const mongoose = require('mongoose');

const riderSchema = new mongoose.Schema({
    riderId: {
        type: String,
        required: true,
        unique: true,
        trim: true,
    },
    name: {
        type: String,
        required: true,
        trim: true,
    },
    userId: {
        type: String,
        trim: true,
        index: true,
        default: null,
    },
    deviceId: {
        type: String,
        trim: true,
        default: null,
    },
    createdAt: {
        type: Date,
        default: Date.now,
    }
});

module.exports = mongoose.model('Rider', riderSchema);
