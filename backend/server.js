/**
 * Smart Parcel Drop Box Backend Server
 * Supports ESP32-S3 door control and Arduino barcode scanner
 */

require('dotenv').config();
const express = require('express');
const http = require('http');
const socketIO = require('socket.io');
const mongoose = require('mongoose');
const cors = require('cors');

const { router: deviceControlRouter, setSocketIO } = require('./routes/deviceControl');
const arduinoScanner = require('./hardware/arduinoScanner');
const Tracking = require('./models/Tracking');
const ScanLog = require('./models/ScanLog');
const Notification = require('./models/Notification');
const Rider = require('./models/Rider');
const User = require('./models/User');
const Dropbox = require('./models/Dropbox');

// In-memory store for one-time owner QR session tokens { token → expiresAtMs }
const ownerSessions = new Map();

// Feature #2 — Rate-limit requestOwnerSession
// Tracks the last time a session was requested { socketId → timestampMs }
const sessionCooldowns = new Map();
const SESSION_COOLDOWN_MS = 10000; // 10 seconds

// Feature #9 — Pending alert re-emit on reconnect
// Holds an active alert until it expires { userId → expiresAtMs }
const pendingOwnerAlerts = new Map();

// Device Registration — one-time tokens { token → { deviceId, expiresAtMs } }
const pendingRegistrations = new Map();

// Automated Admin Tracking — disabled by default so random barcodes/QRs are rejected
let autoAcceptMode = false;

function escapeRegex(text) {
  return (text || '').replace(/[-[\]{}()*+?.:\\^$|#\s]/g, '\\$&');
}

/**
 * Flexible Tracking ID Matcher (Case-insensitive)
 * 
 * Some couriers (Shopee/J&T) add a 'T' or other suffixes to barcodes
 * that might not be in the user's registered ID.
 */
async function findTrackingFlexibly(inputId) {
  if (!inputId) return null;
  const clean = inputId.trim();
  const escaped = escapeRegex(clean);
  
  // 1. Try case-insensitive exact match
  let tracking = await Tracking.findOne({ trackingId: { $regex: new RegExp(`^${escaped}$`, 'i') } });
  if (tracking) return tracking;
  
  // 2. Try match after removing trailing 'T'
  if (clean.toUpperCase().endsWith('T')) {
    const trimmedId = escapeRegex(clean.substring(0, clean.length - 1));
    console.log(`🔍 [FLEX-MATCH] Trying with trimmed ID: ${trimmedId} (Original: ${inputId})`);
    tracking = await Tracking.findOne({ trackingId: { $regex: new RegExp(`^${trimmedId}$`, 'i') } });
    if (tracking) {
      console.log(`✅ [FLEX-MATCH] Match found after trimming 'T'`);
      return tracking;
    }
  }
  
  // 3. Try matching if DB record has 'T' but scan doesn't
  const appended = escapeRegex(clean + 'T');
  tracking = await Tracking.findOne({ trackingId: { $regex: new RegExp(`^${appended}$`, 'i') } });
  if (tracking) {
    console.log(`✅ [FLEX-MATCH] Match found by appending 'T' back to scan`);
    return tracking;
  }

  return null;
}


// Initialize Express app
const app = express();
const server = http.createServer(app);
const io = socketIO(server, {
  cors: {
    origin: process.env.ALLOWED_ORIGINS || '*',
    methods: ['GET', 'POST']
  },
  // allowEIO3: lets the ESP32 (arduinoWebSockets library) connect using EIO=3
  // while the Flutter app continues to use EIO=4. Without this, the ESP32
  // gets immediately disconnected because it speaks a different protocol version.
  allowEIO3: true,
  // Fast detection of dead connections (e.g. ESP32 powered off)
  pingTimeout: 10000,   // 10s before declaring client dead
  pingInterval: 5000,   // Ping every 5s
});

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Store io in express app for controllers
app.set('io', io);

// Request logging
app.use((req, res, next) => {
  console.log(`📨 ${req.method} ${req.path}`);
  next();
});

// Routes
app.use('/device-control', deviceControlRouter);

// Consolidated API Routes
const userRoutes = require('./routes/userRoutes');
const trackingRoutes = require('./routes/trackingRoutes');
const scanLogRoutes = require('./routes/scanLogRoutes');
const notificationRoutes = require('./routes/notificationRoutes');
const deliveryLogRoutes = require('./routes/deliveryLogRoutes');
const riderRoutes = require('./routes/riderRoutes');

app.use('/api/users', userRoutes);
app.use('/api/tracking', trackingRoutes);
app.use('/api/scan-logs', scanLogRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/delivery-logs', deliveryLogRoutes);
app.use('/api/riders', riderRoutes);

const dropboxRoutes = require('./routes/dropboxRoutes');
const hardwareRoutes = require('./routes/hardwareRoutes');
const businessRoutes = require('./routes/businessRoutes');
const taskRoutes = require('./routes/taskRoutes');
const webhookRoutes = require('./routes/webhookRoutes');
const financialRoutes = require('./routes/financialRoutes');
const paymentRoutes = require('./routes/paymentRoutes');

app.use('/api/dropbox', dropboxRoutes);
app.use('/api/hardware', hardwareRoutes);
app.use('/api/business', businessRoutes);
app.use('/api/tasks', taskRoutes);
app.use('/api/webhooks', webhookRoutes);
app.use('/api/financial', financialRoutes);
app.use('/api/payments', paymentRoutes);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'online',
    timestamp: new Date(),
    mongodb: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected'
  });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    name: 'Smart Parcel Drop Box API',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      deviceControl: '/device-control',
      deviceStatus: '/device-control (GET)',
      deviceHealth: '/device-control/health',
      api: {
        users: '/api/users',
        tracking: '/api/tracking',
        notifications: '/api/notifications'
      }
    }
  });
});

// Socket.IO middleware for authentication
const { verifyToken } = require('./utils/auth');

io.use((socket, next) => {
  const token = socket.handshake.auth.token || socket.handshake.query.token;

  if (token) {
    const decoded = verifyToken(token);
    if (decoded) {
      socket.userId = decoded.userId;
      return next();
    }
  }

  // Allow hardware (ESP32) connection without token if it identifies as such
  // In production, you might want a specific 'hardware secret' for this.
  const isHardware = socket.handshake.query.clientType === 'hardware';
  if (isHardware) {
    socket.isHardware = true;
    return next();
  }

  // For now, allow anonymous if not hardware, but tag it for restricted join
  // This helps with migration, but we should eventually require token for all app clients.
  console.log(`⚠️  Connection without token from ${socket.id}`);
  next();
});

// Socket.IO connection handling
io.on('connection', (socket) => {
  console.log(`🔌 Client connected: ${socket.id} (User: ${socket.userId || 'anonymous/hardware'})`);

  // Device room join
  socket.on('join', async (roomId) => {
    // SECURITY: Only allow joining your OWN roomId or the hardware room if you are hardware
    if (roomId === 'esp32_device') {
      // Hardware room - only for ESP32
      socket.join(roomId);
      socket.isEsp32 = true;
      console.log('✅ ESP32 connected and joined room');
      io.emit('esp32Status', { connected: true, timestamp: new Date() });
    } else {
      // User room - must match authenticated userId
      if (socket.userId && roomId === socket.userId) {
        socket.join(roomId);
        console.log(`📡 User ${socket.userId} joined their private room: ${roomId}`);
      } else {
        console.log(`❌ BLOCK: ${socket.id} tried to join unauthorized room: ${roomId}`);
        return; // Deny join
      }
    }

    // Feature #9 — Re-emit pending owner alert if this user has one waiting
    const alertExpiry = pendingOwnerAlerts.get(roomId);
    if (alertExpiry && Date.now() < alertExpiry) {
      socket.emit('ownerAccessAlert', { timestamp: new Date(), replay: true });
      console.log(`🔔 Re-emitted pending ownerAccessAlert to rejoining user: ${roomId}`);
    }
  });

  // ── ESP32 Status Query (mobile app → backend) ──────────────────────────
  // Flutter emits this when a screen opens to get the CURRENT connection state
  // without waiting for a future connect/disconnect event.
  socket.on('getEsp32Status', () => {
    const room = io.sockets.adapter.rooms.get('esp32_device');
    const connected = !!(room && room.size > 0);
    console.log(`📊 getEsp32Status → ${connected ? 'CONNECTED' : 'OFFLINE'}`);
    socket.emit('esp32Status', { connected, timestamp: new Date() });
  });

  // ── Phase 1: Remote ID Registration (mobile app → ESP32) ──────────────────
  // Flutter app emits this when a user schedules a delivery/pickup
  // Payload: { trackingId: "ABC123", mode: "drop_off" | "pick_up" }
  socket.on('registerTracking', ({ trackingId, mode }) => {
    console.log(`📋 registerTracking → ${trackingId}, mode: ${mode}`);
    // Forward directly to the ESP32 hardware device
    io.to('esp32_device').emit('registerTracking', { trackingId, mode });
    console.log(`  ✅ Forwarded to ESP32: ${trackingId} (${mode})`);
  });

  // ── Door Control (mobile app → ESP32) ─────────────────────────────────────
  // Replaces ESP32_DoorControl.ino's POST /door HTTP endpoint.
  // Payload: { type: "top"|"pickup"|"received", action: "open"|"close" }
  socket.on('controlDoor', ({ type, action }) => {
    console.log(`🚪 controlDoor → ${type} door: ${action}`);
    io.to('esp32_device').emit('controlDoor', { type, action });
  });

  // ── Status Poll (mobile app → ESP32) ──────────────────────────────────────
  // Replaces ESP32_DoorControl.ino's GET /status HTTP endpoint.
  // ESP32 responds by emitting a 'doorStateUpdate' event back to all clients.
  socket.on('getStatus', () => {
    console.log(`📊 getStatus requested`);
    io.to('esp32_device').emit('getStatus');
  });

  // ── Phase 2: Scan Verification ──────────────────────────────────────────

  socket.on('verifyScan', async ({ trackingId, mode }) => {
    console.log(`🔍 verifyScan → trackingId: ${trackingId}, mode: ${mode}`);
    try {
      let tracking = await findTrackingFlexibly(trackingId);

      // Case 1: Tracking ID doesn't exist at all
      if (!tracking) {
        if (autoAcceptMode) {
          console.log(`  ✨ AUTO-REGISTER (TEST MODE): Creating new tracking for ${trackingId}`);
          const adminUser = await User.findOne({ role: 'admin' });
          const userId = adminUser ? adminUser._id.toString() : 'hardware_auto_accepted';
          
          tracking = await Tracking.create({
            trackingId,
            userId,
            shopName: 'Auto-Accepted Parcel',
            status: 'pending',
            mode: mode || 'drop_off'
          });
        } else {
          console.log(`  ❌ UNREGISTERED BARCODE REJECTED: ${trackingId}`);
          await ScanLog.create({
            scannedId: trackingId,
            accessGranted: false,
            mode: mode,
            status: 'rejected',
            reason: 'not_registered'
          });
          socket.emit('scanResult', {
            valid: false,
            trackingId,
            mode,
            userId: null,
            reason: 'not_registered'
          });
          return;
        }
      }

      // Case 2: Already completed — parcel was already delivered/done/retrieved
      const completedStatuses = ['delivered', 'done', 'retrieved'];
      if (completedStatuses.includes(tracking.status)) {
        console.log(`  ⚠️  ALREADY COMPLETED (${tracking.status}): ${trackingId}`);
        await ScanLog.create({
          scannedId: trackingId,
          accessGranted: false,
          mode: mode,
          status: 'rejected',
          trackingId: tracking.trackingId,
          userId: tracking.userId,
          reason: 'already_completed'
        });
        await Notification.create({
          userId: tracking.userId,
          title: 'Scan Rejected',
          message: `Tracking ID ${trackingId} was scanned but is already marked as ${tracking.status}.`,
          type: 'system_alert'
        });
        socket.emit('scanResult', {
          valid: false,
          trackingId,
          mode,
          userId: tracking.userId,
          reason: 'already_completed',
          currentStatus: tracking.status
        });
        return;
      }

      // Case 3: Status mismatch for the requested mode.
      // E.g., a pick_up scan on a parcel that is still 'pending',
      // or a drop_off scan on a parcel that is already 'awaiting_pickup'.
      const isPickUpMode = (mode === 'pick_up' || mode === 'pickup');
      const allowedStatuses = isPickUpMode
        ? ['ready_for_pickup', 'awaiting_pickup', 'pending']
        : ['pending', 'in_transit'];

      if (!allowedStatuses.includes(tracking.status)) {
        console.log(`  ⚠️  WRONG STATUS (${tracking.status}): ${trackingId} expected one of [${allowedStatuses.join(', ')}] for mode ${mode}`);
        await ScanLog.create({
          scannedId: trackingId,
          accessGranted: false,
          mode: mode,
          status: 'rejected',
          trackingId: tracking.trackingId,
          userId: tracking.userId,
          reason: 'wrong_status'
        });
        await Notification.create({
          userId: tracking.userId,
          title: 'Scan Rejected',
          message: `Tracking ID ${trackingId} was scanned for ${isPickUpMode ? 'Pick Up' : 'Drop Off'} but its status is currently: ${tracking.status}.`,
          type: 'system_alert'
        });
        socket.emit('scanResult', {
          valid: false,
          trackingId,
          mode,
          userId: tracking.userId,
          reason: 'wrong_status',
          currentStatus: tracking.status
        });
        return;
      }

      // Case 4: Valid — tracking is pending and ready to be processed
      console.log(`  ✅ VALID: ${trackingId}`);
      await ScanLog.create({
        scannedId: trackingId,
        accessGranted: true,
        mode: mode,
        status: 'authorized',
        trackingId: tracking.trackingId,
        userId: tracking.userId,
        reason: 'Authorized'
      });
      await Notification.create({
        userId: tracking.userId,
        title: 'Scan Successful',
        message: `Access granted for ${mode === 'drop_off' ? 'Drop Off' : 'Pick Up'} using tracking ID ${trackingId}.`,
        type: mode === 'drop_off' ? 'delivery_scheduled' : 'parcel_picked_up'
      });

      socket.emit('scanResult', {
        valid: true,
        trackingId,
        mode,
        userId: tracking.userId,
        reason: 'ok'
      });

    } catch (err) {
      console.error('❌ verifyScan error:', err.message);
      socket.emit('scanResult', { valid: false, trackingId, mode, userId: null, reason: 'server_error' });
    }
  });

  // ── Rider Verification ──────────────────────────────────────────────────
  // ESP32 emits this when rider scans their QR code
  // Payload: { riderId: "RIDER-001" }
  socket.on('verifyRider', async ({ riderId }) => {
    console.log(`🚴 verifyRider → checking ID: ${riderId}`);
    try {
      if (!riderId || riderId.length < 3) {
        return socket.emit('riderVerifyResult', { valid: false, riderId });
      }

      // Check MongoDB for registered Rider ID
      const rider = await Rider.findOne({ riderId: riderId });
      const valid = !!rider;
      console.log(`  ${valid ? `✅ RIDER VALID (${rider.name})` : '❌ RIDER INVALID'}: ${riderId}`);

      socket.emit('riderVerifyResult', { valid, riderId });
    } catch (err) {
      console.error('❌ verifyRider error:', err.message);
      socket.emit('riderVerifyResult', { valid: false, riderId });
    }
  });

  // ── Owner QR Session Request (ESP32 → backend → app) ───────────────────
  // Feature #1: Targets only the admin (owner) user's Socket.IO room.
  // Feature #2: Rate-limited to once per 10 seconds.
  // Feature #3: Creates an audit log entry on every attempt.
  socket.on('requestOwnerSession', async () => {
    // Feature #2 — Rate-limit
    const lastRequest = sessionCooldowns.get(socket.id) || 0;
    if (Date.now() - lastRequest < SESSION_COOLDOWN_MS) {
      console.log('⚠️  requestOwnerSession rate-limited — too soon after last request');
      return;
    }
    sessionCooldowns.set(socket.id, Date.now());

    // Feature #6: Generate a simple 6-digit PIN for manual entry fallback
    const pin = Math.floor(100000 + Math.random() * 900000).toString();
    const token = `OWN-${pin}`;
    const expiresAt = Date.now() + 65000; // 65s TTL (60s scan window + 5s buffer)
    ownerSessions.set(token, expiresAt);
    console.log(`🔑 requestOwnerSession → generated token: ${token}`);
    socket.emit('ownerSessionToken', { token });
    setTimeout(() => ownerSessions.delete(token), 70000); // auto-cleanup

    try {
      // Feature #1 — Find admin user, emit only to their room
      const owner = await User.findOne({ role: 'admin' }).select('_id');
      if (owner) {
        const ownerRoom = owner._id.toString();
        io.to(ownerRoom).emit('ownerAccessAlert', { timestamp: new Date() });
        console.log(`🔔 ownerAccessAlert → room: ${ownerRoom}`);

        // Feature #9 — Store pending alert so reconnecting owner still gets it
        pendingOwnerAlerts.set(ownerRoom, expiresAt);
        setTimeout(() => pendingOwnerAlerts.delete(ownerRoom), 70000);
      } else {
        // Fallback: no admin user found — broadcast to all app clients
        socket.broadcast.emit('ownerAccessAlert', { timestamp: new Date() });
        console.log('⚠️  No admin user found; ownerAccessAlert broadcast to all clients');
      }

      // Feature #3 — Audit log: record the access attempt
      await ScanLog.create({
        scannedId: token,
        accessGranted: null,
        mode: 'owner_verify',
        status: 'pending',
        reason: 'owner_qr_requested',
        userId: owner ? owner._id.toString() : 'unknown'
      });
    } catch (err) {
      console.error('❌ requestOwnerSession DB error:', err.message);
      socket.broadcast.emit('ownerAccessAlert', { timestamp: new Date() });
    }
  });

  // ── Owner QR Verification (Flutter → backend → ESP32) ───────────────────
  // Flutter app scans the QR code on the LCD and emits this event.
  // Feature #3: Updates the audit log with the outcome.
  socket.on('verifyOwnerQR', async ({ token }) => {
    console.log(`🔑 verifyOwnerQR → token: ${token}`);
    const expiresAt = ownerSessions.get(token);
    const approved = !!(expiresAt && Date.now() < expiresAt);
    ownerSessions.delete(token); // one-time use
    console.log(`  ${approved ? '✅ OWNER APPROVED' : '❌ OWNER DENIED/EXPIRED'}`);
    io.to('esp32_device').emit('ownerVerifyResult', { approved });
    socket.emit('ownerVerifyAck', { approved, token });

    // Feature #3 — Update the audit log entry with the result
    try {
      await ScanLog.findOneAndUpdate(
        { scannedId: token, mode: 'owner_verify' },
        { $set: {
            accessGranted: approved,
            status: approved ? 'authorized' : 'rejected',
            reason: approved ? 'owner_qr_approved' : 'owner_qr_denied_or_expired'
        }}
      );
    } catch (err) {
      console.error('❌ verifyOwnerQR audit log update error:', err.message);
    }
  });


  // ── Owner Pickup Registration ────────────────────────────────────────────
  // ESP32 emits this when owner scans a waybill QR at the box
  // Payload: { trackingId: "ABC123" }
  socket.on('registerOwnerPickup', async ({ trackingId }) => {
    console.log(`📦 registerOwnerPickup → trackingId: ${trackingId}`);
    try {
      // Find tracking flexibly to get userId for notification
      let tracking = await findTrackingFlexibly(trackingId);
      
      // Use the actual registered tracking ID from the database for the update
      // so we don't accidentally create a duplicate with/without the 'T'
      const actualId = tracking ? tracking.trackingId : trackingId;

      // Default to null if upserted a new one, but if we create it here we need a mode
      // so Flutter knows it's a pickup.
      await Tracking.updateOne(
        { trackingId: actualId },
        {
          $set: {
            status: 'awaiting_pickup',
            registeredAt: new Date(),
            mode: 'pick_up'
          },
          // Assign to anonymous/hardware user if brand new, so it doesn't break schema
          $setOnInsert: {
            userId: tracking ? tracking.userId : 'hardware_generated_pickup'
          }
        },
        { upsert: true }
      );

      // Default to null if upserted a new one and we can't notify a specific user
      const userId = tracking ? tracking.userId : null;

      if (userId) {
        await Notification.create({
          userId,
          title: 'Pickup Ready',
          message: `Tracking ID ${trackingId} is now awaiting pickup at the box.`,
          type: 'system_alert'
        });
      }

      io.emit('trackingStatusChanged', {
        trackingId,
        status: 'awaiting_pickup',
        timestamp: new Date()
      });
      console.log(`  ✅ Owner pickup registered: ${trackingId}`);
      
      // Feature: Increment logical pickupCount
      // Multi-user: search userIds array, fall back to legacy userId field
      if (tracking && tracking.userId) {
        let dbQuery = { userIds: tracking.userId };
        const existsByArray = await Dropbox.findOne(dbQuery);
        if (!existsByArray) dbQuery = { userId: tracking.userId };
        await Dropbox.updateOne(dbQuery, { $inc: { pickupCount: 1 } });
      }
    } catch (err) {
      console.error('❌ registerOwnerPickup error:', err.message);
    }
  });

  // ── Phase 3: Status Update (hardware → backend → mobile app) ────────────
  // ESP32 emits this after a successful drop-off or pick-up cycle
  // Payload: { trackingId: "ABC123", status: "delivered", mode: "drop_off" }
  socket.on('statusUpdate', async ({ trackingId, status, mode }) => {
    console.log(`📦 statusUpdate → ${trackingId}: ${status}`);
    try {
      const tracking = await findTrackingFlexibly(trackingId);
      const actualId = tracking ? tracking.trackingId : trackingId;

      const update = { status };
      if (status === 'delivered') update.deliveredAt = new Date();
      if (status === 'retrieved') update.retrievedAt = new Date();
      if (status === 'done') update.doneAt = new Date();
  
      await Tracking.updateOne({ trackingId: actualId }, { $set: update });

      if (tracking && tracking.userId) {
        let title = 'Status Update';
        let body = `Tracking ID ${trackingId} status changed to ${status}.`;
        let type = 'system';

        if (status === 'delivered' || status === 'done') {
          title = 'Parcel Delivered';
          body = `Your parcel (${trackingId}) has been successfully dropped off in the box.`;
          type = 'parcel_delivered';
        } else if (status === 'retrieved') {
          title = 'Parcel Retrieved';
          body = `Your parcel (${trackingId}) has been successfully retrieved from the box.`;
          type = 'parcel_picked_up';
        }

        await Notification.create({
          userId: tracking.userId,
          title,
          message: body,
          type: type === 'system' ? 'system_alert' : type
        });
      }

      // Broadcast to all connected mobile app clients
      io.emit('trackingStatusChanged', {
        trackingId,
        status,
        mode,
        timestamp: new Date()
      });

      // Feature: Update logical counts
      // Multi-user: find the dropbox by userIds array (or legacy userId fallback)
      if (tracking && tracking.userId) {
        let dropbox = await Dropbox.findOne({ userIds: tracking.userId });
        if (!dropbox) dropbox = await Dropbox.findOne({ userId: tracking.userId });
        if (dropbox) {
          let countUpdate = {};
          if (mode === 'drop_off') {
            if (status === 'delivered' || status === 'done') countUpdate.dropoffCount = (dropbox.dropoffCount || 0) + 1;
            if (status === 'retrieved') countUpdate.dropoffCount = Math.max(0, (dropbox.dropoffCount || 0) - 1);
          } else if (mode === 'pick_up' || mode === 'pickup') {
            if (status === 'retrieved' || status === 'done') countUpdate.pickupCount = Math.max(0, (dropbox.pickupCount || 0) - 1);
          }

          if (Object.keys(countUpdate).length > 0) {
            await Dropbox.updateOne({ _id: dropbox._id }, { $set: countUpdate });
            const updated = await Dropbox.findById(dropbox._id);
            // Re-emit logical counts to all connected app clients
            io.emit('binStatusUpdate', {
              logicalDropoffCount: updated.dropoffCount,
              logicalPickupCount: updated.pickupCount,
              timestamp: new Date()
            });
          }
        }
      }

      console.log(`✅ Status broadcasted: ${trackingId} → ${status}`);
    } catch (err) {
      console.error('❌ statusUpdate error:', err.message);
    }
  });

  // ── Sensor / Bin Status (ESP32 → backend → mobile app) ─────────────────
  // ESP32 emits this periodically or on change with ultrasonic + reed readings
  // Payload: { US_PICKUP: <cm>, US_DROPOFF: <cm>, REED_TOP: bool, REED_PICKUP: bool, REED_RECEIVED: bool }
  socket.on('sensorUpdate', async (data) => {
    console.log(`📡 sensorUpdate:`, data);

    // Find the most recently active registered device to inject logical counts.
    // isRegistered: true ensures we only use active devices, not wiped ones.
    const dropbox = await Dropbox.findOne({ isRegistered: true }).sort({ updatedAt: -1 });

    io.emit('binStatusUpdate', {
      ...data,
      logicalDropoffCount: dropbox ? dropbox.dropoffCount : 0,
      logicalPickupCount: dropbox ? dropbox.pickupCount : 0,
      timestamp: new Date()
    });
  });

  // ── Device Registration (hardware → backend → app) ─────────────────────
  // ESP32 emits this when in DEVICE_UNREGISTERED state and user presses BTN1.
  // Payload: { deviceId: "AA:BB:CC:DD:EE:FF" }  (MAC address)
  socket.on('requestDeviceRegistration', async ({ deviceId, alreadyConnected }) => {
    if (!deviceId) return;
    const pin = Math.floor(100000 + Math.random() * 900000).toString();
    const token = `SPDB-REG-${pin}`;
    const expiresAt = Date.now() + 65000; // 65s TTL
    pendingRegistrations.set(token, { deviceId, expiresAt, alreadyConnected: !!alreadyConnected });
    setTimeout(() => pendingRegistrations.delete(token), 70000);
    console.log(`🆕 requestDeviceRegistration → deviceId: ${deviceId}, token: ${token}, alreadyConnected: ${alreadyConnected}`);
    // Send token back to hardware so it can render as QR + readable code
    socket.emit('registrationToken', { token, pin });
    // Update lastSeenAt for existing registration if already registered
    try {
      await Dropbox.findOneAndUpdate({ deviceId }, { $set: { lastSeenAt: new Date() } });
    } catch (_) {}
  });

  // ── User registers device via app QR scan ───────────────────────────────
  // App emits this after scanning the QR code shown on the LCD.
  // Multi-user: subsequent scans ADD the user to userIds without removing others.
  // Payload: { token: "SPDB-REG-123456", userId: "...", deviceName: "Home" }
  socket.on('registerDevice', async ({ token, userId, deviceName }) => {
    console.log(`📱 registerDevice → token: ${token}, userId: ${userId}`);
    const entry = pendingRegistrations.get(token);
    if (!entry || Date.now() > entry.expiresAt) {
      console.log('  ❌ Invalid or expired registration token');
      socket.emit('deviceRegistrationFailed', { reason: 'invalid_or_expired_token' });
      return;
    }
    pendingRegistrations.delete(token);
    const { deviceId } = entry;
    try {
      // Check if this user is already registered to this device
      const existing = await Dropbox.findOne({ deviceId });
      const alreadyRegisteredByUser = existing && (existing.userIds || []).includes(userId);

      if (alreadyRegisteredByUser) {
        console.log(`  ℹ️  User ${userId} is already registered to device ${deviceId}`);
        socket.emit('deviceRegistered', {
          deviceId,
          dropbox: existing,
          alreadyConnected: !!entry.alreadyConnected,
        });
        io.to('esp32_device').emit('deviceRegistered', { deviceId });
        return;
      }

      // $addToSet ensures the userId is added only once even if called multiple times
      // $setOnInsert only runs when a brand-new document is created (upsert)
      const dropbox = await Dropbox.findOneAndUpdate(
        { deviceId },
        {
          $addToSet: { userIds: userId },
          $set: {
            name: deviceName || 'My Smart Parcel Dropbox',
            isRegistered: true,
            status: 'offline',
            registeredAt: new Date(),
          },
          $setOnInsert: {
            primaryUserId: userId,
          },
        },
        { upsert: true, new: true }
      );

      // Promote to primaryUserId if field is still unset (legacy migration path)
      if (!dropbox.primaryUserId) {
        await Dropbox.updateOne({ _id: dropbox._id }, { $set: { primaryUserId: userId } });
      }

      const registeredUserCount = dropbox.userIds ? dropbox.userIds.length : 1;
      console.log(`  ✅ Device registered: ${deviceId} → user: ${userId} (total users: ${registeredUserCount})`);

      // Notify the registering app client
      socket.emit('deviceRegistered', {
        deviceId,
        dropbox,
        alreadyConnected: !!entry.alreadyConnected,
      });
      // Notify hardware to save registered flag
      io.to('esp32_device').emit('deviceRegistered', { deviceId });
    } catch (err) {
      console.error('❌ registerDevice DB error:', err.message);
      socket.emit('deviceRegistrationFailed', { reason: 'server_error' });
    }
  });
  
  // ── Unregister Device (mobile app → backend) ─────────────────────────────
  // App emits this to remove a user's own access to the dropbox.
  // Multi-user: only pulls this userId out of userIds. The device stays registered
  // for other users. Hardware is notified only when the LAST user unregisters.
  // Payload: { userId: "..." }
  socket.on('unregisterDevice', async ({ userId }) => {
    console.log(`📱 unregisterDevice → userId: ${userId}`);
    if (!userId) return;
    try {
      // Support both new (userIds array) and legacy (userId) documents
      let dropbox = await Dropbox.findOne({ userIds: userId });
      if (!dropbox) dropbox = await Dropbox.findOne({ userId });

      if (!dropbox) {
        console.log(`  ❌ No dropbox found for userId: ${userId}`);
        socket.emit('deviceUnregistrationFailed', { reason: 'no_device_found' });
        return;
      }

      const { deviceId } = dropbox;

      // 1. Pull this user out of userIds
      await Dropbox.updateOne(
        { _id: dropbox._id },
        { $pull: { userIds: userId } }
      );

      // 2. Reload to count remaining users
      const updated = await Dropbox.findById(dropbox._id);
      const remainingUsers = updated ? updated.userIds || [] : [];

      if (remainingUsers.length === 0) {
        // Last user — fully reset the device
        await Dropbox.updateOne(
          { _id: dropbox._id },
          {
            $set: {
              isRegistered: false,
              primaryUserId: null,
              userId: null,
              name: 'Unregistered Device',
              status: 'unregistered',
              wifiSSID: null,
            }
          }
        );
        console.log(`  ✅ Device ${deviceId} fully unregistered (no remaining users)`);
        // Notify hardware to revert to setup mode
        io.to('esp32_device').emit('deviceUnregistered', { deviceId });
      } else {
        console.log(`  ✅ User ${userId} removed from device ${deviceId} (${remainingUsers.length} user(s) remaining)`);
      }

      // 3. Notify requesting app client
      socket.emit('deviceUnregistered', { deviceId, success: true, remainingUsers: remainingUsers.length });

    } catch (err) {
      console.error('❌ unregisterDevice error:', err.message);
      socket.emit('deviceUnregistrationFailed', { reason: 'server_error' });
    }
  });

  // ── Push WiFi Config (app → backend → hardware) ─────────────────────────
  // App emits this after registration to send WiFi credentials to the device.
  // Payload: { ssid: "HomeWiFi", password: "secret" }
  socket.on('pushHardwareConfig', async ({ ssid, password }) => {
    console.log(`⚙️  pushHardwareConfig → ssid: ${ssid}`);
    // Forward to hardware
    io.to('esp32_device').emit('applyHardwareConfig', { ssid, password });
    // Update MongoDB with last known SSID
    if (socket._userId) {
      await Dropbox.findOneAndUpdate({ userId: socket._userId }, { $set: { wifiSSID: ssid } }).catch(() => {});
    }
  });

  // ── WiFi Scanning (app ↔ backend ↔ hardware) ─────────────────────────────
  socket.on('requestWiFiScan', () => {
    console.log(`📡 requestWiFiScan requested by ${socket.id}`);
    io.to('esp32_device').emit('requestWiFiScan');
  });

  socket.on('wifiScanResult', (data) => {
    console.log(`📡 wifiScanResult received from hardware: ${data.networks ? data.networks.length : 0} networks`);
    // Relay to all app clients
    socket.broadcast.emit('wifiScanResult', data);
  });

  // ── Hardware confirms config saved (hardware → backend → app) ───────────
  socket.on('hardwareConfigApplied', async ({ deviceId }) => {
    console.log(`✅ hardwareConfigApplied → device: ${deviceId}`);
    try {
      await Dropbox.findOneAndUpdate({ deviceId }, { $set: { status: 'offline', lastSeenAt: new Date() } });
      // Find owner and notify app
      const dropbox = await Dropbox.findOne({ deviceId });
      if (dropbox) {
        io.to(dropbox.userId).emit('hardwareConfigApplied', { deviceId });
      }
    } catch (err) {
      console.error('❌ hardwareConfigApplied error:', err.message);
    }
  });

  // ── Automated Admin Tracking Events ─────────────────────────────────────
  socket.on('toggleAutoAccept', () => {
    autoAcceptMode = !autoAcceptMode;
    console.log(`🤖 autoAcceptMode toggled: ${autoAcceptMode}`);
    io.emit('autoAcceptStatus', { enabled: autoAcceptMode });
  });
  socket.on('getAutoAcceptStatus', () => {
    socket.emit('autoAcceptStatus', { enabled: autoAcceptMode });
  });

  socket.on('disconnect', () => {
    console.log(`🔌 Client disconnected: ${socket.id}`);
    // socket.rooms is EMPTY by the time disconnect fires — use the flag we stamped at join time
    if (socket.isEsp32) {
      console.log('⚠️  ESP32 disconnected');
      io.emit('esp32Status', { connected: false, timestamp: new Date() });
    }
  });
});

// Pass socket.io to routes
setSocketIO(io);

// Initialize Arduino Scanner
async function initializeScanner() {
  const connected = await arduinoScanner.connect();
  if (connected) {
    // Handle barcode scans
    arduinoScanner.onBarcodeScan((barcode) => {
      console.log(`📦 Broadcasting barcode: ${barcode}`);
      io.emit('barcodeScan', { barcode, timestamp: new Date() });
    });
  } else {
    console.warn('⚠️  Arduino Scanner not connected. Barcode scanning disabled.');
  }
}

// Connect to MongoDB
async function connectDatabase() {
  try {
    const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/smart_parcel_dropbox';
    await mongoose.connect(mongoUri);
    console.log('✅ MongoDB connected');
  } catch (error) {
    console.error('❌ MongoDB connection error:', error.message);
    console.log('⚠️  Server will run without database. Some features may not work.');
  }
}

// Start server
async function startServer() {
  const PORT = process.env.PORT || 3000;

  // Connect to database
  await connectDatabase();

  // Initialize hardware
  await initializeScanner();

  // Start HTTP server
  server.listen(PORT, () => {
    console.log('');
    console.log('🚀 ========================================');
    console.log(`🚀 Server running on port ${PORT}`);
    console.log(`🚀 http://localhost:${PORT}`);
    console.log('🚀 ========================================');
    console.log('');
    console.log('📡 WebSocket server ready');
    console.log('🔧 ESP32-S3 IP:', process.env.ESP32_IP || '10.63.248.x (Waiting for connection...)');
    console.log('🔧 Scanner Port:', process.env.SCANNER_PORT || 'COM3');
    console.log('');
  });
}

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n🛑 Shutting down gracefully...');
  arduinoScanner.disconnect();
  await mongoose.connection.close();
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
});

// Start the server
startServer().catch((error) => {
  console.error('❌ Failed to start server:', error);
  process.exit(1);
});
