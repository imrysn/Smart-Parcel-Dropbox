/**
 * Hardware Controller
 * Handles ESP32-S3 onboarding tokens, barcode scanning, and offline sync.
 */

const Dropbox = require('../models/Dropbox');
const Tracking = require('../models/Tracking');
const ScanLog = require('../models/ScanLog');

// In-memory store for pending device registrations { token -> { deviceId, expiresAtMs } }
const pendingRegistrations = new Map();

/**
 * Generate dynamic pairing token for unboxed hardware
 * GET /api/hardware/init-token
 */
const initToken = async (req, res) => {
  try {
    const { deviceId } = req.query;
    if (!deviceId) {
      return res.status(400).json({ message: 'deviceId parameter is required' });
    }

    // Check if device is already registered
    const mongoose = require('mongoose');
    if (mongoose.connection.readyState === 1) {
      let dropbox = await Dropbox.findOne({ deviceId });
      if (dropbox && dropbox.isRegistered && (dropbox.userIds.length > 0 || dropbox.userId)) {
        return res.status(400).json({ message: 'Device is already registered' });
      }
    }

    // Generate random 6-character token e.g. SPDB-A8X92F
    const characters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let randomPart = '';
    for (let i = 0; i < 6; i++) {
      randomPart += characters.charAt(Math.floor(Math.random() * characters.length));
    }
    const token = `SPDB-${randomPart}`;
    const expiresAtMs = Date.now() + 15 * 60 * 1000; // 15 mins

    pendingRegistrations.set(token, { deviceId, expiresAtMs });

    // Clean up expired tokens
    for (const [key, val] of pendingRegistrations.entries()) {
      if (val.expiresAtMs < Date.now()) {
        pendingRegistrations.delete(key);
      }
    }

    console.log(`🔑 Generated Hardware Pairing Token: ${token} for Device: ${deviceId}`);

    res.json({
      success: true,
      deviceId,
      token,
      expiresInSeconds: 900
    });
  } catch (error) {
    console.error('Error generating init token:', error);
    res.status(500).json({ message: error.message });
  }
};

/**
 * Verify scanned parcel barcode with multi-carrier normalization and single-use enforcement
 * POST /api/hardware/verify-barcode
 */
const verifyBarcode = async (req, res) => {
  try {
    const { deviceId, barcode } = req.body;

    if (!deviceId || !barcode) {
      return res.status(400).json({ allowed: false, message: 'deviceId and barcode are required' });
    }

    // 1. Multi-carrier normalization: strip non-alphanumeric characters except hyphens
    let sanitizedBarcode = barcode.trim().replace(/[^a-zA-Z0-9-]/g, '');
    if (!sanitizedBarcode) {
      return res.status(400).json({ allowed: false, message: 'Invalid barcode payload' });
    }

    console.log(`📦 [BARCODE-SCAN] Device: ${deviceId} | Raw: ${barcode} | Sanitized: ${sanitizedBarcode}`);

    // 2. Find associated dropbox and registered users
    const dropbox = await Dropbox.findOne({ deviceId });
    if (!dropbox || !dropbox.isRegistered) {
      return res.status(404).json({ allowed: false, message: 'Unregistered or unknown device' });
    }

    const registeredUsers = dropbox.userIds && dropbox.userIds.length > 0
      ? dropbox.userIds
      : (dropbox.userId ? [dropbox.userId] : []);

    if (registeredUsers.length === 0) {
      return res.status(403).json({ allowed: false, message: 'No registered owners for this device' });
    }

    // 3. Search for tracking record linked to device users
    let tracking = await Tracking.findOne({
      trackingId: sanitizedBarcode,
      userId: { $in: registeredUsers }
    });

    // Flexible trim/append 'T' fallback for Shopee/J&T
    if (!tracking && sanitizedBarcode.toUpperCase().endsWith('T')) {
      const trimmed = sanitizedBarcode.substring(0, sanitizedBarcode.length - 1);
      tracking = await Tracking.findOne({ trackingId: trimmed, userId: { $in: registeredUsers } });
    }
    if (!tracking) {
      tracking = await Tracking.findOne({ trackingId: sanitizedBarcode + 'T', userId: { $in: registeredUsers } });
    }

    if (!tracking) {
      // Log failed scan
      await ScanLog.create({
        deviceId,
        barcode: sanitizedBarcode,
        success: false,
        reason: 'Tracking ID not recognized or registered to owner',
        scannedAt: new Date()
      });
      return res.status(404).json({ allowed: false, message: 'Tracking ID not found in owner registry' });
    }

    // 4. Enforce Single-Use Anti-Rescan Security Rule
    if (['delivered', 'done', 'retrieved'].includes(tracking.status)) {
      await ScanLog.create({
        deviceId,
        barcode: sanitizedBarcode,
        success: false,
        reason: 'Single-use security restriction: Parcel already delivered',
        scannedAt: new Date()
      });
      return res.status(400).json({ allowed: false, message: 'Parcel already delivered! Re-scan denied.' });
    }

    // 5. Valid deposit: update status and log scan
    tracking.status = 'delivered';
    tracking.deliveredAt = new Date();
    await tracking.save();

    await ScanLog.create({
      deviceId,
      barcode: sanitizedBarcode,
      success: true,
      reason: 'Valid drop-off deposit',
      scannedAt: new Date()
    });

    // Notify connected clients via Socket.IO
    const io = req.app.get('io');
    if (io) {
      io.emit('parcelDelivered', {
        deviceId,
        trackingId: tracking.trackingId,
        userId: tracking.userId,
        deliveredAt: tracking.deliveredAt
      });
    }

    return res.json({
      allowed: true,
      action: 'open_door',
      trackingId: tracking.trackingId,
      message: 'Barcode verified. Drop box unlocked.'
    });

  } catch (error) {
    console.error('Error verifying barcode:', error);
    res.status(500).json({ allowed: false, message: error.message });
  }
};

/**
 * Offline Sync: Fetch active barcodes for local hardware SQLite caching
 * GET /api/hardware/sync-active-barcodes/:deviceId
 */
const syncActiveBarcodes = async (req, res) => {
  try {
    const { deviceId } = req.params;

    const dropbox = await Dropbox.findOne({ deviceId });
    if (!dropbox || !dropbox.isRegistered) {
      return res.status(404).json({ message: 'Unregistered hardware device' });
    }

    const registeredUsers = dropbox.userIds && dropbox.userIds.length > 0
      ? dropbox.userIds
      : (dropbox.userId ? [dropbox.userId] : []);

    const activeTrackings = await Tracking.find({
      userId: { $in: registeredUsers },
      status: { $in: ['pending', 'in_transit', 'awaiting_pickup'] }
    }).select('trackingId mode status createdAt');

    res.json({
      deviceId,
      syncedAt: new Date(),
      count: activeTrackings.length,
      barcodes: activeTrackings.map(t => t.trackingId),
      pruneBeforeDate: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) // 30 days ago
    });
  } catch (error) {
    console.error('Error syncing barcodes:', error);
    res.status(500).json({ message: error.message });
  }
};

module.exports = {
  initToken,
  verifyBarcode,
  syncActiveBarcodes,
  pendingRegistrations
};
