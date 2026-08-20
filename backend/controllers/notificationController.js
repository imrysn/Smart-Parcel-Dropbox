const Notification = require('../models/Notification');

// @desc    Create a notification
// @route   POST /api/notifications
exports.createNotification = async (req, res) => {
    try {
        const notificationData = { ...req.body, userId: req.userId };
        const notification = await Notification.create(notificationData);

        // Use global io if available
        const io = req.app.get('io');
        if (io) {
            io.to(notification.userId).emit('notificationNew', notification);
            console.log(`[SOCKET] notificationNew emitted for user: ${notification.userId}`);
        }

        res.status(201).json(notification);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get user notifications (supports pagination via ?page=1&limit=15)
// @route   GET /api/notifications/user/:userId
exports.getUserNotifications = async (req, res) => {
    try {
        const userId = req.params.userId;

        // Security check
        if (userId !== req.userId) {
            return res.status(403).json({ message: 'Access denied: cannot access another user\'s notifications' });
        }

        const page = req.query.page ? parseInt(req.query.page, 10) : null;
        const limit = req.query.limit ? parseInt(req.query.limit, 10) : null;

        let query = Notification.find({ userId }).sort({ timestamp: -1 });

        if (page && limit && page > 0 && limit > 0) {
            const skip = (page - 1) * limit;
            query = query.skip(skip).limit(limit);
        }

        const notifications = await query;
        res.json(notifications);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Mark notification as read
// @route   PATCH /api/notifications/:id/read
exports.markAsRead = async (req, res) => {
    try {
        const notification = await Notification.findById(req.params.id);
        
        if (!notification) {
            return res.status(404).json({ message: 'Notification not found' });
        }

        // Security check
        if (notification.userId !== req.userId) {
            return res.status(403).json({ message: 'Access denied: cannot modify another user\'s notification' });
        }

        notification.isRead = true;
        await notification.save();
        res.json(notification);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
// @desc    Mark all notifications as read for a user
// @route   PATCH /api/notifications/user/:userId/read
exports.markAllAsRead = async (req, res) => {
    try {
        const userId = req.params.userId;

        // Security check
        if (userId !== req.userId) {
            return res.status(403).json({ message: 'Access denied: cannot modify another user\'s notifications' });
        }

        await Notification.updateMany({ userId }, { isRead: true });
        res.json({ message: 'All notifications marked as read' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
