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
  expectedDeliveryDate: String,
  // 'drop_off' = courier drops parcel off, 'pick_up' = user picks up
  mode: {
    type: String,
    enum: ['drop_off', 'pick_up', 'pickup'], // Support both for compatibility during migration
    default: 'drop_off'
  },
  status: {
    type: String,
    enum: ['pending', 'in_transit', 'delivered', 'retrieved', 'ready_for_pickup'],
    default: 'pending'
  },
  registeredAt: { type: Date, default: Date.now },
  deliveredAt: { type: Date },
  retrievedAt: { type: Date }
}, { timestamps: true });

module.exports = mongoose.model('Tracking', trackingSchema);
