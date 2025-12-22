const DeliveryLog = require('../models/DeliveryLog');

// @desc    Get all delivery logs (Admin)
// @route   GET /api/delivery-logs
exports.getAllDeliveryLogs = async (req, res) => {
    try {
        const logs = await DeliveryLog.find().sort({ timestamp: -1 });
        res.json(logs);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get delivery logs for a tracking ID
// @route   GET /api/delivery-logs/:trackingId
exports.getDeliveryLogs = async (req, res) => {
    try {
        const logs = await DeliveryLog.find({ trackingId: req.params.trackingId }).sort({ timestamp: -1 });
        res.json(logs);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Add a delivery log entry manually if needed (not usually used by app directly but good to have)
exports.addDeliveryLog = async (req, res) => {
    try {
        const log = await DeliveryLog.create(req.body);
        res.status(201).json(log);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
