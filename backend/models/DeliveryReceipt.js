const mongoose = require('mongoose');

const deliveryReceiptSchema = new mongoose.Schema({
  // The built-in unique index scopes each event ID to its sending device.
  _id: { type: String, required: true },
  trackingRecordId: { type: mongoose.Schema.Types.ObjectId, required: true },
  notificationId: { type: mongoose.Schema.Types.ObjectId },
  batchId: { type: String },
  deviceId: { type: String },
  userId: { type: String },
  trackingId: { type: String },
  needsReview: { type: Boolean, default: false },
  reviewedAt: { type: Date },
  occurredAt: { type: Date, default: null },
  receivedAt: { type: Date, required: true },
});

deliveryReceiptSchema.index({ deviceId: 1, userId: 1, receivedAt: -1 });

module.exports = mongoose.model('DeliveryReceipt', deliveryReceiptSchema);
