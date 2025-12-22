const mongoose = require('mongoose');

const deliveryLogSchema = new mongoose.Schema({
    trackingId: {
        type: String,
        required: false
    },
    userId: {
        type: String,
        required: true
    },
    eventType: {
        type: String,
        required: true
    },
    details: String,
    timestamp: {
        type: Date,
        default: Date.now
    }
});

module.exports = mongoose.model('DeliveryLog', deliveryLogSchema);
