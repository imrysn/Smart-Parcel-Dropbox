const mongoose = require('mongoose');

const deliveryLogSchema = new mongoose.Schema({
    trackingId: {
        type: String,
        required: true
    },
    userId: {
        type: String,
        required: true
    },
    eventType: {
        type: String,
        required: true,
        enum: ['parcel_delivered', 'parcel_retrieved', 'door_opened', 'door_closed', 'status_update']
    },
    details: String,
    timestamp: {
        type: Date,
        default: Date.now
    }
}, {
    timestamps: true
});

module.exports = mongoose.model('DeliveryLog', deliveryLogSchema);
