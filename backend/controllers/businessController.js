const Tracking = require('../models/Tracking');
const Dropbox = require('../models/Dropbox');

/**
 * GET /api/business/daily-digest
 * Returns fulfillment digest statistics for the logged-in user
 */
exports.getDailyDigest = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;

    // Start & end of today (local server date)
    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);

    const endOfDay = new Date();
    endOfDay.setHours(23, 59, 59, 999);

    // Fetch user trackings
    const trackings = await Tracking.find({ userId });

    // Outbound customer packages staged today or currently awaiting pickup
    const outboundAll = trackings.filter(t => t.direction === 'OUTBOUND_CUSTOMER');
    const outboundToday = outboundAll.filter(t => new Date(t.createdAt) >= startOfDay);
    const outboundCollected = outboundToday.filter(t => t.status === 'retrieved' || t.status === 'done');
    const outboundPending = outboundAll.filter(t => t.status === 'pending' || t.status === 'awaiting_pickup');

    // Inbound supplier parcels delivered today
    const inboundToday = trackings.filter(t => 
      t.direction !== 'OUTBOUND_CUSTOMER' && 
      (t.status === 'delivered' || t.status === 'done') && 
      t.deliveredAt && new Date(t.deliveredAt) >= startOfDay
    );

    // Capacity check from Dropbox model
    const dropbox = await Dropbox.findOne({ userIds: userId }) || await Dropbox.findOne({ userId });
    const dropoffCount = dropbox ? (dropbox.dropoffCount || 0) : 0;
    const pickupCount = dropbox ? (dropbox.pickupCount || 0) : 0;
    const totalParcelsInBox = dropoffCount + pickupCount;
    // Assuming 5 parcels capacity max for standard dropbox unit
    const maxCapacity = 5;
    const capacityPercent = Math.min(100, Math.round((totalParcelsInBox / maxCapacity) * 100));

    res.json({
      success: true,
      data: {
        date: new Date().toISOString(),
        outbound: {
          totalStagedToday: outboundToday.length,
          collectedToday: outboundCollected.length,
          pendingPickupCount: outboundPending.length,
        },
        inbound: {
          deliveredToday: inboundToday.length,
        },
        capacity: {
          currentItems: totalParcelsInBox,
          maxCapacity,
          percent: capacityPercent,
          status: capacityPercent >= 80 ? 'CRITICAL' : (capacityPercent >= 60 ? 'WARNING' : 'HEALTHY')
        }
      }
    });
  } catch (err) {
    console.error('❌ getDailyDigest error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * POST /api/business/outbound-staging
 * Stage a new customer order into the dropbox for courier pickup
 */
exports.stageOutboundPackage = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const { trackingId: rawId, shopName, customerName, customerPhone, courierName } = req.body;
    const trackingId = (rawId || '').trim();

    if (!trackingId || !customerName) {
      return res.status(400).json({ success: false, message: 'trackingId and customerName are required' });
    }

    // Check if trackingId exists - overwrite for test reuse
    const escaped = trackingId.replace(/[-[\]{}()*+?.:\\^$|#\s]/g, '\\$&');
    const existing = await Tracking.findOne({ trackingId: { $regex: new RegExp(`^${escaped}$`, 'i') } });
    if (existing) {
      console.log(`[TESTING] Outbound tracking ID ${trackingId} already exists. Overwriting for reuse.`);
      await Tracking.deleteOne({ _id: existing._id });
    }

    // Generate 6-digit courier OTP PIN
    const courierOtp = Math.floor(100000 + Math.random() * 900000).toString();
    const courierOtpExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours

    const newTracking = await Tracking.create({
      trackingId,
      userId,
      shopName: shopName || 'My Business Store',
      direction: 'OUTBOUND_CUSTOMER',
      customerName,
      customerPhone: customerPhone || '',
      courierName: courierName || 'General Courier',
      courierOtp,
      courierOtpExpiresAt,
      mode: 'pick_up',
      status: 'awaiting_pickup'
    });

    const io = req.app.get('io');
    if (io) {
      io.to(userId).emit('trackingUpdate', newTracking);
      io.to('esp32_device').emit('registerTracking', { trackingId, mode: 'pick_up' });
      console.log(`[SOCKET] Outbound tracking staged: ${trackingId} for user ${userId}`);
    }

    res.status(201).json({
      success: true,
      message: 'Outbound package staged successfully',
      data: newTracking
    });
  } catch (err) {
    console.error('❌ stageOutboundPackage error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * POST /api/business/generate-dispatch-link
 * Returns customer dispatch share text
 */
exports.generateDispatchLink = async (req, res) => {
  try {
    const { trackingId } = req.body;
    const tracking = await Tracking.findOne({ trackingId });

    if (!tracking) {
      return res.status(404).json({ success: false, message: 'Tracking not found' });
    }

    const shop = tracking.shopName || 'Our Shop';
    const customer = tracking.customerName || 'Valued Customer';
    const courier = tracking.courierName || 'Courier';

    const text = `Hi ${customer}! Your order has been securely staged at our Smart Parcel Dropbox for pickup via ${courier}.\n\nTracking ID: ${tracking.trackingId}\nStatus: ${tracking.status.toUpperCase()}\n\nThank you for shopping with ${shop}! 📦✨`;
    
    res.json({
      success: true,
      data: {
        text,
        shareText: text
      }
    });
  } catch (err) {
    console.error('❌ generateDispatchLink error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * POST /api/business/batch-outbound-staging
 * Stage multiple packages in a single in-app action and option to trigger box unlock
 */
exports.batchStageOutboundPackages = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const { packages, shopName, openDoor } = req.body;

    if (!Array.isArray(packages) || packages.length === 0) {
      return res.status(400).json({ success: false, message: 'packages array is required and must not be empty' });
    }

    const createdList = [];

    for (const pkg of packages) {
      if (!pkg.trackingId) continue;

      // Upsert/Overwrite if existing
      await Tracking.deleteOne({ trackingId: pkg.trackingId });

      const courierOtp = Math.floor(100000 + Math.random() * 900000).toString();
      const courierOtpExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);

      const created = await Tracking.create({
        trackingId: pkg.trackingId,
        userId,
        shopName: shopName || 'My Business Store',
        direction: 'OUTBOUND_CUSTOMER',
        customerName: pkg.customerName || 'Valued Customer',
        customerPhone: pkg.customerPhone || '',
        courierName: pkg.courierName || 'General Courier',
        courierOtp,
        courierOtpExpiresAt,
        mode: 'pick_up',
        status: 'awaiting_pickup'
      });

      createdList.push(created);
    }

    // Increment dropbox pickup count for logical state
    let dbQuery = { userIds: userId };
    let dropbox = await Dropbox.findOne(dbQuery);
    if (!dropbox) dbQuery = { userId };
    await Dropbox.updateOne(dbQuery, { $inc: { pickupCount: createdList.length } });

    // Emit socket notifications and optional box unlock
    const io = req.app.get('io');
    if (io) {
      for (const pkg of createdList) {
        io.to(userId).emit('trackingUpdate', pkg);
        io.to('esp32_device').emit('registerTracking', { trackingId: pkg.trackingId, mode: 'pick_up' });
      }
      if (openDoor) {
        console.log(`🚪 Batch Outbound Staging → Unlocking Dropbox door for ${userId}`);
        io.to('esp32_device').emit('controlDoor', { type: 'pickup', action: 'open' });
      }
    }

    res.status(201).json({
      success: true,
      message: `Successfully staged ${createdList.length} packages in batch`,
      count: createdList.length,
      data: createdList
    });
  } catch (err) {
    console.error('❌ batchStageOutboundPackages error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};
