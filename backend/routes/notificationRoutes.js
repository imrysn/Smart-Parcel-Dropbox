const express = require('express');
const router = express.Router();
const { createNotification, getUserNotifications, markAsRead, markAllAsRead } = require('../controllers/notificationController');
const { authMiddleware } = require('../utils/auth');
const Notification = require('../models/Notification');
const Tracking = require('../models/Tracking');
const PushInstallation = require('../models/PushInstallation');
const deliveryPush = require('../utils/deliveryPush');

router.use(authMiddleware);

router.put('/push-installations/:id', async (req, res, next) => {
    if (!deliveryPush.enabled()) return res.sendStatus(503);
    const { id } = req.params;
    const { token } = req.body || {};
    if (!/^[a-f0-9]{32}$/.test(id) || typeof token !== 'string' || !/^\S{20,4096}$/.test(token)) {
        return res.sendStatus(400);
    }
    if (!Number.isFinite(req.sessionExpiresAt)) return res.sendStatus(401);
    try {
        await PushInstallation.findByIdAndUpdate(id, { $set: {
            token, platform: 'android', userId: req.userId, expiresAt: new Date(req.sessionExpiresAt),
        } }, { upsert: true, runValidators: true });
        res.sendStatus(204);
    } catch (error) {
        if (error.code === 11000) return res.sendStatus(409);
        next(error);
    }
});

router.delete('/push-installations/:id', async (req, res, next) => {
    try {
        await PushInstallation.deleteOne({ _id: req.params.id, userId: req.userId });
        res.sendStatus(204);
    } catch (error) {
        next(error);
    }
});

router.get('/:id/parcel', async (req, res, next) => {
    if (!/^[a-f0-9]{24}$/.test(req.params.id)) return res.sendStatus(404);
    try {
        const event = await Notification.findOne({
            _id: req.params.id, userId: req.userId, type: 'parcel_delivered',
        });
        if (!event?.trackingId) return res.sendStatus(404);
        const parcel = await Tracking.findOne({ trackingId: event.trackingId, userId: req.userId });
        if (!parcel) return res.sendStatus(404);
        res.json(parcel);
    } catch (error) {
        next(error);
    }
});

router.post('/', createNotification);
router.get('/user/:userId', getUserNotifications);
router.patch('/:id/read', markAsRead);
router.patch('/user/:userId/read', markAllAsRead);

module.exports = router;
