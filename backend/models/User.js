const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
    uid: {
        type: String,
        unique: true,
        sparse: true // Allow null/undefined for MongoDB-only users
    },
    email: {
        type: String,
        required: true,
        unique: true,
        lowercase: true
    },
    password: {
        type: String,
        required: true
    },
    fullName: String,
    phoneNumber: String,
    address: String,
    role: {
        type: String,
        enum: ['user', 'admin', 'courier'],
        default: 'user'
    },
    resetCode: {
        type: String,
        default: null
    },
    resetCodeExpiry: {
        type: Date,
        default: null
    },
    // ── Phase 4: Applied Cryptography ─────────
    hmacKey: {
        type: String,
        default: null // Generated upon registration/login
    }
}, {
    timestamps: true
});

module.exports = mongoose.model('User', userSchema);
