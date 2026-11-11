const mongoose = require('mongoose');

const taskSchema = new mongoose.Schema({
  userId: {
    type: String,
    required: true
  },
  title: {
    type: String,
    required: true,
    trim: true
  },
  stage: {
    type: String,
    enum: ['INQUIRY', 'CRAFTING', 'READY_FOR_BOX', 'SHIPPED'],
    default: 'INQUIRY'
  },
  platform: {
    type: String,
    enum: ['SHOPEE', 'TIKTOK', 'INSTAGRAM', 'CUSTOM'],
    default: 'CUSTOM'
  },
  customerName: {
    type: String,
    trim: true
  },
  customerPhone: {
    type: String,
    trim: true
  },
  trackingId: {
    type: String,
    trim: true
  },
  courierName: {
    type: String,
    trim: true
  },
  courierOtp: {
    type: String,
    trim: true
  },
  dueDate: {
    type: Date
  },
  notes: {
    type: String
  }
}, { timestamps: true });

module.exports = mongoose.model('Task', taskSchema);
