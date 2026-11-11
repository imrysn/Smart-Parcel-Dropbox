const { applicationDefault, initializeApp } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');
const Notification = require('../models/Notification');
const PushInstallation = require('../models/PushInstallation');

const enabled = () => process.env.SPD_PUSH_ENABLED === 'true';
const ttlMs = 24 * 60 * 60 * 1000;
const retryMs = 2 * 60 * 1000;
const invalidTokens = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

let messaging;

function deliveryMessage(event, token, now) {
  const id = String(event._id);
  return {
    token,
    notification: { title: 'Parcel delivered', body: 'Open Smart Parcel Dropbox for details.' },
    data: { type: 'parcel_delivered', notificationId: id },
    android: {
      priority: 'high',
      ttl: Math.max(0, event.timestamp.getTime() + ttlMs - now.getTime()),
      notification: { channelId: 'parcel_updates', tag: id, visibility: 'private' },
    },
  };
}

async function sendDelivery(event, now, send) {
  const installations = await PushInstallation.find({
    userId: event.userId, expiresAt: { $gt: now }, _id: { $nin: event.pushSentInstallations || [] },
  });
  const results = await Promise.allSettled(installations.map(async installation => {
    const { _id, token } = installation;
    const binding = { _id, token, userId: event.userId, expiresAt: { $gt: new Date() } };
    if (!await PushInstallation.exists(binding)) return;
    try {
      await send(deliveryMessage(event, token, now));
      return _id;
    } catch (error) {
      if (!invalidTokens.has(error.code)) throw error;
      await PushInstallation.deleteOne({ _id, token, userId: event.userId });
    }
  }));
  return {
    retry: results.some(result => result.status === 'rejected'),
    sent: results.flatMap(result => result.status === 'fulfilled' && result.value ? [result.value] : []),
  };
}

async function drainDeliveryPush() {
  messaging ??= getMessaging(initializeApp({ credential: applicationDefault() }, 'spd-delivery'));
  // Claim a bounded batch so multiple workers can safely share the queue.
  for (let index = 0; index < 20; index++) {
    const now = new Date();
    const lease = new Date(now.getTime() + retryMs);
    const event = await Notification.findOneAndUpdate({
      pushDueAt: { $lte: now },
      timestamp: { $gt: new Date(now.getTime() - ttlMs) },
    }, { $set: { pushDueAt: lease } }, { sort: { pushDueAt: 1 } }).select('+pushSentInstallations');
    if (!event) break;
    const { retry, sent } = await sendDelivery(event, now, message => messaging.send(message));
    const claim = { _id: event._id, pushDueAt: lease };
    if (!retry) {
      await Notification.updateOne(claim, { $unset: { pushDueAt: 1, pushSentInstallations: 1 } });
    } else if (sent.length) {
      await Notification.updateOne(claim, { $addToSet: { pushSentInstallations: { $each: sent } } });
    }
  }
}

function startDeliveryPush() {
  if (!enabled()) return;
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try {
      await drainDeliveryPush();
    } catch (error) {
      console.error('Delivery push worker failed:', error.code || error.name);
    } finally {
      running = false;
    }
  };
  setInterval(tick, 5000).unref();
  void tick();
}

module.exports = { enabled, sendDelivery, startDeliveryPush };
