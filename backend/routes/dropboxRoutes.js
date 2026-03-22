const express = require('express');
const router = express.Router();
const Dropbox = require('../models/Dropbox');

/**
 * GET /api/dropbox/:userId
 * Get the dropbox registered to a specific user.
 */
router.get('/:userId', async (req, res) => {
  try {
    const dropbox = await Dropbox.findOne({ userId: req.params.userId });
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

module.exports = router;
