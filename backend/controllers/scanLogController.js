const ScanLog = require('../models/ScanLog');
const DeliveryLog = require('../models/DeliveryLog');
const Dropbox = require('../models/Dropbox');

// @desc    Log a scan attempt
// @route   POST /api/scan-logs
exports.logScanAttempt = async (req, res) => {
    try {
        const { scannedCode, accessGranted, trackingId, reason } = req.body;
        const userId = req.userId; // Securely get userId from auth token
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

// @desc    Get scan logs scoped to authenticated user / their paired device
// @route   GET /api/scan-logs
exports.getScanLogs = async (req, res) => {
    try {
        const boxes = await Dropbox.find({
            $or: [{ userIds: req.userId }, { primaryUserId: req.userId }, { userId: req.userId }]
        }).select('deviceId');
        const deviceIds = boxes.map((b) => b.deviceId).filter(Boolean);

        const query = deviceIds.length > 0
            ? { $or: [{ userId: req.userId }, { deviceId: { $in: deviceIds } }] }
            : { userId: req.userId };

        const logs = await ScanLog.find(query).sort({ timestamp: -1 });
        res.json(logs);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
// @desc    Get scan logs for a specific user
// @route   GET /api/scan-logs/user/:userId
exports.getUserScanLogs = async (req, res) => {
    try {
        const userId = req.params.userId;

        // Security check
        if (userId !== req.userId) {
            return res.status(403).json({ message: 'Access denied: cannot access another user\'s logs' });
        }

        const logs = await ScanLog.find({ userId }).sort({ timestamp: -1 });
        res.json(logs);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get owner access history logs (scoped to user & paired dropbox)
// @route   GET /api/scan-logs/owner-access
exports.getOwnerAccessLogs = async (req, res) => {
    try {
        const boxes = await Dropbox.find({
            isRegistered: true,
            $or: [{ userIds: req.userId }, { primaryUserId: req.userId }, { userId: req.userId }]
        }).select('deviceId');
        const deviceIds = boxes.map((b) => b.deviceId).filter(Boolean);

        const ownerScope = deviceIds.length > 0
            ? { $or: [{ userId: req.userId }, { deviceId: { $in: deviceIds } }] }
            : { userId: req.userId };

        const logs = await ScanLog.find({ mode: 'owner_verify', ...ownerScope })
            .sort({ createdAt: -1 })
            .limit(50);
        res.json(logs);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
