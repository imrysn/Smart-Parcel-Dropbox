const mongoose = require('mongoose');

const deliveryReceiptSchema = new mongoose.Schema({
  // The built-in unique index scopes each event ID to its sending device.
  _id: { type: String, required: true },
  trackingRecordId: { type: mongoose.Schema.Types.ObjectId, required: true },
  notificationId: { type: mongoose.Schema.Types.ObjectId, required: true },
  occurredAt: { type: Date, default: null },
  receivedAt: { type: Date, required: true },
});

module.exports = mongoose.model('DeliveryReceipt', deliveryReceiptSchema);
