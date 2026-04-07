const mongoose = require('mongoose');

/**
 * Dropbox — represents a registered Smart Parcel Dropbox hardware unit.
 * Created when a user scans the registration QR code shown on the LCD.
 *
 * Multi-user: a single physical device can be registered by multiple users.
 * userIds holds all registered user IDs. primaryUserId is the first registrant.
 * The legacy userId field is kept as a virtual alias for backward compatibility.
 */
const dropboxSchema = new mongoose.Schema({
  deviceId: {
    type: String,
    required: true,
    unique: true,    // MAC address of the ESP32
  },
  // ── Multi-user fields ──────────────────────────────────────────────────────
  userIds: {
    type: [String],
    default: [],     // All users who have registered this device
  },
  primaryUserId: {
    type: String,
    default: null,   // First user to register (for display / ownership)
  },
  // ── Legacy single-user field (kept for backward compat, not written to) ───
  userId: {
    type: String,
    default: null,
  },
  // ─────────────────────────────────────────────────────────────────────────
  name: {
    type: String,
    default: 'My Smart Parcel Dropbox',
  },
  isRegistered: {
    type: Boolean,
    default: true,
  },
  wifiSSID: {
    type: String,
    default: null,   // populated when user pushes WiFi config via app
  },
  status: {
    type: String,
    enum: ['online', 'offline', 'unregistered'],
    default: 'offline',
  },
  registeredAt: {
    type: Date,
    default: Date.now,
  },
  dropoffCount: {
    type: Number,
    default: 0,
    min: 0,
  },
  pickupCount: {
    type: Number,
    default: 0,
    min: 0,
  },
  lastSeenAt: {
    type: Date,
    default: null,
  },
  // ── Phase 4: Applied Cryptography ─────────
  hmacKey: {
    type: String,
    default: null // Shared with primary owner for TOTP
  },
  // ── Spatial Volume Analytics (CS Phase 3) ─────────
  occupancyPercent: {
    type: Number,
    default: 0,
  },
  fillPercentage: {
    type: Number,
    default: 0,
  },
}, {
  timestamps: true,
});

module.exports = mongoose.model('Dropbox', dropboxSchema);
