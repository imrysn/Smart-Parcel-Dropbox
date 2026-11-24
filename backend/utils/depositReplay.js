const mongoose = require('mongoose');
const DeliveryReceipt = require('../models/DeliveryReceipt');
const Dropbox = require('../models/Dropbox');
const Notification = require('../models/Notification');
const Tracking = require('../models/Tracking');
const { membersOf, emitToMembers } = require('./deviceSessions');
const deliveryPush = require('./deliveryPush');

const writeOptions = { writeConcern: { w: 'majority', j: true } };
const eligibleStatus = { $in: ['pending', 'in_transit'] };
const batchKey = /^[A-Za-z0-9_-]{1,48}$/;

async function saveDelivery(session, box, tracking, deliveredAt, receivedAt) {
  const updatedBox = await Dropbox.findOneAndUpdate(
    { _id: box._id, isRegistered: true }, { $inc: { dropoffCount: 1 } }, { session, new: true },
  );
  if (!updatedBox) throw new Error('Dropbox registration changed during deposit replay');
  const [notification] = await Notification.create([{
    userId: tracking.userId,
    trackingId: tracking.trackingId,
    title: 'Parcel Delivered',
    message: `Tracking ID ${tracking.trackingId} status changed to delivered.`,
    type: 'parcel_delivered',
    timestamp: deliveredAt,
    ...(deliveryPush.enabled() ? { pushDueAt: receivedAt } : {}),
  }], { session });
  return { tracking, box: updatedBox, notification };
}

async function recordConfirmedDeposit(deviceId, event, batch = false) {
  if (!deviceId) return { ack: { ok: false, reason: 'device_required' } };

  const { eventId, trackingRecordId, occurredAt, batchId, needsReview } = event ?? {};
  const receivedAt = new Date();
  const eventTime = typeof occurredAt === 'string' ? new Date(occurredAt) : null;
  if (typeof eventId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(eventId) ||
      typeof trackingRecordId !== 'string' || !/^[a-f0-9]{24}$/.test(trackingRecordId) ||
      (batch && (typeof batchId !== 'string' || !batchKey.test(batchId) || typeof needsReview !== 'boolean')) ||
      (occurredAt !== undefined && (!eventTime || !Number.isFinite(eventTime.getTime()) ||
        eventTime.toISOString() !== occurredAt || eventTime > receivedAt))) {
    return { ack: { ok: false, reason: 'invalid_event' } };
  }

  const receiptId = `${deviceId}:${eventId}`;
  const deliveredAt = eventTime ?? receivedAt;
  const rejected = reason => ({ ack: { ok: false, eventId, reason } });
  let result;

  // The driver can retry the callback. Publish only the result of the committed attempt.
  await mongoose.connection.transaction(async session => {
    const box = await Dropbox.findOne({ deviceId, isRegistered: true }).session(session);
    if (!box) {
      result = rejected('device_unregistered');
      return;
    }

    const receipt = await DeliveryReceipt.findById(receiptId).session(session).lean();
    if (receipt) {
      const matches = String(receipt.trackingRecordId) === trackingRecordId &&
        receipt.occurredAt?.getTime() === eventTime?.getTime() &&
        (receipt.batchId ?? null) === (batch ? batchId : null) &&
        Boolean(receipt.needsReview) === (batch && needsReview);
      result = matches
        ? { ack: { ok: true, eventId, duplicate: true,
          ...(receipt.notificationId && { notificationId: String(receipt.notificationId) }) } }
        : rejected('event_conflict');
      return;
    }

    const review = batch && needsReview;
    const tracking = await Tracking.findOneAndUpdate({
      _id: trackingRecordId,
      userId: { $in: membersOf(box) },
      mode: 'drop_off',
      status: eligibleStatus,
      pendingDropoffReviewId: { $exists: false },
    }, { $set: review ? { pendingDropoffReviewId: receiptId } : { status: 'delivered', deliveredAt } },
    { session, new: true });
    if (!tracking) {
      result = rejected('tracking_ineligible');
      return;
    }

    const delivery = review ? null : await saveDelivery(session, box, tracking, deliveredAt, receivedAt);
    const notificationId = delivery ? String(delivery.notification._id) : undefined;

    await DeliveryReceipt.create([{
      _id: receiptId,
      trackingRecordId,
      notificationId,
      occurredAt: eventTime,
      receivedAt,
      ...(batch && { batchId, deviceId, userId: tracking.userId, trackingId: tracking.trackingId, needsReview }),
    }], { session });

    result = {
      ack: { ok: true, eventId, duplicate: false, ...(notificationId && { notificationId }) },
      delivery,
    };
  }, writeOptions);

  return result;
}

async function confirmDropoffReview(deviceId, userId, receiptId, barcode) {
  let result;
  await mongoose.connection.transaction(async session => {
    result = { status: 404, message: 'Drop-off review not found.' };
    const box = await Dropbox.findOne({ deviceId, isRegistered: true }).session(session);
    if (!membersOf(box).includes(userId)) return;
    const review = await DeliveryReceipt.findOne({ _id: receiptId, deviceId, userId, needsReview: true }).session(session);
    if (!review) return;
    const scanned = typeof barcode === 'string' ? barcode.trim().toUpperCase() : '';
    const expected = review.trackingId.toUpperCase();
    const matches = scanned === expected || scanned + 'T' === expected || scanned === expected + 'T';
    if (!scanned || !matches) {
      result = { status: 400, message: 'Scan the waybill for this parcel.' };
      return;
    }
    if (review.reviewedAt) {
      result = { status: 200 };
      return;
    }
    const now = new Date();
    const deliveredAt = review.occurredAt ?? now;
    const tracking = await Tracking.findOneAndUpdate({
      _id: review.trackingRecordId,
      userId,
      mode: 'drop_off',
      status: eligibleStatus,
      pendingDropoffReviewId: review._id,
    }, { $set: { status: 'delivered', deliveredAt }, $unset: { pendingDropoffReviewId: '' } },
    { session, new: true });
    if (!tracking) {
      result = { status: 409, message: 'This parcel is no longer awaiting review.' };
      return;
    }
    const delivery = await saveDelivery(session, box, tracking, deliveredAt, now);
    await DeliveryReceipt.updateOne({ _id: review._id }, {
      $set: { reviewedAt: now, notificationId: delivery.notification._id },
    }, { session });
    result = { status: 200, delivery };
  }, writeOptions);
  return result;
}

function publishDelivery(io, delivery) {
  if (!io || !delivery) return;
  const { tracking, box, notification } = delivery;
  const { pushDueAt, ...visibleNotification } = notification.toJSON();
  const room = io.to(tracking.userId);
  room.emit('notificationNew', visibleNotification);
  room.emit('trackingStatusChanged', {
    trackingId: tracking.trackingId, status: 'delivered', mode: 'drop_off',
    deviceId: box.deviceId, timestamp: tracking.deliveredAt,
    notificationId: String(notification._id), pushQueued: !!pushDueAt,
  });
  emitToMembers(io, box, 'binStatusUpdate', {
    logicalDropoffCount: box.dropoffCount, logicalPickupCount: box.pickupCount,
  });
}

module.exports = { recordConfirmedDeposit, confirmDropoffReview, publishDelivery };
