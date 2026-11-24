const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { once } = require('node:events');
const { createHmac, randomBytes } = require('node:crypto');
const mongoose = require('mongoose');
const DeliveryReceipt = require('../models/DeliveryReceipt');
const Dropbox = require('../models/Dropbox');
const Notification = require('../models/Notification');
const Tracking = require('../models/Tracking');

const connect = require(path.join(path.dirname(require.resolve('socket.io')), '../client-dist/socket.io.js'));
const mongoUri = process.env.SPD_TEST_MONGO_URI;

test('confirmed deposit replay commits once and rolls back on failure', {
  timeout: 20000,
  skip: !mongoUri ? 'Set SPD_TEST_MONGO_URI to an isolated MongoDB replica set' : false,
}, async t => {
  const deviceId = 'BOX-REPLAY';
  const key = randomBytes(32).toString('hex');
  process.env.SPD_DEVICE_KEYS = JSON.stringify({ [deviceId]: key });
  process.env.JWT_SECRET = randomBytes(32).toString('hex');
  process.env.SPD_PUSH_ENABLED = 'false';
  const { server, io } = require('../server');
  const peers = [];
  t.after(async () => {
    for (const peer of peers) peer.disconnect();
    try {
      await new Promise(resolve => io.close(resolve));
      if (mongoose.connection.readyState === 1) await mongoose.connection.dropDatabase();
    } finally {
      await mongoose.disconnect();
    }
  });

  await mongoose.connect(mongoUri, {
    dbName: `spd_replay_test_${randomBytes(12).toString('hex')}`,
    serverSelectionTimeoutMS: 5000,
  });
  await Promise.all([Dropbox.init(), Tracking.init(), Notification.init(), DeliveryReceipt.init()]);
  const box = await Dropbox.create({ deviceId, primaryUserId: 'owner-a' });
  const parcel = await Tracking.create({ trackingId: 'SPD-DEPOSIT', userId: 'owner-a' });
  const other = await Tracking.create({ trackingId: 'SPD-OTHER', userId: 'owner-b' });
  const { generateToken } = require('../utils/auth');
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}`;
  const transport = { transports: ['websocket'], autoConnect: false, reconnection: false, forceNew: true };

  async function connectBox() {
    const peer = connect(url, { ...transport, query: { clientType: 'hardware' } });
    peers.push(peer);
    peer.on('deviceChallenge', ({ nonce }) => {
      const proof = createHmac('sha256', key).update(`${deviceId}:${nonce}`).digest('hex');
      peer.emit('authenticateDevice', { deviceId, proof });
    });
    const ready = once(peer, 'deviceAuthenticated');
    peer.connect();
    await ready;
    return peer;
  }

  const event = {
    eventId: 'delivery-1',
    trackingRecordId: String(parcel._id),
    occurredAt: new Date(Date.now() - 60000).toISOString(),
  };
  const phone = connect(url, { ...transport, auth: { token: generateToken('owner-a') } });
  peers.push(phone);
  const phoneConnected = once(phone, 'connect');
  phone.connect();
  await phoneConnected;
  const send = (peer, payload) => peer.timeout(3500).emitWithAck('confirmedDeposit', payload);
  assert.deepEqual(await send(phone, event), { ok: false, reason: 'device_required' });

  let hardware = await connectBox();
  assert.equal((await send(hardware, { ...event, trackingRecordId: String(other._id) })).reason, 'tracking_ineligible');

  // Fail after the parcel, count, and notification writes but before the receipt is saved.
  const failure = t.mock.method(DeliveryReceipt, 'create', async () => {
    throw new Error('Simulated receipt write failure');
  });
  assert.equal((await send(hardware, event)).reason, 'server_error');
  failure.mock.restore();
  assert.equal((await Tracking.findById(parcel._id)).status, 'pending');
  assert.equal((await Dropbox.findById(box._id)).dropoffCount, 0);
  assert.equal(await Notification.countDocuments(), 0);
  assert.equal(await DeliveryReceipt.countDocuments(), 0);

  const update = once(phone, 'trackingStatusChanged');
  const results = await Promise.all([send(hardware, event), send(hardware, event)]);
  const [live] = await update;
  assert.deepEqual(results.map(result => result.duplicate).sort(), [false, true]);
  assert.ok(results.every(result => result.ok && result.notificationId === live.notificationId));
  hardware.disconnect();
  hardware = await connectBox();
  assert.deepEqual(await send(hardware, event), {
    ok: true, eventId: event.eventId, duplicate: true, notificationId: live.notificationId,
  });
  assert.equal((await send(hardware, { ...event, trackingRecordId: String(other._id) })).reason, 'event_conflict');
  assert.equal((await send(hardware, { ...event, eventId: 'delivery-2' })).reason, 'tracking_ineligible');
  assert.equal((await Tracking.findById(parcel._id)).deliveredAt.toISOString(), event.occurredAt);
  assert.equal((await Dropbox.findById(box._id)).dropoffCount, 1);
  assert.equal(await Notification.countDocuments(), 1);
  assert.equal(await DeliveryReceipt.countDocuments(), 1);

  const missed = await Tracking.create({ trackingId: 'SPD-MISSED', userId: 'owner-a' });
  const detected = await Tracking.create({ trackingId: 'SPD-DETECTED', userId: 'owner-a' });
  const { Rider, ScanLog } = {
    Rider: require('../models/Rider'),
    ScanLog: require('../models/ScanLog'),
  };
  await Promise.all([Rider.init(), ScanLog.init()]);
  const authorize = barcode => hardware.timeout(3500).emitWithAck('verifyBatchScan', { barcode });
  assert.deepEqual(await authorize(missed.trackingId), { ok: true, trackingRecordId: String(missed._id) });
  assert.equal((await authorize('UNKNOWN-WAYBILL')).ok, false);
  const sendItem = payload => hardware.timeout(3500).emitWithAck('batchDropoffItem', payload);
  const missedItem = { batchId: 'batch-one', eventId: 'batch-one-0', trackingRecordId: String(missed._id), needsReview: true };
  const detectedItem = { batchId: 'batch-one', eventId: 'batch-one-1', trackingRecordId: String(detected._id), needsReview: false };
  assert.deepEqual(await sendItem(missedItem), { ok: true, eventId: missedItem.eventId, duplicate: false });
  assert.equal((await sendItem(missedItem)).duplicate, true);
  assert.equal((await authorize(missed.trackingId)).ok, false);
  assert.equal((await sendItem(detectedItem)).ok, true);
  assert.equal((await Tracking.findById(missed._id)).status, 'pending');
  assert.equal((await Dropbox.findById(box._id)).dropoffCount, 2);
  assert.equal(await Notification.countDocuments(), 2);

  const endpoint = `${url}/api/dropbox/${deviceId}`;
  const headers = userId => ({ authorization: `Bearer ${generateToken(userId)}`, 'content-type': 'application/json' });
  const list = await fetch(`${endpoint}/dropoff-batches`, { headers: headers('owner-a') });
  assert.equal(list.status, 200);
  const { items } = await list.json();
  assert.equal(items.length, 2);
  const review = items.find(item => item.needsReview);
  const confirm = (barcode, userId = 'owner-a') => fetch(
    `${endpoint}/dropoff-reviews/${encodeURIComponent(review._id)}/confirm`,
    { method: 'POST', headers: headers(userId), body: JSON.stringify({ barcode }) },
  );
  assert.equal((await confirm(missed.trackingId, 'owner-b')).status, 403);
  assert.equal((await confirm(detected.trackingId)).status, 400);
  assert.equal((await confirm(missed.trackingId)).status, 200);
  assert.equal((await confirm(missed.trackingId)).status, 200);
  assert.equal((await sendItem(missedItem)).duplicate, true);
  assert.equal((await Tracking.findById(missed._id)).status, 'delivered');
  assert.equal((await Dropbox.findById(box._id)).dropoffCount, 3);
  assert.equal(await Notification.countDocuments(), 3);
});
