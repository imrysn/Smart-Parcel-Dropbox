const mongoose = require('mongoose');

const scanLogSchema = new mongoose.Schema({
    trackingId: {
        type: String,
        required: true
    },
    scannedId: {
        type: String,
        required: true
    },
    mode: {
        type: String,
        enum: ['drop_off', 'pick_up'],
        required: true
    },
    status: {
        type: String,
        enum: ['authorized', 'unauthorized', 'expired'],
        required: true
    },
    message: String,
    timestamp: {
        type: Date,
        default: Date.now
    }
}, {
    timestamps: true
});

module.exports = mongoose.model('ScanLog', scanLogSchema);
