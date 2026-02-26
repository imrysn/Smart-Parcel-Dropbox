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
  // Give the ESP32 (slow MCU) more time to respond to heartbeats
  pingTimeout: 60000,   // 60s before declaring client dead (default: 20s)
  pingInterval: 25000,  // Ping every 25s
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

  // ESP32 emits this when a barcode is scanned at WAITING_FOR_SCAN
  // Payload: { trackingId: "ABC123", mode: "drop_off" }
  socket.on('verifyScan', async ({ trackingId, mode }) => {
    console.log(`🔍 verifyScan → trackingId: ${trackingId}, mode: ${mode}`);
    try {
      // Find a tracking record that matches AND is still pending
      const tracking = await Tracking.findOne({
        trackingId,
        status: 'pending'
      });

      const valid = !!tracking;
      console.log(`  ${valid ? '✅ VALID' : '❌ INVALID'}: ${trackingId}`);

      socket.emit('scanResult', {
        valid,
        trackingId,
        mode,
        userId: tracking ? tracking.userId : null
      });

    } catch (err) {
      console.error('❌ verifyScan error:', err.message);
      socket.emit('scanResult', { valid: false, trackingId, mode, userId: null });
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
      await Tracking.updateOne(
        { trackingId },
        { $set: { status: 'awaiting_pickup', registeredAt: new Date() } },
        { upsert: true }
      );
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
      const update = { status };
      if (status === 'delivered') update.deliveredAt = new Date();
      if (status === 'retrieved') update.retrievedAt = new Date();
      if (status === 'done') update.doneAt = new Date();

      await Tracking.updateOne({ trackingId }, { $set: update });

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

  socket.on('disconnect', () => {
    console.log(`🔌 Client disconnected: ${socket.id}`);
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
