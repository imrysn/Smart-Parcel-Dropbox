const mongoose = require('mongoose');

const paymentQrSchema = new mongoose.Schema({
  userId: {
    type: String,
    required: true,
    unique: true
  },
  gcashName: { type: String, trim: true },
  gcashNumber: { type: String, trim: true },
  mayaName: { type: String, trim: true },
  mayaNumber: { type: String, trim: true },
  bankName: { type: String, trim: true, default: 'BDO / BPI / UnionBank' },
  bankAccountName: { type: String, trim: true },
  bankAccountNumber: { type: String, trim: true },
  qrPhImageUrl: { type: String, trim: true }
}, { timestamps: true });

module.exports = mongoose.model('PaymentQr', paymentQrSchema);
