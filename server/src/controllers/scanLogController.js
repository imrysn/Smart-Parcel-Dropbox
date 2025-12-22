const ScanLog = require('../models/ScanLog');
const DeliveryLog = require('../models/DeliveryLog');

// @desc    Log a scan attempt
// @route   POST /api/scan-logs
exports.logScanAttempt = async (req, res) => {
    try {
        const { scannedCode, accessGranted, trackingId, userId, reason } = req.body;
        const scanLog = await ScanLog.create({
            scannedCode,
            accessGranted,
            trackingId,
            userId,
            reason
        });

        // If access was granted, also log it as a delivery event
        if (accessGranted) {
            await DeliveryLog.create({
                trackingId: trackingId || 'SCAN',
                userId: userId || 'courier',
                eventType: 'door_opened_by_scan',
                details: `Box opened via QR scan: ${scannedCode}`
            });
        }

        res.status(201).json(scanLog);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get all scan logs
// @route   GET /api/scan-logs
exports.getScanLogs = async (req, res) => {
    try {
        const logs = await ScanLog.find().sort({ timestamp: -1 });
        res.json(logs);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
// @desc    Get scan logs for a specific user
// @route   GET /api/scan-logs/user/:userId
exports.getUserScanLogs = async (req, res) => {
    try {
        const logs = await ScanLog.find({ userId: req.params.userId }).sort({ timestamp: -1 });
        res.json(logs);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
