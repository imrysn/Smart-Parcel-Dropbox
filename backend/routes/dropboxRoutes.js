const express = require('express');
const router = express.Router();
const Dropbox = require('../models/Dropbox');

/**
 * GET /api/dropbox/:userId
 * Get the dropbox registered to a specific user.
 * Supports multi-user: searches userIds array, falls back to legacy userId field.
 */
router.get('/:userId', async (req, res) => {
  try {
    const uid = req.params.userId;
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
    const dropbox = await Dropbox.findOneAndUpdate(
      { deviceId: req.params.deviceId },
      { $set: { name } },
      { new: true }
    );
    if (!dropbox) {
      return res.status(404).json({ message: 'Dropbox not found' });
    }
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

