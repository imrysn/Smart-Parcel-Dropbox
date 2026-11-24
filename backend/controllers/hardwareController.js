/**
 * Hardware Controller
 * Handles ESP32-S3 onboarding tokens, barcode scanning, and offline sync.
 */

const Dropbox = require('../models/Dropbox');
const Tracking = require('../models/Tracking');
const ScanLog = require('../models/ScanLog');
const { membersOf, registeredBoxForDevice } = require('../utils/deviceSessions');

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
 * Authorize entry access for an eligible inbound barcode.
 * POST /api/hardware/verify-barcode
 */
const verifyBarcode = async (req, res) => {
  try {
    const { deviceId, barcode } = req.body;

    if (!deviceId || typeof barcode !== 'string') {
      return res.status(400).json({ allowed: false, message: 'deviceId and barcode are required' });
    }

    // 1. Multi-carrier normalization: strip non-alphanumeric characters except hyphens
    const sanitizedBarcode = barcode.trim().replace(/[^a-zA-Z0-9-]/g, '');
    if (!sanitizedBarcode) {
      return res.status(400).json({ allowed: false, message: 'Invalid barcode payload' });
    }

    console.log(`📦 [BARCODE-SCAN] Device: ${deviceId} | Raw: ${barcode} | Sanitized: ${sanitizedBarcode}`);

    // 2. Find associated dropbox and registered users
    const dropbox = await registeredBoxForDevice(deviceId);
    if (!dropbox) {
      return res.status(404).json({ allowed: false, message: 'Unregistered or unknown device' });
    }

    const registeredUsers = membersOf(dropbox);

    if (registeredUsers.length === 0) {
      return res.status(403).json({ allowed: false, message: 'No registered owners for this device' });
    }

    // 3. Search for tracking record linked to device users (case-insensitive)
    function escapeRegex(text) {
      return (text || '').replace(/[-[\]{}()*+?.:\\^$|#\s]/g, '\\$&');
    }
    const escaped = escapeRegex(sanitizedBarcode);

    let tracking = await Tracking.findOne({
      trackingId: { $regex: new RegExp(`^${escaped}$`, 'i') },
      userId: { $in: registeredUsers }
    }, '+pendingDropoffReviewId');

    // Flexible trim/append 'T' fallback for Shopee/J&T
    if (!tracking && sanitizedBarcode.toUpperCase().endsWith('T')) {
      const trimmed = escapeRegex(sanitizedBarcode.substring(0, sanitizedBarcode.length - 1));
      tracking = await Tracking.findOne({
        trackingId: { $regex: new RegExp(`^${trimmed}$`, 'i') },
        userId: { $in: registeredUsers }
      }, '+pendingDropoffReviewId');
    }
    if (!tracking) {
      const appended = escapeRegex(sanitizedBarcode + 'T');
      tracking = await Tracking.findOne({
        trackingId: { $regex: new RegExp(`^${appended}$`, 'i') },
        userId: { $in: registeredUsers }
      }, '+pendingDropoffReviewId');
    }

    if (!tracking) {
      // Log failed scan
      await ScanLog.create({
        scannedId: sanitizedBarcode,
        mode: 'drop_off',
        status: 'rejected',
        message: 'Tracking ID not recognized or registered to owner',
      });
      return res.status(404).json({ allowed: false, message: 'Tracking ID not found in owner registry' });
    }

    if (tracking.pendingDropoffReviewId) {
      return res.status(409).json({ allowed: false, reason: 'needs_review', message: 'Parcel awaiting owner review.' });
    }

    if (tracking.mode !== 'drop_off' || !['pending', 'in_transit'].includes(tracking.status)) {
      await ScanLog.create({
        scannedId: sanitizedBarcode,
        trackingId: tracking.trackingId,
        mode: 'drop_off',
        status: 'rejected',
        message: 'Tracking record is not eligible for drop-off',
      });
      return res.status(400).json({ allowed: false, message: 'Tracking record is not eligible for drop-off.' });
    }

    await ScanLog.create({
      scannedId: sanitizedBarcode,
      trackingId: tracking.trackingId,
      mode: 'drop_off',
      status: 'authorized',
      message: 'Entry access authorized. Deposit confirmation pending.',
    });

    return res.json({
      allowed: true,
      action: 'open_door',
      trackingId: tracking.trackingId,
      message: 'Entry access authorized. Deposit confirmation pending.'
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

    const dropbox = await registeredBoxForDevice(deviceId);
    if (!dropbox) {
      return res.status(404).json({ message: 'Unregistered hardware device' });
    }

    const registeredUsers = membersOf(dropbox);

    const activeTrackings = await Tracking.find({
      userId: { $in: registeredUsers },
      status: { $in: ['pending', 'in_transit', 'awaiting_pickup'] },
      pendingDropoffReviewId: { $exists: false },
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
