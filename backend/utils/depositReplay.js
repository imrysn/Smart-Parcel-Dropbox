const mongoose = require('mongoose');
const DeliveryReceipt = require('../models/DeliveryReceipt');
const Dropbox = require('../models/Dropbox');
const Notification = require('../models/Notification');
const Tracking = require('../models/Tracking');
const { membersOf } = require('./deviceSessions');
const deliveryPush = require('./deliveryPush');

async function recordConfirmedDeposit(deviceId, event) {
  if (!deviceId) return { ack: { ok: false, reason: 'device_required' } };

  const { eventId, trackingRecordId, occurredAt } = event ?? {};
  const receivedAt = new Date();
  const eventTime = typeof occurredAt === 'string' ? new Date(occurredAt) : null;
  if (typeof eventId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(eventId) ||
      typeof trackingRecordId !== 'string' || !/^[a-f0-9]{24}$/.test(trackingRecordId) ||
      (occurredAt !== undefined && (!eventTime || !Number.isFinite(eventTime.getTime()) ||
        eventTime.toISOString() !== occurredAt || eventTime > receivedAt))) {
    return { ack: { ok: false, reason: 'invalid_event' } };
  }

  const receiptId = `${deviceId}:${eventId}`;
  const deliveredAt = eventTime ?? receivedAt;
  const pushEnabled = deliveryPush.enabled();
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
        receipt.occurredAt?.getTime() === eventTime?.getTime();
      result = matches
        ? { ack: { ok: true, eventId, duplicate: true, notificationId: String(receipt.notificationId) } }
        : rejected('event_conflict');
      return;
    }

    const tracking = await Tracking.findOneAndUpdate({
      _id: trackingRecordId,
      userId: { $in: membersOf(box) },
      mode: 'drop_off',
      status: { $in: ['pending', 'in_transit'] },
    }, { $set: { status: 'delivered', deliveredAt } }, { session, new: true });
    if (!tracking) {
      result = rejected('tracking_ineligible');
      return;
    }

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
      ...(pushEnabled ? { pushDueAt: receivedAt } : {}),
    }], { session });

    await DeliveryReceipt.create([{
      _id: receiptId,
      trackingRecordId,
      notificationId: notification._id,
      occurredAt: eventTime,
      receivedAt,
    }], { session });

    result = {
      ack: { ok: true, eventId, duplicate: false, notificationId: String(notification._id) },
      delivery: { tracking, box: updatedBox, notification },
    };
  }, { writeConcern: { w: 'majority', j: true } });

  return result;
}

module.exports = { recordConfirmedDeposit };
