const mongoose = require('mongoose');

const transactionSchema = new mongoose.Schema({
  userId: {
    type: String,
    required: true
  },
  type: {
    type: String,
    enum: ['REVENUE', 'EXPENSE_SHIPPING', 'EXPENSE_MATERIAL', 'EXPENSE_OTHER'],
    required: true
  },
  amount: {
    type: Number,
    required: true
  },
  category: {
    type: String,
    default: 'General'
  },
  description: {
    type: String,
    trim: true
  },
  referenceId: {
    type: String
  },
  date: {
    type: Date,
    default: Date.now
  }
}, { timestamps: true });

module.exports = mongoose.model('Transaction', transactionSchema);
