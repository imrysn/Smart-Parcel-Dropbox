const Tracking = require('../models/Tracking');
const DeliveryLog = require('../models/DeliveryLog');
const Notification = require('../models/Notification');

function escapeRegex(text) {
    return (text || '').replace(/[-[\]{}()*+?.:\\^$|#\s]/g, '\\$&');
}

// @desc    Register a tracking ID
exports.registerTracking = async (req, res) => {
    try {
        const { trackingId: rawId, shopName, expectedDeliveryDate, mode } = req.body;
        const userId = req.userId; // Securely get userId from auth token
        const trackingId = (rawId || '').trim();
        const escaped = escapeRegex(trackingId);

        const exists = await Tracking.findOne({ trackingId: { $regex: new RegExp(`^${escaped}$`, 'i') } });
        if (exists) {
            console.log(`[TESTING] Tracking ID ${trackingId} already exists. Overwriting for reuse.`);
            // Clean up old records for a fresh start
            await Tracking.deleteOne({ _id: exists._id });
            await DeliveryLog.deleteMany({ trackingId: exists.trackingId });
        }

        const tracking = await Tracking.create({
            trackingId,
            userId,
            shopName,
            expectedDeliveryDate,
            mode: mode || 'drop_off',
        });

        // Use global io if available
        const io = req.app.get('io');
        if (io) {
            io.to(userId).emit('trackingUpdate', tracking);
            io.to('esp32_device').emit('registerTracking', { trackingId, mode: mode || 'drop_off' });
            console.log(`[SOCKET] trackingUpdate emitted for user: ${userId} & esp32_device`);
        }

        // Create a notification for the registration
        const isPickUp = mode === 'pick_up' || mode === 'pickup';
        await Notification.create({
            userId,
            title: isPickUp ? 'Pickup Registered' : 'Delivery Registered',
            message: `Tracking ID ${trackingId} has been registered for ${isPickUp ? 'pick up' : 'drop off'}.`,
            type: 'system_alert'
        });

        res.status(201).json(tracking);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get user tracking IDs
exports.getUserTracking = async (req, res) => {
    try {
        const userId = req.params.userId;
        
        // Security check: only allow users to see their own tracking data
        if (userId !== req.userId) {
            return res.status(403).json({ message: 'Access denied: cannot access another user\'s data' });
        }

        const tracking = await Tracking.find({ userId }).sort({ createdAt: -1 });
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

// @desc    Get tracking by ID (case-insensitive)
// @route   GET /api/tracking/:trackingId
exports.getTrackingById = async (req, res) => {
    try {
        const rawId = (req.params.trackingId || '').trim();
        const escaped = escapeRegex(rawId);
        const tracking = await Tracking.findOne({ trackingId: { $regex: new RegExp(`^${escaped}$`, 'i') } });
        if (!tracking) {
            return res.status(404).json({ message: 'Tracking ID not found' });
        }
        res.json(tracking);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Update tracking status (case-insensitive)
// @route   PATCH /api/tracking/:trackingId/status
exports.updateTrackingStatus = async (req, res) => {
    try {
        const { status } = req.body;
        const rawId = (req.params.trackingId || '').trim();
        const escaped = escapeRegex(rawId);
        const tracking = await Tracking.findOneAndUpdate(
            { trackingId: { $regex: new RegExp(`^${escaped}$`, 'i') } },
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
        const rawId = (req.params.trackingId || '').trim();
        const escaped = escapeRegex(rawId);
        const tracking = await Tracking.findOne({ trackingId: { $regex: new RegExp(`^${escaped}$`, 'i') } });

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
            { _id: tracking._id },
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

        console.log(`🔄 [TEST] Reset tracking ${tracking.trackingId} → pending`);

        const io = req.app.get('io');
        if (io) {
            io.to(updated.userId).emit('trackingUpdate', updated);
        }

        res.json({ message: 'Reset to pending for re-testing', tracking: updated });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
// @desc    Simulate automated tracking progression (FOR DEMO/TESTING)
// @route   POST /api/tracking/:trackingId/simulate
exports.simulateTracking = async (req, res) => {
    try {
        const rawId = (req.params.trackingId || '').trim();
        const escaped = escapeRegex(rawId);
        const tracking = await Tracking.findOne({ trackingId: { $regex: new RegExp(`^${escaped}$`, 'i') } });

        if (!tracking) {
            return res.status(404).json({ message: 'Tracking ID not found' });
        }

        const trackingId = tracking.trackingId;
        const io = req.app.get('io');
        const statuses = tracking.mode === 'pickup' 
            ? ['pending', 'awaiting_pickup', 'ready_for_pickup', 'retrieved', 'done']
            : ['pending', 'in_transit', 'delivered', 'done'];

        // Start the simulation in the "background"
        let currentIndex = statuses.indexOf(tracking.status);
        if (currentIndex === -1) currentIndex = 0;

        const runSimulation = async () => {
            for (let i = currentIndex + 1; i < statuses.length; i++) {
                const nextStatus = statuses[i];
                
                // Wait for a few seconds between steps
                await new Promise(resolve => setTimeout(resolve, 5000));

                const updated = await Tracking.findOneAndUpdate(
                    { _id: tracking._id },
                    { 
                        $set: { 
                            status: nextStatus,
                            deliveredAt: nextStatus === 'delivered' ? new Date() : undefined,
                            retrievedAt: nextStatus === 'retrieved' ? new Date() : undefined,
                            doneAt: nextStatus === 'done' ? new Date() : undefined
                        } 
                    },
                    { new: true }
                );

                if (io) {
                    io.to(updated.userId).emit('trackingUpdate', updated);
                    io.emit('trackingStatusChanged', {
                        trackingId,
                        status: nextStatus,
                        mode: updated.mode,
                        timestamp: new Date()
                    });
                }
                
                console.log(`🤖 [SIMULATION] ${trackingId} -> ${nextStatus}`);
            }
        };

        runSimulation(); // Fire and forget

        res.json({ message: 'Simulation started', targetStatuses: statuses.slice(currentIndex + 1) });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Delete a tracking ID
// @route   DELETE /api/tracking/:trackingId
exports.deleteTracking = async (req, res) => {
    try {
        const rawId = (req.params.trackingId || '').trim();
        const userId = req.userId; // Securely get userId from auth token
        const escaped = escapeRegex(rawId);

        const tracking = await Tracking.findOne({ trackingId: { $regex: new RegExp(`^${escaped}$`, 'i') } });

        if (!tracking) {
            return res.status(404).json({ message: 'Tracking ID not found' });
        }

        // Security check: only allow users to delete their own tracking data
        if (tracking.userId !== userId) {
            return res.status(403).json({ message: 'Access denied: cannot delete another user\'s data' });
        }

        await Tracking.deleteOne({ _id: tracking._id });

        // Use global io if available to notify the user
        const io = req.app.get('io');
        if (io) {
            io.to(userId).emit('trackingDeleted', { trackingId: tracking.trackingId });
            console.log(`[SOCKET] trackingDeleted emitted for user: ${userId}`);
        }

        res.json({ message: 'Tracking ID deleted successfully' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
