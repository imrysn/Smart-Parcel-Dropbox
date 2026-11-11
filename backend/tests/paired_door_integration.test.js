const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { once } = require('node:events');
const { createHmac, randomBytes } = require('node:crypto');
const Dropbox = require('../models/Dropbox');
const Notification = require('../models/Notification');
const Tracking = require('../models/Tracking');
const { generateToken } = require('../utils/auth');
const connect = require(path.join(path.dirname(require.resolve('socket.io')), '../client-dist/socket.io.js'));

test('paired phones receive only their box heartbeat, lock result, and delivery', {
  timeout: 10000,
  skip: typeof WebSocket !== 'function' && 'This integration check requires Node with a WebSocket client',
}, async t => {
  const keyA = randomBytes(32).toString('hex');
  const keyB = randomBytes(32).toString('hex');
  process.env.SPD_DEVICE_KEYS = JSON.stringify({ 'BOX-A': keyA, 'BOX-B': keyB });
  process.env.JWT_SECRET = randomBytes(32).toString('hex');
  const pushSetting = process.env.SPD_PUSH_ENABLED;
  process.env.SPD_PUSH_ENABLED = 'true';
  const boxes = [
    { _id: 'a', deviceId: 'BOX-A', userIds: ['owner-a'], primaryUserId: 'owner-a' },
    { _id: 'b', deviceId: 'BOX-B', userIds: ['owner-b'], primaryUserId: 'owner-b' },
  ];
  t.mock.method(Dropbox, 'findOne', async query => boxes.find(box => query.deviceId
    ? box.deviceId === query.deviceId : box.userIds.includes(query.$or?.[0]?.userIds)));
  t.mock.method(Dropbox, 'updateOne', async () => ({ modifiedCount: 1 }));
  t.mock.method(Dropbox, 'findById', async id => boxes.find(box => box._id === id));
  const storeTelemetry = t.mock.method(Dropbox, 'findOneAndUpdate', async (query, update) => {
    const box = boxes.find(item => item.deviceId === query.deviceId);
    return box && Object.assign(box, update.$set);
  });
  const parcel = { _id: 'parcel-a', trackingId: 'SPD-DEMO', userId: 'owner-a', status: 'pending', mode: 'drop_off' };
  t.mock.method(Tracking, 'findOne', async filter => filter.userId.$in.includes(parcel.userId) && parcel);
  t.mock.method(Tracking, 'updateOne', async (_filter, update) => {
    Object.assign(parcel, update.$set);
    return { modifiedCount: 1 };
  });
  const storeDelivery = t.mock.method(Notification, 'create', async data => new Notification(data));

  const { server, io } = require('../server');
  const peers = [];
  t.after(async () => {
    for (const peer of peers) peer.disconnect();
    await new Promise(resolve => io.close(resolve));
    delete process.env.SPD_DEVICE_KEYS;
    delete process.env.JWT_SECRET;
    if (pushSetting === undefined) delete process.env.SPD_PUSH_ENABLED;
    else process.env.SPD_PUSH_ENABLED = pushSetting;
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}`;

  async function connectDevice(deviceId, key) {
    const socket = connect(url, {
      transports: ['websocket'], autoConnect: false, reconnection: false, forceNew: true,
      query: { clientType: 'hardware' },
    });
    peers.push(socket);
    socket.on('deviceChallenge', ({ nonce }) => {
      const proof = createHmac('sha256', key).update(`${deviceId}:${nonce}`).digest('hex');
      socket.emit('authenticateDevice', { deviceId, proof });
    });
    const ready = new Promise((resolve, reject) => {
      socket.once('deviceAuthenticated', resolve);
      socket.once('connect_error', reject);
    });
    socket.connect();
    await ready;
    return socket;
  }

  const boxA = await connectDevice('BOX-A', keyA);
  const boxB = await connectDevice('BOX-B', keyB);
  function connectPhone(userId) {
    const socket = connect(url, {
      auth: { token: generateToken(userId) }, transports: ['websocket'], reconnection: false, forceNew: true,
    });
    peers.push(socket);
    return socket;
  }
  const phoneA = connectPhone('owner-a');
  const phoneB = connectPhone('owner-b');
  await Promise.all([once(phoneA, 'connect'), once(phoneB, 'connect')]);
  let unrelatedReports = 0;
  phoneB.on('esp32Status', data => { if (data.diagnostics) unrelatedReports++; });
  const heartbeat = { firmwareVersion: '1.0.0-test', wifiRssi: -63, uptimeSeconds: 120 };
  phoneA.emit('deviceHeartbeat', heartbeat);
  const report = new Promise(resolve => {
    phoneA.on('esp32Status', data => { if (data.diagnostics) resolve(data); });
  });
  boxA.emit('deviceHeartbeat', { ...heartbeat, deviceId: 'BOX-B' });
  const reportA = await report;
  assert.equal(reportA.deviceId, 'BOX-A');
  assert.equal(reportA.diagnostics.wifiRssi, heartbeat.wifiRssi);

  let unrelatedVolumeReports = 0;
  phoneB.on('spatialVolumeHUD', () => unrelatedVolumeReports++);
  const volume = once(phoneA, 'spatialVolumeHUD');
  boxA.emit('spatialVolumeUpdate', { deviceId: 'BOX-B', occupancyPercent: 61.7, rawDistance: 16.2 });
  const [volumeA] = await volume;
  assert.deepEqual(volumeA, { deviceId: 'BOX-A', occupancyPercent: 61.7, fillPercentage: 62, rawDistance: 16.2 });

  let unrelatedDeliveries = 0;
  phoneB.on('trackingStatusChanged', () => unrelatedDeliveries++);
  const delivery = once(phoneA, 'trackingStatusChanged');
  boxA.emit('statusUpdate', { trackingId: parcel.trackingId, status: 'delivered', mode: 'drop_off' });
  const [event] = await delivery;
  assert.equal(event.pushQueued, true);
  assert.match(event.notificationId, /^[a-f0-9]{24}$/);
  assert.equal(storeDelivery.mock.calls[0].arguments[0].userId, 'owner-a');
  assert.ok(storeDelivery.mock.calls[0].arguments[0].pushDueAt instanceof Date);
  let commandsB = 0;
  boxB.on('controlDoor', () => commandsB++);
  boxA.on('controlDoor', ({ requestId }) => {
    boxA.emit('doorCommandResult', {
      requestId, ok: true,
      doorState: { parcelDoorOpen: false, pickupDoorOpen: true, receivedDoorOpen: false },
    });
  });

  const response = await fetch(`${url}/device-control`, {
    method: 'POST',
    headers: { authorization: `Bearer ${generateToken('owner-a')}`, 'content-type': 'application/json' },
    body: JSON.stringify({ doorType: 'pickup', command: 'open', deviceId: 'BOX-A' }),
  });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.doorState.deviceId, 'BOX-A');
  assert.equal(result.doorState.pickupDoorOpen, true);
  assert.equal(commandsB, 0);
  assert.equal(unrelatedReports, 0);
  assert.equal(unrelatedDeliveries, 0);
  assert.equal(unrelatedVolumeReports, 0);
  assert.equal(storeTelemetry.mock.callCount(), 2);
});
