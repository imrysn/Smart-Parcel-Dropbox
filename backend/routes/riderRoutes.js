const express = require('express');
const router = express.Router();
const Rider = require('../models/Rider');
const Dropbox = require('../models/Dropbox');
const { authMiddleware } = require('../utils/auth');

router.use(authMiddleware);

async function getUserDropboxIds(userId) {
    const boxes = await Dropbox.find({
        isRegistered: true,
        $or: [{ userIds: userId }, { primaryUserId: userId }, { userId }]
    }).select('deviceId');
    return boxes.map((b) => b.deviceId).filter(Boolean);
}

// Get trusted courier passes owned by caller or paired dropbox
router.get('/', async (req, res) => {
    try {
        const deviceIds = await getUserDropboxIds(req.userId);
        const query = deviceIds.length > 0
            ? { $or: [{ userId: req.userId }, { deviceId: { $in: deviceIds } }] }
            : { userId: req.userId };

        const riders = await Rider.find(query).sort({ createdAt: -1 });
        res.json(riders);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

// Add a new trusted courier pass
router.post('/', async (req, res) => {
    const riderId = typeof req.body?.riderId === 'string' ? req.body.riderId.trim() : '';
    const name = typeof req.body?.name === 'string' ? req.body.name.trim() : '';

    if (!riderId || riderId.length < 3 || !name) {
        return res.status(400).json({ message: 'Courier name and badge ID (min 3 characters) are required' });
    }

    try {
        const deviceIds = await getUserDropboxIds(req.userId);
        const rider = new Rider({
            riderId,
            name,
            userId: req.userId,
            deviceId: deviceIds[0] || null,
        });

        const newRider = await rider.save();
        res.status(201).json(newRider);
    } catch (error) {
        if (error.code === 11000) {
            return res.status(400).json({ message: 'Courier pass ID already exists' });
        }
        res.status(400).json({ message: error.message });
    }
});

// Delete a trusted courier pass (owner-scoped)
router.delete('/:id', async (req, res) => {
    try {
        const rider = await Rider.findById(req.params.id);
        if (!rider) return res.status(404).json({ message: 'Courier pass not found' });

        const deviceIds = await getUserDropboxIds(req.userId);
        const isOwner = rider.userId === req.userId || (rider.deviceId && deviceIds.includes(rider.deviceId));
        if (!isOwner) {
            return res.status(403).json({ message: 'Access denied: cannot remove another user\'s courier pass' });
        }

        await Rider.deleteOne({ _id: rider._id });
        res.json({ message: 'Courier pass removed' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

module.exports = router;
