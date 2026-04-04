const DeliveryLog = require('../models/DeliveryLog');

// @desc    Get all delivery logs (Admin)
// @route   GET /api/delivery-logs
exports.getAllDeliveryLogs = async (req, res) => {
    try {
        // Restricted to admin or scoped to current user
        const logs = await DeliveryLog.find({ userId: req.userId }).sort({ timestamp: -1 });
        res.json(logs);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get delivery logs for a tracking ID
// @route   GET /api/delivery-logs/:trackingId
exports.getDeliveryLogs = async (req, res) => {
    try {
        const logs = await DeliveryLog.find({ 
            trackingId: req.params.trackingId,
            userId: req.userId // Security: ensure user owns this log
        }).sort({ timestamp: -1 });
        res.json(logs);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Add a delivery log entry manually
exports.addDeliveryLog = async (req, res) => {
    try {
        const logData = { ...req.body, userId: req.userId };
        const log = await DeliveryLog.create(logData);
        res.status(201).json(log);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
