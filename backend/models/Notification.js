const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema({
    userId: {
        type: String,
        required: true
    },
    title: {
        type: String,
        required: true
    },
    message: {
        type: String,
        required: true
    },
    type: {
        type: String,
        enum: ['parcel_delivered', 'parcel_picked_up', 'delivery_scheduled', 'system_alert'],
        default: 'parcel_delivered'
    },
    isRead: {
        type: Boolean,
        default: false
    },
    timestamp: {
        type: Date,
        default: Date.now
    },
    trackingId: String
}, {
    timestamps: true
});

module.exports = mongoose.model('Notification', notificationSchema);
