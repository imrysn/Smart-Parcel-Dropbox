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

app.use('/api/users', userRoutes);
app.use('/api/tracking', trackingRoutes);
app.use('/api/scan-logs', scanLogRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/delivery-logs', deliveryLogRoutes);

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

// Socket.IO connection handling
io.on('connection', (socket) => {
  console.log(`🔌 Client connected: ${socket.id}`);

  // Device room join (ESP32 identifies itself)
  socket.on('join', (roomId) => {
    socket.join(roomId);
    console.log(`📡 ${socket.id} joined room: ${roomId}`);

    // Track ESP32 connection status
    if (roomId === 'esp32_device') {
      socket.isEsp32 = true; // stamp flag — socket.rooms is empty by disconnect time
      console.log('✅ ESP32 connected and joined room');
      io.emit('esp32Status', { connected: true, timestamp: new Date() });
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
      const tracking = await Tracking.findOne({ trackingId });

      // Case 1: Tracking ID doesn't exist at all
      if (!tracking) {
        console.log(`  ❌ NOT FOUND: ${trackingId}`);
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
          body: `Tracking ID ${trackingId} was scanned but is already marked as ${tracking.status}.`,
          type: 'warning'
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
      const expectedStatus = isPickUpMode ? 'awaiting_pickup' : 'pending';

      if (tracking.status !== expectedStatus) {
        console.log(`  ⚠️  WRONG STATUS (${tracking.status}): ${trackingId} expected ${expectedStatus} for mode ${mode}`);
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
          body: `Tracking ID ${trackingId} was scanned for ${isPickUpMode ? 'Pick Up' : 'Drop Off'} but its status is currently: ${tracking.status}.`,
          type: 'warning'
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
        body: `Access granted for ${mode === 'drop_off' ? 'Drop Off' : 'Pick Up'} using tracking ID ${trackingId}.`,
        type: mode === 'drop_off' ? 'delivery' : 'pickup'
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
  // For now: any non-empty riderId is accepted (no Rider model yet).
  // Replace with a real DB check once a Rider model is added.
  socket.on('verifyRider', async ({ riderId }) => {
    console.log(`🚴 verifyRider → riderId: ${riderId}`);
    try {
      const valid = riderId && riderId.length > 2;
      console.log(`  ${valid ? '✅ RIDER VALID' : '❌ RIDER INVALID'}: ${riderId}`);
      socket.emit('riderVerifyResult', { valid: !!valid, riderId });
    } catch (err) {
      console.error('❌ verifyRider error:', err.message);
      socket.emit('riderVerifyResult', { valid: false, riderId });
    }
  });

  // ── Owner Pickup Registration ────────────────────────────────────────────
  // ESP32 emits this when owner scans a waybill QR at the box
  // Payload: { trackingId: "ABC123" }
  socket.on('registerOwnerPickup', async ({ trackingId }) => {
    console.log(`📦 registerOwnerPickup → trackingId: ${trackingId}`);
    try {
      // Find tracking to get userId for notification
      let tracking = await Tracking.findOne({ trackingId });

      // Default to null if upserted a new one, but if we create it here we need a mode
      // so Flutter knows it's a pickup.
      await Tracking.updateOne(
        { trackingId },
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
          body: `Tracking ID ${trackingId} is now awaiting pickup at the box.`,
          type: 'pickup'
        });
      }

      io.emit('trackingStatusChanged', {
        trackingId,
        status: 'awaiting_pickup',
        timestamp: new Date()
      });
      console.log(`  ✅ Owner pickup registered: ${trackingId}`);
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
      const tracking = await Tracking.findOne({ trackingId });

      const update = { status };
      if (status === 'delivered') update.deliveredAt = new Date();
      if (status === 'retrieved') update.retrievedAt = new Date();
      if (status === 'done') update.doneAt = new Date();

      await Tracking.updateOne({ trackingId }, { $set: update });

      if (tracking && tracking.userId) {
        let title = 'Status Update';
        let body = `Tracking ID ${trackingId} status changed to ${status}.`;
        let type = 'system';

        if (status === 'delivered' || status === 'done') {
          title = 'Parcel Delivered';
          body = `Your parcel (${trackingId}) has been successfully dropped off in the box.`;
          type = 'delivery';
        } else if (status === 'retrieved') {
          title = 'Parcel Retrieved';
          body = `Your parcel (${trackingId}) has been successfully retrieved from the box.`;
          type = 'pickup';
        }

        await Notification.create({
          userId: tracking.userId,
          title,
          body,
          type
        });
      }

      // Broadcast to all connected mobile app clients
      io.emit('trackingStatusChanged', {
        trackingId,
        status,
        mode,
        timestamp: new Date()
      });

      console.log(`✅ Status broadcasted: ${trackingId} → ${status}`);
    } catch (err) {
      console.error('❌ statusUpdate error:', err.message);
    }
  });

  // ── Sensor / Bin Status (ESP32 → backend → mobile app) ─────────────────
  // ESP32 emits this periodically or on change with ultrasonic + reed readings
  // Payload: { US_PICKUP: <cm>, US_DROPOFF: <cm>, REED_TOP: bool, REED_PICKUP: bool, REED_RECEIVED: bool }
  socket.on('sensorUpdate', (data) => {
    console.log(`📡 sensorUpdate:`, data);
    io.emit('binStatusUpdate', { ...data, timestamp: new Date() });
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
    console.log('🔧 ESP32-S3 IP:', process.env.ESP32_IP || '192.168.1.100');
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
