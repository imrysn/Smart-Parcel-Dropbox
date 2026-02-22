/**
 * Tracking Model
 * Stores parcel tracking IDs registered by users via the mobile app.
 * The ESP32 checks this collection when verifying a barcode scan.
 */
const mongoose = require('mongoose');

const trackingSchema = new mongoose.Schema({
  trackingId: {
    type: String,
    required: true,
    unique: true,
    trim: true
  },
  userId: {
    type: String,
    required: true
  },
  shopName: {
    type: String,
    default: 'Unknown'
  },
  // 'drop_off' = courier drops parcel off, 'pick_up' = user picks up
  mode: {
    type: String,
    enum: ['drop_off', 'pick_up'],
    required: true
  },
  status: {
    type: String,
    enum: ['pending', 'in_transit', 'delivered', 'retrieved'],
    default: 'pending'
  },
  registeredAt: { type: Date, default: Date.now },
  deliveredAt:  { type: Date },
  retrievedAt:  { type: Date }
}, { timestamps: true });

module.exports = mongoose.model('Tracking', trackingSchema);
