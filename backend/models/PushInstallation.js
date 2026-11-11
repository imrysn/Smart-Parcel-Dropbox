const mongoose = require('mongoose');

const schema = new mongoose.Schema({
  _id: String,
  userId: { type: String, required: true, index: true },
  token: { type: String, required: true, unique: true },
  platform: { type: String, enum: ['android'], required: true },
  expiresAt: { type: Date, required: true, expires: 0 },
}, { timestamps: true });

module.exports = mongoose.model('PushInstallation', schema);
