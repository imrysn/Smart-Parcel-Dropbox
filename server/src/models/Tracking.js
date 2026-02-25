const mongoose = require('mongoose');

const trackingSchema = new mongoose.Schema({
    trackingId: {
        type: String,
        required: true,
        unique: true
    },
    userId: {
        type: String,
        required: true,
        ref: 'User'
    },
    shopName: String,
    status: {
        type: String,
        enum: ['pending', 'in_transit', 'delivered', 'retrieved', 'ready_for_pickup'],
        default: 'pending'
    },
    mode: {
        type: String,
        enum: ['drop_off', 'pickup'],
        default: 'drop_off'
    },
    expectedDeliveryDate: String,
    deliveredAt: Date,
    retrievedAt: Date
}, {
    timestamps: true
});

module.exports = mongoose.model('Tracking', trackingSchema);
