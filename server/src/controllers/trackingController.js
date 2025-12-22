const Tracking = require('../models/Tracking');
const DeliveryLog = require('../models/DeliveryLog');

// @desc    Register a tracking ID
exports.registerTracking = async (req, res) => {
    try {
        const { trackingId, userId, shopName, expectedDeliveryDate } = req.body;

        const exists = await Tracking.findOne({ trackingId });
        if (exists) {
            return res.status(400).json({ message: 'Tracking ID already registered' });
        }

        const tracking = await Tracking.create({
            trackingId,
            userId,
            shopName,
            expectedDeliveryDate
        });

        res.status(201).json(tracking);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get user tracking IDs
exports.getUserTracking = async (req, res) => {
    try {
        const tracking = await Tracking.find({ userId: req.params.userId }).sort({ createdAt: -1 });
        res.json(tracking);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get all tracking IDs (Admin)
// @route   GET /api/tracking
exports.getAllTracking = async (req, res) => {
    try {
        const tracking = await Tracking.find().sort({ createdAt: -1 });
        res.json(tracking);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get tracking by ID
// @route   GET /api/tracking/:trackingId
exports.getTrackingById = async (req, res) => {
    try {
        const tracking = await Tracking.findOne({ trackingId: req.params.trackingId });
        if (!tracking) {
            return res.status(404).json({ message: 'Tracking ID not found' });
        }
        res.json(tracking);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Update tracking status
// @route   PATCH /api/tracking/:trackingId/status
exports.updateTrackingStatus = async (req, res) => {
    try {
        const { status } = req.body;
        const tracking = await Tracking.findOneAndUpdate(
            { trackingId: req.params.trackingId },
            {
                $set: {
                    status,
                    deliveredAt: status === 'delivered' ? new Date() : undefined,
                    retrievedAt: status === 'retrieved' ? new Date() : undefined
                }
            },
            { new: true }
        );

        if (!tracking) {
            return res.status(404).json({ message: 'Tracking ID not found' });
        }

        // Log the change in DeliveryLog
        await DeliveryLog.create({
            trackingId: tracking.trackingId,
            userId: tracking.userId,
            eventType: status === 'delivered' ? 'parcel_delivered' : (status === 'retrieved' ? 'parcel_retrieved' : 'status_update'),
            details: `Status updated to ${status}`
        });

        res.json(tracking);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
