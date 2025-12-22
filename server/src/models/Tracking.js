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
        enum: ['pending', 'in_transit', 'delivered', 'retrieved'],
        default: 'pending'
    },
    expectedDeliveryDate: String,
    deliveredAt: Date,
    retrievedAt: Date
}, {
    timestamps: true
});

module.exports = mongoose.model('Tracking', trackingSchema);
