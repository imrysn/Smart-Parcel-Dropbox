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
  // Force WebSocket-only: the arduinoWebSockets library cannot handle
  // Socket.IO v4's default polling→upgrade flow, causing connect/disconnect loops.
  transports: ['websocket'],
  // Give the ESP32 (slow MCU) more time to respond to heartbeats
  pingTimeout: 60000,   // 60s before declaring client dead (default: 20s)
  pingInterval: 25000,  // Send ping every 25s (default: 25s, keeping same)
});

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging
app.use((req, res, next) => {
  console.log(`📨 ${req.method} ${req.path}`);
  next();
});

// Routes
app.use('/device-control', deviceControlRouter);

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
      deviceHealth: '/device-control/health'
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
        mode,
        status: 'pending'
      });

      const valid = !!tracking;
      console.log(`  ${valid ? '✅ VALID' : '❌ INVALID'}: ${trackingId}`);

      // Reply only to the ESP32 socket that sent this
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

  // ── Phase 3: Status Update (hardware → backend → mobile app) ────────────
  // ESP32 emits this after a successful drop-off or pick-up cycle
  // Payload: { trackingId: "ABC123", status: "delivered", mode: "drop_off" }
  socket.on('statusUpdate', async ({ trackingId, status, mode }) => {
    console.log(`📦 statusUpdate → ${trackingId}: ${status}`);
    try {
      const update = { status };
      if (status === 'delivered') update.deliveredAt = new Date();
      if (status === 'retrieved') update.retrievedAt = new Date();

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
