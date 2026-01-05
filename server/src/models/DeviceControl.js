const mongoose = require('mongoose');

const deviceControlSchema = new mongoose.Schema({
    command: {
        type: String,
        required: true,
        enum: ['open', 'close']
    },
    userId: String,
    status: {
        type: String,
        enum: ['pending', 'processing', 'completed'],
        default: 'pending'
    },
    timestamp: {
        type: Date,
        default: Date.now
    }
});

module.exports = mongoose.model('DeviceControl', deviceControlSchema);
