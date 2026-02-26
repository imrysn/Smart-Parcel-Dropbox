const Tracking = require('../models/Tracking');
const DeliveryLog = require('../models/DeliveryLog');
const Notification = require('../models/Notification');

// @desc    Register a tracking ID
exports.registerTracking = async (req, res) => {
    try {
        const { trackingId, userId, shopName, expectedDeliveryDate, mode } = req.body;

        const exists = await Tracking.findOne({ trackingId });
        if (exists) {
            return res.status(400).json({ message: 'Tracking ID already registered' });
        }

        const tracking = await Tracking.create({
            trackingId,
            userId,
            shopName,
            expectedDeliveryDate,
            mode: mode || 'drop_off',   // default: user registers to receive a drop-off
        });

        // Use global io if available
        const io = req.app.get('io');
        if (io) {
            io.to(userId).emit('trackingUpdate', tracking);
            console.log(`[SOCKET] trackingUpdate emitted for user: ${userId}`);
        }

        // Create a notification for the registration
        const isPickUp = mode === 'pick_up' || mode === 'pickup';
        await Notification.create({
            userId,
            title: isPickUp ? 'Pickup Registered' : 'Delivery Registered',
            body: `Tracking ID ${trackingId} has been registered for ${isPickUp ? 'pick up' : 'drop off'}.`,
            type: 'system'
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

        // Use global io if available
        const io = req.app.get('io');
        if (io) {
            io.to(tracking.userId).emit('trackingUpdate', tracking);
            console.log(`[SOCKET] trackingUpdate (status change) emitted for user: ${tracking.userId}`);
        }

        res.json(tracking);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Reset a completed tracking record back to 'pending' (FOR TESTING ONLY)
// @route   POST /api/tracking/:trackingId/reset
exports.resetTracking = async (req, res) => {
    try {
        const tracking = await Tracking.findOne({ trackingId: req.params.trackingId });

        if (!tracking) {
            return res.status(404).json({ message: 'Tracking ID not found' });
        }

        const completedStatuses = ['delivered', 'done', 'retrieved', 'awaiting_pickup', 'ready_for_pickup'];
        if (!completedStatuses.includes(tracking.status)) {
            return res.status(400).json({
                message: `Cannot reset: status is '${tracking.status}'. Only completed parcels can be reset.`
            });
        }

        const updated = await Tracking.findOneAndUpdate(
            { trackingId: req.params.trackingId },
            {
                $set: {
                    status: 'pending',
                    deliveredAt: null,
                    retrievedAt: null,
                    doneAt: null,
                }
            },
            { new: true }
        );

        console.log(`🔄 [TEST] Reset tracking ${req.params.trackingId} → pending`);

        const io = req.app.get('io');
        if (io) {
            io.to(updated.userId).emit('trackingUpdate', updated);
        }

        res.json({ message: 'Reset to pending for re-testing', tracking: updated });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
