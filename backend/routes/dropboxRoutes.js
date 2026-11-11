const crypto = require('crypto');
const express = require('express');
const router = express.Router();
const Dropbox = require('../models/Dropbox');
const User = require('../models/User');
const { authMiddleware } = require('../utils/auth');

const { pendingRegistrations } = require('../controllers/hardwareController');

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function resolvePrimaryOwnerId(dropbox) {
  if (!dropbox) return null;
  return dropbox.primaryUserId || dropbox.userId || (dropbox.userIds && dropbox.userIds[0]) || null;
}

// All dropbox routes are protected
router.use(authMiddleware);

/**
 * POST /api/dropbox/claim
 * Claim and pair an unboxed hardware dropbox device to the authenticated owner account.
 */
router.post('/claim', async (req, res) => {
  try {
    const { token, name } = req.body;
    const formattedToken = typeof token === 'string' ? token.trim().toUpperCase() : '';

    if (!formattedToken) {
      return res.status(400).json({ message: 'Pairing token from the Dropbox LCD is required' });
    }

    const pending = pendingRegistrations.get(formattedToken);
    if (!pending) {
      return res.status(400).json({ message: 'Invalid or expired pairing token. Please scan the QR code on your physical box LCD.' });
    }

    const expiry = pending.expiresAtMs || pending.expiresAt;
    if (expiry && expiry < Date.now()) {
      pendingRegistrations.delete(formattedToken);
      return res.status(400).json({ message: 'Pairing token has expired. Please refresh on physical box LCD.' });
    }

    const targetDeviceId = pending.deviceId;
    pendingRegistrations.delete(formattedToken);

    if (!targetDeviceId) {
      return res.status(400).json({ message: 'Invalid pairing token or device ID' });
    }

    // Find existing device document or create new active device record
    let dropbox = await Dropbox.findOne({ deviceId: targetDeviceId });
    const wasAlreadyRegistered = Boolean(dropbox && dropbox.isRegistered);

    if (!dropbox) {
      dropbox = new Dropbox({
        deviceId: targetDeviceId,
        primaryUserId: req.userId,
        userIds: [req.userId],
        name: name || 'My Smart Parcel Dropbox',
        isRegistered: true,
        status: pending.alreadyConnected ? 'online' : 'offline',
        registeredAt: new Date(),
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
      if (!wasAlreadyRegistered) {
        dropbox.status = pending.alreadyConnected ? 'online' : dropbox.status || 'offline';
        dropbox.registeredAt = new Date();
        if (name) dropbox.name = name;
      } else if (!dropbox.name && name) {
        dropbox.name = name;
      }
    }

    await dropbox.save();

    const skipWifiSetup = Boolean(
      pending.alreadyConnected ||
      pending.isHouseholdInvite ||
      (wasAlreadyRegistered && (dropbox.wifiSSID || dropbox.status === 'online'))
    );

    // Notify the claiming owner and hardware unit via Socket.IO
    const io = req.app.get('io');
    if (io) {
      io.to(req.userId).emit('deviceRegistered', {
        deviceId: targetDeviceId,
        alreadyConnected: skipWifiSetup,
        dropbox,
      });
      if (!pending.isHouseholdInvite) {
        io.to('esp32_device').emit('deviceRegistered', { deviceId: targetDeviceId });
      }
    }

    console.log(`✅ [DEVICE-CLAIMED] Device: ${targetDeviceId} claimed by User: ${req.userId}`);

    res.json({
      success: true,
      message: 'Dropbox paired successfully',
      deviceId: targetDeviceId,
      alreadyConnected: skipWifiSetup,
      dropbox,
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
    } else if (dropbox.primaryUserId === uid || dropbox.userId === uid) {
      // Promote next remaining household member cleanly
      await Dropbox.updateOne(
        { _id: dropbox._id },
        {
          $set: {
            primaryUserId: remainingUsers[0],
            ...(dropbox.userId === uid ? { userId: remainingUsers[0] } : {}),
          }
        }
      );
    }

    res.json({ message: 'Dropbox unregistered successfully', deviceId, remainingUsers: remainingUsers.length });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

/**
 * GET /api/dropbox/:deviceId/members
 * List household members paired to this device (must already belong to device).
 */
router.get('/:deviceId/members', async (req, res) => {
  try {
    const dropbox = await Dropbox.findOne({
      deviceId: req.params.deviceId,
      isRegistered: true,
      $or: [{ userIds: req.userId }, { primaryUserId: req.userId }, { userId: req.userId }]
    });

    if (!dropbox) {
      return res.status(403).json({ message: 'Access denied: you are not paired to this device' });
    }

    const memberIds = Array.from(new Set([
      ...(dropbox.userIds || []),
      ...(dropbox.primaryUserId ? [dropbox.primaryUserId] : []),
      ...(dropbox.userId ? [dropbox.userId] : []),
    ])).filter(Boolean);

    const users = await User.find({ _id: { $in: memberIds } }).select('fullName email');
    const byId = new Map(users.map((u) => [u._id.toString(), u]));

    const primaryId = resolvePrimaryOwnerId(dropbox);
    const members = memberIds.map((id) => {
      const user = byId.get(id);
      return {
        id,
        fullName: user?.fullName || 'Household Member',
        email: user?.email || '',
        isPrimaryOwner: id === primaryId,
      };
    });

    res.json({
      deviceId: dropbox.deviceId,
      name: dropbox.name,
      primaryUserId: primaryId,
      isPrimaryOwner: req.userId === primaryId,
      members,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

/**
 * DELETE /api/dropbox/:deviceId/members/:memberId
 * Remove a household member from a paired dropbox (primary owner only).
 */
router.delete('/:deviceId/members/:memberId', async (req, res) => {
  try {
    const { deviceId, memberId } = req.params;
    const dropbox = await Dropbox.findOne({ deviceId, isRegistered: true });

    if (!dropbox) {
      return res.status(404).json({ message: 'Dropbox not found' });
    }

    const primaryId = resolvePrimaryOwnerId(dropbox);
    if (req.userId !== primaryId) {
      return res.status(403).json({ message: 'Only the primary owner can remove household members' });
    }

    if (memberId === primaryId) {
      return res.status(400).json({ message: 'Use Unlink Hardware to remove yourself as primary owner' });
    }

    await Dropbox.updateOne(
      { _id: dropbox._id },
      { $pull: { userIds: memberId } }
    );

    const updated = await Dropbox.findById(dropbox._id);
    const remaining = updated?.userIds || [];

    const io = req.app.get('io');
    if (io) {
      io.to(memberId).emit('deviceUnregistered', { deviceId, removedByOwner: true });
    }

    res.json({
      message: 'Member removed successfully',
      deviceId,
      remainingUsers: remaining.length,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

/**
 * POST /api/dropbox/:deviceId/members
 * Directly pair a household member by their registered account email (primary owner only).
 */
router.post('/:deviceId/members', async (req, res) => {
  try {
    const { deviceId } = req.params;
    const rawEmail = req.body?.email;
    const email = typeof rawEmail === 'string' ? rawEmail.trim().toLowerCase() : '';

    if (!EMAIL_REGEX.test(email)) {
      return res.status(400).json({ message: 'Please enter a valid email address' });
    }

    const dropbox = await Dropbox.findOne({ deviceId, isRegistered: true });
    if (!dropbox) {
      return res.status(404).json({ message: 'Dropbox not found' });
    }

    const primaryId = resolvePrimaryOwnerId(dropbox);
    if (req.userId !== primaryId) {
      return res.status(403).json({ message: 'Only the primary owner can add household members' });
    }

    const targetUser = await User.findOne({ email }).select('fullName email');
    if (!targetUser) {
      return res.status(404).json({
        message: 'No account found for that email. Ask them to create an account in the app first.',
      });
    }

    const targetUserId = targetUser._id.toString();
    if ((dropbox.userIds || []).includes(targetUserId) || primaryId === targetUserId) {
      return res.status(400).json({ message: 'This person is already paired to this dropbox' });
    }

    const otherDropbox = await Dropbox.findOne({
      isRegistered: true,
      deviceId: { $ne: dropbox.deviceId },
      $or: [{ userIds: targetUserId }, { primaryUserId: targetUserId }, { userId: targetUserId }],
    });
    if (otherDropbox) {
      return res.status(400).json({ message: 'That account is already paired to another dropbox' });
    }

    await Dropbox.updateOne(
      { _id: dropbox._id },
      { $addToSet: { userIds: targetUserId } }
    );

    const updated = await Dropbox.findById(dropbox._id);
    const io = req.app.get('io');
    if (io) {
      io.to(targetUserId).emit('deviceRegistered', {
        deviceId: dropbox.deviceId,
        alreadyConnected: true,
        addedByOwner: true,
        dropbox: updated,
      });
    }

    res.status(201).json({
      message: 'Household member added successfully',
      member: {
        id: targetUserId,
        fullName: targetUser.fullName || 'Household Member',
        email: targetUser.email,
        isPrimaryOwner: false,
      },
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

/**
 * POST /api/dropbox/:deviceId/invite
 * Generate an in-app 15-minute QR/PIN pairing token for a household member (primary owner only).
 */
router.post('/:deviceId/invite', async (req, res) => {
  try {
    const { deviceId } = req.params;
    const dropbox = await Dropbox.findOne({ deviceId, isRegistered: true });
    if (!dropbox) {
      return res.status(404).json({ message: 'Dropbox not found' });
    }

    const primaryId = resolvePrimaryOwnerId(dropbox);
    if (req.userId !== primaryId) {
      return res.status(403).json({ message: 'Only the primary owner can generate pairing invites' });
    }

    const now = Date.now();
    for (const [key, val] of pendingRegistrations.entries()) {
      const exp = val?.expiresAtMs || val?.expiresAt || 0;
      if (exp < now) pendingRegistrations.delete(key);
    }

    const pin = crypto.randomInt(100000, 1000000).toString();
    const token = `SPDB-REG-${pin}`;
    const ttlMs = 15 * 60 * 1000;
    const expiresAtMs = now + ttlMs;

    pendingRegistrations.set(token, {
      deviceId: dropbox.deviceId,
      expiresAt: expiresAtMs,
      expiresAtMs,
      alreadyConnected: true,
      isHouseholdInvite: true,
      invitedBy: req.userId,
    });

    res.status(201).json({
      token,
      pin,
      expiresInSeconds: 900,
      expiresAt: new Date(expiresAtMs).toISOString(),
      deviceName: dropbox.name || 'My Smart Parcel Dropbox',
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

module.exports = router;

