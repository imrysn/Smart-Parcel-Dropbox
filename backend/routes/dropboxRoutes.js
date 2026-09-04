const express = require('express');
const router = express.Router();
const Dropbox = require('../models/Dropbox');
const { authMiddleware } = require('../utils/auth');

const { pendingRegistrations } = require('../controllers/hardwareController');

// All dropbox routes are protected
router.use(authMiddleware);

/**
 * POST /api/dropbox/claim
 * Claim and pair an unboxed hardware dropbox device to the authenticated owner account.
 */
router.post('/claim', async (req, res) => {
  try {
    const { token, deviceId, name, buttonConfirmed } = req.body;

    if (!token && !deviceId) {
      return res.status(400).json({ message: 'Token or deviceId is required to claim hardware' });
    }

    let targetDeviceId = deviceId;

    // Validate token if provided
    if (token) {
      const formattedToken = token.trim().toUpperCase();
      const pending = pendingRegistrations.get(formattedToken);
      if (pending) {
        const expiry = pending.expiresAtMs || pending.expiresAt;
        if (expiry && expiry < Date.now()) {
          pendingRegistrations.delete(formattedToken);
          return res.status(400).json({ message: 'Pairing token has expired. Please refresh on physical box LCD.' });
        }
        targetDeviceId = pending.deviceId;
        pendingRegistrations.delete(formattedToken);
      }
    }

    if (!targetDeviceId) {
      return res.status(400).json({ message: 'Invalid pairing token or device ID' });
    }

    // Find existing device document or create new active device record
    let dropbox = await Dropbox.findOne({ deviceId: targetDeviceId });

    if (!dropbox) {
      dropbox = new Dropbox({
        deviceId: targetDeviceId,
        primaryUserId: req.userId,
        userIds: [req.userId],
        name: name || 'My Smart Parcel Dropbox',
        isRegistered: true,
        status: 'online'
      });
    } else {
      // Add user to userIds array if not already present
      if (!dropbox.userIds.includes(req.userId)) {
        dropbox.userIds.push(req.userId);
      }
      if (!dropbox.primaryUserId) {
        dropbox.primaryUserId = req.userId;
      }
      dropbox.isRegistered = true;
      dropbox.status = 'online';
      if (name) dropbox.name = name;
    }

    await dropbox.save();

    // Broadcast WebSocket notification to hardware box
    const io = req.app.get('io');
    if (io) {
      io.emit('deviceRegistered', {
        deviceId: targetDeviceId,
        primaryUserId: dropbox.primaryUserId,
        userIds: dropbox.userIds
      });
    }

    console.log(`✅ [DEVICE-CLAIMED] Device: ${targetDeviceId} claimed by User: ${req.userId}`);

    res.json({
      success: true,
      message: 'Dropbox paired successfully',
      dropbox
    });
  } catch (error) {
    console.error('Error claiming dropbox:', error);
    res.status(500).json({ message: error.message });
  }
});

/**
 * GET /api/dropbox/:userId
 * Get the dropbox registered to a specific user.
 * Supports multi-user: searches userIds array, falls back to legacy userId field.
 */
router.get('/:userId', async (req, res) => {
  try {
    const uid = req.params.userId;
    
    // Security check: only show own dropbox
    if (uid !== req.userId) {
      return res.status(403).json({ message: 'Access denied: cannot access another user\'s dropbox' });
    }

    // Primary lookup: new multi-user array
    let dropbox = await Dropbox.findOne({ userIds: uid });
    // Legacy fallback: old single-user documents
    if (!dropbox) {
      dropbox = await Dropbox.findOne({ userId: uid });
    }
    if (!dropbox) {
      return res.status(404).json({ message: 'No dropbox registered for this user' });
    }
    res.json(dropbox);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

/**
 * PATCH /api/dropbox/:deviceId
 * Update dropbox name or other metadata.
 */
router.patch('/:deviceId', async (req, res) => {
  try {
    const { name } = req.body;
    
    // Security check: ensure user is registered for this device
    const exists = await Dropbox.findOne({ 
      deviceId: req.params.deviceId,
      $or: [{ userIds: req.userId }, { userId: req.userId }]
    });

    if (!exists) {
      return res.status(403).json({ message: 'Access denied: you are not registered for this device' });
    }

    const dropbox = await Dropbox.findOneAndUpdate(
      { deviceId: req.params.deviceId },
      { $set: { name } },
      { new: true }
    );
    
    res.json(dropbox);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

/**
 * DELETE /api/dropbox/:userId
 * Remove a specific user's registration from a dropbox device.
 * If this was the last registered user, the device is fully reset to unregistered.
 */
router.delete('/:userId', async (req, res) => {
  try {
    const uid = req.params.userId;

    // Security check: only unregister yourself
    if (uid !== req.userId) {
      return res.status(403).json({ message: 'Access denied: cannot unregister another user' });
    }

    // Find by userIds array OR legacy userId field
    let dropbox = await Dropbox.findOne({ userIds: uid });
    if (!dropbox) dropbox = await Dropbox.findOne({ userId: uid });

    if (!dropbox) {
      return res.status(404).json({ message: 'No dropbox registered for this user' });
    }

    const deviceId = dropbox.deviceId;

    // Pull this user out of the array
    await Dropbox.updateOne(
      { _id: dropbox._id },
      { $pull: { userIds: uid } }
    );

    // Reload to check if any users remain
    const updated = await Dropbox.findById(dropbox._id);
    const remainingUsers = updated.userIds || [];

    if (remainingUsers.length === 0) {
      // Last user unregistered — fully reset the device
      await Dropbox.updateOne(
        { _id: dropbox._id },
        {
          $set: {
            isRegistered: false,
            primaryUserId: null,
            userId: null,
            name: 'Unregistered Device',
            status: 'unregistered',
            wifiSSID: null,
          }
        }
      );

      // Notify hardware to revert to setup mode
      const io = req.app.get('io');
      if (io) {
        io.to('esp32_device').emit('deviceUnregistered', { deviceId });
      }
    }

    res.json({ message: 'Dropbox unregistered successfully', deviceId, remainingUsers: remainingUsers.length });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

module.exports = router;

