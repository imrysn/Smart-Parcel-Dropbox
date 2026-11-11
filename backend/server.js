/**
 * Smart Parcel Drop Box Backend Server
 * Supports ESP32-S3 door control and Arduino barcode scanner
 */

if (require.main === module) require('dotenv').config();
const express = require('express');
const http = require('http');
const socketIO = require('socket.io');
const mongoose = require('mongoose');
const cors = require('cors');
const { randomBytes, randomInt, randomUUID } = require('node:crypto');

const { router: deviceControlRouter, setSocketIO } = require('./routes/deviceControl');
const arduinoScanner = require('./hardware/arduinoScanner');
const Tracking = require('./models/Tracking');
const ScanLog = require('./models/ScanLog');
const Notification = require('./models/Notification');
const deliveryPush = require('./utils/deliveryPush');
const Rider = require('./models/Rider');
const User = require('./models/User');
const Dropbox = require('./models/Dropbox');
const { verifyEmailTransport } = require('./utils/emailService');
const {
  verifyDeviceProof, normalizeDeviceId, deviceRoom, membersOf, pairedBoxForUser,
  registeredBoxForDevice, emitToMembers, isDeviceOnline, recordDoorState,
  commandDoor, confirmDoorCommand, deviceDisconnected,
} = require('./utils/deviceSessions');

// Owner credentials are short-lived and bound to a single registered device.
const ownerSessions = new Map();
const ownerPasses = new Map();

// Feature #2 — Rate-limit requestOwnerSession
// Tracks the last time a session was requested { socketId → timestampMs }
const sessionCooldowns = new Map();
const SESSION_COOLDOWN_MS = 10000; // 10 seconds


// Device Registration — one-time tokens { token → { deviceId, expiresAtMs } }
const { pendingRegistrations } = require('./controllers/hardwareController');

// Automated Admin Tracking — disabled by default so random barcodes/QRs are rejected
const autoAcceptDevices = new Set();

function escapeRegex(text) {
  return (text || '').replace(/[-[\]{}()*+?.:\\^$|#\s]/g, '\\$&');
}

/**
 * Flexible Tracking ID Matcher (Case-insensitive)
 * 
 * Some couriers (Shopee/J&T) add a 'T' or other suffixes to barcodes
 * that might not be in the user's registered ID.
 */
async function findTrackingFlexibly(inputId, userIds) {
  if (typeof inputId !== 'string' || !inputId.trim() || !userIds.length) return null;
  const clean = inputId.trim();
  const escaped = escapeRegex(clean);
  const scope = { userId: { $in: userIds } };
  
  // 1. Try case-insensitive exact match
  let tracking = await Tracking.findOne({ ...scope, trackingId: { $regex: new RegExp(`^${escaped}$`, 'i') } });
  if (tracking) return tracking;
  
  // 2. Try match after removing trailing 'T'
  if (clean.toUpperCase().endsWith('T')) {
    const trimmedId = escapeRegex(clean.substring(0, clean.length - 1));
    console.log(`🔍 [FLEX-MATCH] Trying with trimmed ID: ${trimmedId} (Original: ${inputId})`);
    tracking = await Tracking.findOne({ ...scope, trackingId: { $regex: new RegExp(`^${trimmedId}$`, 'i') } });
    if (tracking) {
      console.log(`✅ [FLEX-MATCH] Match found after trimming 'T'`);
      return tracking;
    }
  }
  
  // 3. Try matching if DB record has 'T' but scan doesn't
  const appended = escapeRegex(clean + 'T');
  tracking = await Tracking.findOne({ ...scope, trackingId: { $regex: new RegExp(`^${appended}$`, 'i') } });
  if (tracking) {
    console.log(`✅ [FLEX-MATCH] Match found by appending 'T' back to scan`);
    return tracking;
  }

  // 4. Try matching Courier Pickup OTP PIN (e.g. 6-digit PIN scanned or entered)
  if (/^\d{6}$/.test(clean)) {
    tracking = await Tracking.findOne({ ...scope, courierOtp: clean, courierOtpExpiresAt: { $gt: new Date() }, status: { $in: ['awaiting_pickup', 'ready_for_pickup', 'pending'] } });
    if (tracking) {
      console.log(`✅ [FLEX-MATCH] Match found by Courier Pickup OTP: ${clean}`);
      return tracking;
    }
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
const webhookRoutes = require('./routes/webhookRoutes');

app.use('/api/dropbox', dropboxRoutes);
app.use('/api/hardware', hardwareRoutes);
app.use('/api/business', businessRoutes);
app.use('/api/webhooks', webhookRoutes);

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

// Public Digital Courier Pickup Pass Mobile Web View
app.get('/pass/:trackingId', async (req, res) => {
  try {
    const { trackingId } = req.params;
    const tracking = await Tracking.findOne({ trackingId });
    const courier = tracking?.courierName || 'Courier';
    const customer = tracking?.customerName || 'Customer';
    const shop = tracking?.shopName || 'Smart Parcel Dropbox';
    const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=320x320&data=${encodeURIComponent(trackingId)}`;

    res.send(`
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Pickup Pass - ${trackingId}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
    body { background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 20px; }
    .card { background: #1e293b; border-radius: 24px; padding: 28px 24px; width: 100%; max-width: 380px; text-align: center; border: 1px solid #334155; box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.5); }
    .badge { display: inline-block; background: rgba(16, 185, 129, 0.15); color: #10b981; font-size: 11px; font-weight: 800; padding: 4px 10px; border-radius: 9999px; letter-spacing: 1px; margin-bottom: 12px; }
    h1 { font-size: 20px; font-weight: 800; margin-bottom: 4px; }
    .subtitle { color: #94a3b8; font-size: 13px; margin-bottom: 20px; }
    .qr-box { background: #ffffff; padding: 18px; border-radius: 18px; display: inline-block; margin-bottom: 14px; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.2); }
    .qr-box img { display: block; width: 220px; height: 220px; }
    .tracking-code { font-family: monospace; font-size: 17px; font-weight: 700; color: #cbd5e1; letter-spacing: 2px; margin-bottom: 18px; }
    .steps { background: rgba(15, 23, 42, 0.6); border-radius: 14px; padding: 14px; text-align: left; font-size: 12px; color: #94a3b8; line-height: 1.6; border: 1px solid #334155; }
    .steps strong { color: #f8fafc; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">COURIER PICKUP PASS</div>
    <h1>${courier} Pickup</h1>
    <div class="subtitle">Order for ${customer} • ${shop}</div>
    <div class="qr-box">
      <img src="${qrUrl}" alt="QR Code">
    </div>
    <div class="tracking-code">${trackingId}</div>
    <div class="steps">
      <strong>How to Unlock:</strong><br>
      1. Arrive at the Smart Parcel Drop Box.<br>
      2. Press the physical <strong>PICKUP</strong> button.<br>
      3. Hold this QR code (or your <strong>${courier}</strong> app barcode) to the optical scanner.<br>
      4. Door unlocks automatically!
    </div>
  </div>
</body>
</html>
    `);
  } catch (err) {
    res.status(500).send('Error loading pickup pass');
  }
});

// Socket.IO middleware for authentication
const { verifyToken, checkSigningKey } = require('./utils/auth');

io.use((socket, next) => {
  const decoded = verifyToken(socket.handshake.auth?.token);
  if (decoded?.userId) {
    socket.userId = decoded.userId;
    socket.sessionExpiresAt = decoded.exp * 1000;
    return next();
  }
  if (socket.handshake.query.clientType === 'hardware') {
    socket.deviceNonce = randomBytes(24).toString('hex');
    return next();
  }
  next(new Error('Authentication required'));
});

async function emitCurrentOwnerAlert(socket) {
  const box = await pairedBoxForUser(socket.userId);
  if (!box) return;
  for (const session of ownerSessions.values()) {
    if (session.deviceId === box.deviceId && session.expiresAt > Date.now()) {
      socket.emit('ownerAccessAlert', { alertId: session.alertId, expiresAt: session.expiresAt, deviceId: box.deviceId });
    }
  }
}

async function publishPresence(deviceId) {
  const box = await registeredBoxForDevice(deviceId);
  const connected = isDeviceOnline(io, deviceId);
  if (box) {
    const presence = connected ? { status: 'online', lastSeenAt: new Date() } : { status: 'offline' };
    await Dropbox.updateOne({ _id: box._id }, { $set: presence });
    emitToMembers(io, box, 'esp32Status', { connected });
  }
}

io.on('connection', (socket) => {
  const on = (name, handler) => socket.on(name, async (...args) => {
    try {
      if (name !== 'disconnect' && socket.userId && socket.sessionExpiresAt <= Date.now()) {
        socket.disconnect(true);
        return;
      }
      await handler(...args);
    } catch (err) {
      console.error('Socket handler failed:', name, err.message);
      const reply = args.at(-1);
      if (typeof reply === 'function') reply({ ok: false, reason: 'server_error' });
    }
  });

  if (socket.userId) {
    socket.join(socket.userId);
  } else {
    const challengeTimer = setTimeout(() => {
      if (!socket.deviceId) socket.disconnect(true);
    }, 5000);
    challengeTimer.unref();
    socket.once('disconnect', () => clearTimeout(challengeTimer));
    on('authenticateDevice', (data) => {
      const nonce = socket.deviceNonce;
      socket.deviceNonce = null;
      const deviceId = normalizeDeviceId(data?.deviceId);
      if (!verifyDeviceProof(deviceId, nonce, data?.proof)) {
        socket.disconnect(true);
        return;
      }
      clearTimeout(challengeTimer);
      const room = deviceRoom(deviceId);
      for (const id of io.sockets.adapter.rooms.get(room) || []) io.sockets.sockets.get(id)?.disconnect(true);
      socket.deviceId = deviceId;
      socket.join(room);
      socket.emit('deviceAuthenticated');
      return publishPresence(deviceId);
    });
    socket.emit('deviceChallenge', { nonce: socket.deviceNonce });
  }

  on('join', async roomId => {
    if (socket.userId && roomId === socket.userId) await emitCurrentOwnerAlert(socket);
  });
  on('requestOwnerAlert', () => emitCurrentOwnerAlert(socket));

  on('getEsp32Status', async () => {
    if (!socket.userId) return;
    const box = await pairedBoxForUser(socket.userId);
    socket.emit('esp32Status', {
      deviceId: box?.deviceId, connected: isDeviceOnline(io, box?.deviceId), diagnostics: box?.diagnostics,
    });
  });

  on('deviceHeartbeat', async (data) => {
    if (!socket.deviceId || !socket.connected || !data) return;
    const now = new Date();
    if (now.getTime() - (socket.lastHeartbeatAt ?? 0) < 25000) return;
    const { firmwareVersion, wifiRssi, uptimeSeconds } = data;
    if (typeof firmwareVersion !== 'string' || !/^[\w.-]{1,40}$/.test(firmwareVersion) ||
        !Number.isInteger(wifiRssi) || wifiRssi < -127 || wifiRssi > 0 ||
        !Number.isSafeInteger(uptimeSeconds) || uptimeSeconds < 0) return;
    socket.lastHeartbeatAt = now.getTime();
    const diagnostics = { firmwareVersion, wifiRssi, uptimeSeconds, reportedAt: now };
    const box = await Dropbox.findOneAndUpdate({
      deviceId: socket.deviceId,
      isRegistered: true,
      $or: [{ 'diagnostics.reportedAt': { $exists: false } }, { 'diagnostics.reportedAt': { $lt: now } }],
    }, { $set: { diagnostics }, $max: { lastSeenAt: now } }, { new: true });
    if (box && socket.connected) emitToMembers(io, box, 'esp32Status', { connected: true, diagnostics });
  });

  on('registerTracking', async (data) => {
    const box = await pairedBoxForUser(socket.userId);
    if (!box || typeof data?.trackingId !== 'string') return;
    const tracking = await Tracking.findOne({ trackingId: data.trackingId, userId: socket.userId });
    if (tracking) io.to(deviceRoom(box.deviceId)).emit('registerTracking', { trackingId: tracking.trackingId, mode: tracking.mode });
  });

  on('controlDoor', async (data, reply) => {
    const box = await pairedBoxForUser(socket.userId);
    const result = box ? await commandDoor(io, box.deviceId, data?.type, data?.action) : { ok: false, reason: 'unpaired' };
    if (typeof reply === 'function') reply(result);
  });

  on('getStatus', async () => {
    const box = await pairedBoxForUser(socket.userId);
    if (box) io.to(deviceRoom(box.deviceId)).emit('getStatus');
  });

  on('doorStateUpdate', async (data) => {
    const box = await registeredBoxForDevice(socket.deviceId);
    if (!box || !socket.connected) return;
    const state = recordDoorState(socket.deviceId, data);
    if (state) emitToMembers(io, box, 'doorStateUpdate', state);
  });

  on('doorCommandResult', async (data) => {
    const box = await registeredBoxForDevice(socket.deviceId);
    if (!box || !socket.connected) return;
    const state = recordDoorState(socket.deviceId, data?.doorState);
    confirmDoorCommand(socket.deviceId, data, state);
    if (state) emitToMembers(io, box, 'doorStateUpdate', state);
  });

  on('createOwnerPass', async (_data, reply) => {
    if (typeof reply !== 'function') return;
    const box = await pairedBoxForUser(socket.userId);
    if (!box) return reply({ ok: false, reason: 'unpaired' });
    for (const [token, pass] of ownerPasses) {
      if (pass.deviceId === box.deviceId && pass.userId === socket.userId) ownerPasses.delete(token);
    }
    const token = 'SPD-OWNER-' + randomBytes(16).toString('hex').toUpperCase();
    const expiresAt = Date.now() + 60000;
    ownerPasses.set(token, { deviceId: box.deviceId, userId: socket.userId, expiresAt });
    setTimeout(() => ownerPasses.delete(token), 60000).unref();
    reply({ ok: true, token, expiresAt });
  });

  on('verifyScan', async ({ trackingId, mode } = {}) => {
    const box = await registeredBoxForDevice(socket.deviceId);
    const userIds = membersOf(box);
    if (!userIds.length || typeof trackingId !== 'string' || !['drop_off', 'pickup', 'pick_up'].includes(mode)) {
      return socket.emit('scanResult', { valid: false, trackingId, mode, reason: 'unauthorized' });
    }
    try {
      const pass = ownerPasses.get(trackingId.trim().toUpperCase());
      if (pass && pass.deviceId === box.deviceId && userIds.includes(pass.userId) && pass.expiresAt > Date.now()) {
        ownerPasses.delete(trackingId.trim().toUpperCase());
        await ScanLog.create({
          scannedId: 'owner_access_pass', deviceId: box.deviceId, userId: pass.userId,
          accessGranted: true, mode: 'owner_verify', status: 'authorized', reason: 'owner_badge_scan',
        });
        return socket.emit('scanResult', { valid: true, trackingId, mode, userId: pass.userId, reason: 'ok' });
      }

      // Check if this is a registered Rider ID (for pickup mode or courier access)
      const rider = await Rider.findOne({ riderId: trackingId, $or: [{ deviceId: box.deviceId }, { deviceId: null, userId: { $in: userIds } }] });
      if (rider) {
        console.log(`🚴 RIDER AUTHORIZED AT PHYSICAL SCANNER: ${rider.name} (${trackingId})`);
        await ScanLog.create({
          scannedId: trackingId,
          accessGranted: true,
          mode: mode,
          status: 'authorized',
          reason: `rider_badge:${rider.name}`
        });
        socket.emit('scanResult', {
          valid: true,
          trackingId,
          mode,
          userId: null,
          isRider: true,
          riderName: rider.name,
          reason: 'ok'
        });
        return;
      }

      let tracking = await findTrackingFlexibly(trackingId, userIds);

      // Case 1: Tracking ID doesn't exist at all
      if (!tracking) {
        if (autoAcceptDevices.has(box.deviceId)) {
          console.log(`  ✨ AUTO-REGISTER (TEST MODE): Creating new tracking for ${trackingId}`);
          const userId = box.primaryUserId || userIds[0];
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

      if (!allowedStatuses.includes(tracking.status) || isPickUpMode !== ['pick_up', 'pickup'].includes(tracking.mode)) {
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
  on('verifyRider', async ({ riderId } = {}) => {
    const box = await registeredBoxForDevice(socket.deviceId);
    const userIds = membersOf(box);
    const rider = userIds.length && typeof riderId === 'string' && await Rider.findOne({
      riderId, $or: [{ deviceId: box.deviceId }, { deviceId: null, userId: { $in: userIds } }],
    });
    socket.emit('riderVerifyResult', { valid: Boolean(rider), riderId });
  });

  on('requestOwnerSession', async () => {
    const box = await registeredBoxForDevice(socket.deviceId);
    const userIds = membersOf(box);
    if (!userIds.length) return;
    const now = Date.now();
    if (now - (sessionCooldowns.get(socket.id) || 0) < SESSION_COOLDOWN_MS) return;
    sessionCooldowns.set(socket.id, now);

    for (const [token, session] of ownerSessions) {
      if (session.deviceId === box.deviceId) ownerSessions.delete(token);
    }
    let token;
    do {
      token = 'OWN-' + randomInt(100000, 1000000);
    } while (ownerSessions.has(token));
    const session = { deviceId: box.deviceId, expiresAt: now + 65000, alertId: randomUUID() };
    ownerSessions.set(token, session);
    setTimeout(() => {
      if (ownerSessions.get(token) === session) ownerSessions.delete(token);
    }, 65000).unref();
    socket.emit('ownerSessionToken', { token });
    emitToMembers(io, box, 'ownerAccessAlert', { alertId: session.alertId, expiresAt: session.expiresAt });
    await Promise.all(userIds.map(async userId => {
      const notification = await Notification.create({
        userId,
        title: 'Dropbox access requested',
        message: 'An owner verification was requested at your dropbox.',
        type: 'system_alert',
      });
      io.to(userId).emit('notificationNew', notification);
    }));
    await ScanLog.create({
      deviceId: box.deviceId, scannedId: session.alertId, userId: box.primaryUserId || userIds[0],
      accessGranted: null, mode: 'owner_verify', status: 'pending', reason: 'owner_qr_requested',
    });
  });

  on('verifyOwnerQR', async ({ token } = {}) => {
    const box = await pairedBoxForUser(socket.userId);
    const session = typeof token === 'string' ? ownerSessions.get(token) : null;
    if (!box || !session || session.deviceId !== box.deviceId || session.expiresAt <= Date.now() ||
        !isDeviceOnline(io, box.deviceId)) {
      socket.emit('ownerVerifyAck', { approved: false, token, reason: 'invalid_or_expired' });
      return;
    }
    ownerSessions.delete(token);
    io.to(deviceRoom(box.deviceId)).emit('ownerVerifyResult', { approved: true });
    socket.emit('ownerVerifyAck', { approved: true, token });
    await ScanLog.updateOne(
      { deviceId: box.deviceId, scannedId: session.alertId, mode: 'owner_verify' },
      { $set: { userId: socket.userId, accessGranted: true, status: 'authorized', reason: 'owner_qr_approved' } },
    );
  });

  on('registerOwnerPickup', async ({ trackingId } = {}) => {
    const box = await registeredBoxForDevice(socket.deviceId);
    const userIds = membersOf(box);
    const tracking = await findTrackingFlexibly(trackingId, userIds);
    if (!tracking || !['pick_up', 'pickup'].includes(tracking.mode) || tracking.status !== 'pending') return;
    const result = await Tracking.updateOne(
      { _id: tracking._id, status: 'pending' }, { $set: { status: 'awaiting_pickup' } },
    );
    if (!result.modifiedCount) return;
    await Dropbox.updateOne({ _id: box._id }, { $inc: { pickupCount: 1 } });
    io.to(tracking.userId).emit('trackingStatusChanged', { trackingId: tracking.trackingId, status: 'awaiting_pickup', mode: 'pick_up' });
  });

  on('statusUpdate', async ({ trackingId, status, mode } = {}) => {
    const box = await registeredBoxForDevice(socket.deviceId);
    const tracking = await findTrackingFlexibly(trackingId, membersOf(box));
    if (!tracking) return;
    const pickup = ['pick_up', 'pickup'].includes(mode);
    if ((pickup ? 'pick_up' : mode) !== (tracking.mode === 'pickup' ? 'pick_up' : tracking.mode)) return;
    const nextStates = pickup ? {
      pending: ['awaiting_pickup', 'ready_for_pickup', 'retrieved'],
      awaiting_pickup: ['ready_for_pickup', 'retrieved', 'done'],
      ready_for_pickup: ['retrieved', 'done'],
    } : {
      pending: ['delivered', 'done'], in_transit: ['delivered', 'done'],
      delivered: ['retrieved'], done: ['retrieved'],
    };
    if (!Object.hasOwn(nextStates, tracking.status) || !nextStates[tracking.status].includes(status)) return;

    const update = { status };
    const timeFields = { delivered: 'deliveredAt', retrieved: 'retrievedAt', done: 'doneAt' };
    if (timeFields[status]) update[timeFields[status]] = new Date();
    const updated = await Tracking.updateOne({ _id: tracking._id, status: tracking.status }, { $set: update });
    if (!updated.modifiedCount) return;

    const collected = status === 'retrieved' || (pickup && status === 'done');
    const delivered = !pickup && ['delivered', 'done'].includes(status);
    const notification = await Notification.create({
      userId: tracking.userId, trackingId: tracking.trackingId,
      title: collected ? 'Parcel Retrieved' : delivered ? 'Parcel Delivered' : 'Pickup Status Updated',
      message: 'Tracking ID ' + tracking.trackingId + ' status changed to ' + status + '.',
      type: collected ? 'parcel_picked_up' : delivered ? 'parcel_delivered' : 'system_alert',
      ...(delivered && deliveryPush.enabled() ? { pushDueAt: new Date() } : {}),
    });
    const room = io.to(tracking.userId);
    const { pushDueAt, ...visibleNotification } = notification.toJSON();
    room.emit('notificationNew', visibleNotification);
    room.emit('trackingStatusChanged', {
      trackingId: tracking.trackingId, status, mode, deviceId: box.deviceId, timestamp: new Date(),
      ...(delivered ? { notificationId: String(notification._id), pushQueued: !!pushDueAt } : {}),
    });

    if (collected || delivered) {
      const countField = pickup ? 'pickupCount' : 'dropoffCount';
      if (delivered) await Dropbox.updateOne({ _id: box._id }, { $inc: { dropoffCount: 1 } });
      if (collected) await Dropbox.updateOne({ _id: box._id, [countField]: { $gt: 0 } }, { $inc: { [countField]: -1 } });
      const currentBox = await Dropbox.findById(box._id);
      if (currentBox) emitToMembers(io, currentBox, 'binStatusUpdate', {
        logicalDropoffCount: currentBox.dropoffCount, logicalPickupCount: currentBox.pickupCount,
      });
    }

  });

  on('sensorUpdate', async (data) => {
    const box = await registeredBoxForDevice(socket.deviceId);
    if (!box || !socket.connected) return;
    const payload = { logicalDropoffCount: box.dropoffCount, logicalPickupCount: box.pickupCount, timestamp: new Date() };
    for (const field of ['US_PICKUP', 'US_DROPOFF', 'REED_TOP', 'REED_PICKUP', 'REED_RECEIVED']) {
      if (typeof data?.[field] === 'boolean' || typeof data?.[field] === 'number') payload[field] = data[field];
    }
    emitToMembers(io, box, 'binStatusUpdate', payload);
  });

  // ── Device Registration (hardware → backend → app) ─────────────────────
  // ESP32 emits this when in DEVICE_UNREGISTERED state and user presses BTN1.
  // Payload: { deviceId: "AA:BB:CC:DD:EE:FF" }  (MAC address)
  on('requestDeviceRegistration', async ({ alreadyConnected } = {}) => {
    const deviceId = socket.deviceId;
    if (!deviceId) return;
    let pin;
    do { pin = randomInt(100000, 1000000).toString(); } while (pendingRegistrations.has('SPDB-REG-' + pin));
    const token = `SPDB-REG-${pin}`;
    const expiresAt = Date.now() + 65000; // 65s TTL
    pendingRegistrations.set(token, {
      deviceId,
      expiresAt,
      expiresAtMs: expiresAt,
      alreadyConnected: !!alreadyConnected
    });
    setTimeout(() => pendingRegistrations.delete(token), 70000).unref();
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
  on('registerDevice', async ({ token, deviceName } = {}) => {
    const effectiveUserId = socket.userId;
    if (!effectiveUserId) {
      console.log('❌ registerDevice rejected: unauthenticated socket');
      socket.emit('deviceRegistrationFailed', { reason: 'unauthorized' });
      return;
    }
    const entry = pendingRegistrations.get(token);
    const expiresAt = entry?.expiresAtMs || entry?.expiresAt;
    if (!entry || (expiresAt && Date.now() > expiresAt)) {
      console.log('  ❌ Invalid or expired registration token');
      socket.emit('deviceRegistrationFailed', { reason: 'invalid_or_expired_token' });
      return;
    }
    pendingRegistrations.delete(token);
    const { deviceId } = entry;
    try {
      // Check if this user is already registered to this device
      const existing = await Dropbox.findOne({ deviceId });
      const wasAlreadyRegistered = Boolean(existing && existing.isRegistered);
      const skipWifiSetup = Boolean(
        entry.alreadyConnected ||
        entry.isHouseholdInvite ||
        (wasAlreadyRegistered && (existing.wifiSSID || existing.status === 'online'))
      );
      const alreadyRegisteredByUser = existing && (existing.userIds || []).includes(effectiveUserId);

      if (alreadyRegisteredByUser) {
        console.log(`  ℹ️  User ${effectiveUserId} is already registered to device ${deviceId}`);
        socket.emit('deviceRegistered', {
          deviceId,
          dropbox: existing,
          alreadyConnected: skipWifiSetup,
        });
        if (!entry.isHouseholdInvite) {
          io.to(deviceRoom(deviceId)).emit('deviceRegistered', { deviceId });
        }
        return;
      }

      const preservedName = (wasAlreadyRegistered && existing.name)
        ? existing.name
        : (deviceName || 'My Smart Parcel Dropbox');

      // $addToSet ensures the userId is added only once even if called multiple times
      // $setOnInsert only runs when a brand-new document is created (upsert)
      const dropbox = await Dropbox.findOneAndUpdate(
        { deviceId },
        {
          $addToSet: { userIds: effectiveUserId },
          $set: {
            name: preservedName,
            isRegistered: true,
            status: wasAlreadyRegistered ? (existing.status || 'offline') : 'offline',
            registeredAt: wasAlreadyRegistered ? (existing.registeredAt || new Date()) : new Date(),
          },
          $setOnInsert: {
            primaryUserId: effectiveUserId,
          },
        },
        { upsert: true, new: true }
      );

      // Promote to primaryUserId if field is still unset (legacy migration path)
      if (!dropbox.primaryUserId) {
        await Dropbox.updateOne({ _id: dropbox._id }, { $set: { primaryUserId: effectiveUserId } });
      }

      const registeredUserCount = dropbox.userIds ? dropbox.userIds.length : 1;
      console.log(`  ✅ Device registered: ${deviceId} → user: ${effectiveUserId} (total users: ${registeredUserCount})`);

      // Notify the registering app client
      socket.emit('deviceRegistered', {
        deviceId,
        dropbox,
        alreadyConnected: skipWifiSetup,
      });
      if (!entry.isHouseholdInvite) {
        // Notify hardware to save registered flag
        io.to(deviceRoom(deviceId)).emit('deviceRegistered', { deviceId });
      }
    } catch (err) {
      console.error('❌ registerDevice DB error:', err.message);
      socket.emit('deviceRegistrationFailed', { reason: 'server_error' });
    }
  });
  
  // ── Unregister Device (mobile app → backend) ─────────────────────────────
  // App emits this to remove a user's own access to the dropbox.
  // Multi-user: only pulls this userId out of userIds. The device stays registered
  // for other users. Hardware is notified only when the LAST user unregisters.
  on('unregisterDevice', async () => {
    const effectiveUserId = socket.userId;
    if (!effectiveUserId) {
      socket.emit('deviceUnregistrationFailed', { reason: 'unauthorized' });
      return;
    }
    console.log(`📱 unregisterDevice → userId: ${effectiveUserId}`);
    try {
      // Support both new (userIds array) and legacy (userId) documents
      let dropbox = await Dropbox.findOne({ userIds: effectiveUserId });
      if (!dropbox) dropbox = await Dropbox.findOne({ userId: effectiveUserId });

      if (!dropbox) {
        console.log(`  ❌ No dropbox found for userId: ${effectiveUserId}`);
        socket.emit('deviceUnregistrationFailed', { reason: 'no_device_found' });
        return;
      }

      const { deviceId } = dropbox;

      // 1. Pull this user out of userIds
      await Dropbox.updateOne(
        { _id: dropbox._id },
        { $pull: { userIds: effectiveUserId } }
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
        io.to(deviceRoom(deviceId)).emit('deviceUnregistered', { deviceId });
      } else {
        if (dropbox.primaryUserId === effectiveUserId || dropbox.userId === effectiveUserId) {
          await Dropbox.updateOne(
            { _id: dropbox._id },
            {
              $set: {
                primaryUserId: remainingUsers[0],
                ...(dropbox.userId === effectiveUserId ? { userId: remainingUsers[0] } : {}),
              }
            }
          );
        }
        console.log(`  ✅ User ${effectiveUserId} removed from device ${deviceId} (${remainingUsers.length} user(s) remaining)`);
      }

      // 3. Notify requesting app client
      socket.emit('deviceUnregistered', { deviceId, success: true, remainingUsers: remainingUsers.length });

    } catch (err) {
      console.error('❌ unregisterDevice error:', err.message);
      socket.emit('deviceUnregistrationFailed', { reason: 'server_error' });
    }
  });

  on('pushHardwareConfig', async ({ ssid, password } = {}) => {
    const box = await pairedBoxForUser(socket.userId);
    if (!box || !isDeviceOnline(io, box.deviceId) || typeof ssid !== 'string' ||
        typeof password !== 'string' || !ssid.trim() || ssid.length > 32 || password.length > 64) return;
    io.to(deviceRoom(box.deviceId)).emit('applyHardwareConfig', { ssid, password });
    await Dropbox.updateOne({ _id: box._id }, { $set: { wifiSSID: ssid } });
  });

  on('requestWiFiScan', async () => {
    const box = await pairedBoxForUser(socket.userId);
    if (box) io.to(deviceRoom(box.deviceId)).emit('requestWiFiScan');
  });

  on('wifiScanResult', async (data) => {
    const box = await registeredBoxForDevice(socket.deviceId);
    if (box && Array.isArray(data?.networks)) emitToMembers(io, box, 'wifiScanResult', { networks: data.networks.slice(0, 15) });
  });

  on('hardwareConfigApplied', async () => {
    const box = await registeredBoxForDevice(socket.deviceId);
    if (box) emitToMembers(io, box, 'hardwareConfigApplied', {});
  });

  on('toggleAutoAccept', async ({ enabled } = {}) => {
    const box = await pairedBoxForUser(socket.userId);
    if (!box || (box.primaryUserId || box.userId) !== socket.userId || process.env.SPD_ALLOW_AUTO_ACCEPT !== 'true') return;
    if (enabled === true) autoAcceptDevices.add(box.deviceId);
    else autoAcceptDevices.delete(box.deviceId);
    emitToMembers(io, box, 'autoAcceptStatus', { enabled: autoAcceptDevices.has(box.deviceId) });
  });
  on('getAutoAcceptStatus', async () => {
    const box = await pairedBoxForUser(socket.userId);
    socket.emit('autoAcceptStatus', { enabled: Boolean(box && autoAcceptDevices.has(box.deviceId)) });
  });

  on('disconnect', async () => {
    sessionCooldowns.delete(socket.id);
    if (!socket.deviceId) return;
    deviceDisconnected(socket.deviceId);
    for (const [token, session] of ownerSessions) {
      if (session.deviceId === socket.deviceId) ownerSessions.delete(token);
    }
    await publishPresence(socket.deviceId);
  });
});

// Pass socket.io to routes
setSocketIO(io);

// Initialize Arduino Scanner
async function initializeScanner() {
  const connected = await arduinoScanner.connect();
  if (connected) {
    // Handle barcode scans
    arduinoScanner.onBarcodeScan(async (barcode) => {
      try {
        const box = await registeredBoxForDevice(process.env.SPD_SERIAL_DEVICE_ID);
        if (box) emitToMembers(io, box, 'barcodeScan', { barcode, timestamp: new Date() });
      } catch (error) {
        console.error('Could not route serial scanner event:', error.message);
      }
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
  checkSigningKey();
  void verifyEmailTransport();
  const PORT = process.env.PORT || 3000;

  // Connect to database
  await connectDatabase();
  deliveryPush.startDeliveryPush();

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

if (require.main === module) {
  process.on('SIGINT', async () => {
    arduinoScanner.disconnect();
    await mongoose.connection.close();
    io.close(() => process.exit(0));
  });

  startServer().catch((error) => {
    console.error('❌ Failed to start server:', error.message);
    process.exit(1);
  });
}

module.exports = { app, server, io };
