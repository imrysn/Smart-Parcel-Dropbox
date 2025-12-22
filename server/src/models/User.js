const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
    uid: {
        type: String,
        required: true,
        unique: true
    },
    email: {
        type: String,
        required: true,
        unique: true
    },
    fullName: String,
    phoneNumber: String,
    address: String,
    role: {
        type: String,
        enum: ['user', 'admin', 'courier'],
        default: 'user'
    }
}, {
    timestamps: true
});

module.exports = mongoose.model('User', userSchema);
