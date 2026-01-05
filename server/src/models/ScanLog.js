const mongoose = require('mongoose');

const scanLogSchema = new mongoose.Schema({
    scannedCode: {
        type: String,
        required: true
    },
    accessGranted: {
        type: Boolean,
        required: true
    },
    trackingId: String,
    userId: String,
    reason: String,
    timestamp: {
        type: Date,
        default: Date.now
    }
});

module.exports = mongoose.model('ScanLog', scanLogSchema);
