const mongoose = require('mongoose');

/**
 * Dropbox — represents a registered Smart Parcel Dropbox hardware unit.
 * Created when a user scans the registration QR code shown on the LCD.
 */
const dropboxSchema = new mongoose.Schema({
  deviceId: {
    type: String,
    required: true,
    unique: true,    // MAC address of the ESP32
  },
  userId: {
    type: String,
    required: true,  // MongoDB user._id who registered this device
  },
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
  lastSeenAt: {
    type: Date,
    default: null,
  },
}, {
  timestamps: true,
});

module.exports = mongoose.model('Dropbox', dropboxSchema);
