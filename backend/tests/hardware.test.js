const test = require('node:test');
const assert = require('node:assert/strict');
const { initToken, pendingRegistrations, verifyBarcode } = require('../controllers/hardwareController');
const Dropbox = require('../models/Dropbox');
const Tracking = require('../models/Tracking');
const ScanLog = require('../models/ScanLog');

test('Hardware Controller Logic Unit Tests', async (t) => {
  await t.test('initToken should reject missing deviceId', async () => {
    let statusCode = null;
    let body = null;
    const req = { query: {} };
    const res = {
      status: (code) => { statusCode = code; return res; },
      json: (data) => { body = data; return res; }
    };

    await initToken(req, res);
    assert.equal(statusCode, 400);
    assert.equal(body.message, 'deviceId parameter is required');
  });

  await t.test('initToken should generate a valid 6-character SPDB- token', async () => {
    let statusCode = null;
    let body = null;
    const req = { query: { deviceId: 'ESP32_TEST_MAC_001' } };
    const res = {
      status: (code) => { statusCode = code; return res; },
      json: (data) => { body = data; return res; }
    };

    await initToken(req, res);
    assert.equal(body.success, true);
    assert.ok(body.token.startsWith('SPDB-'));
    assert.equal(body.token.length, 11); // 'SPDB-' + 6 chars
    assert.ok(pendingRegistrations.has(body.token));
  });
});

test('an inbound barcode scan authorizes entry without completing a delivery', async (t) => {
  const deviceId = 'BOX-A';
  const userId = 'owner-a';
  const tracking = new Tracking({ trackingId: 'PARCEL-123', userId, mode: 'drop_off', status: 'pending' });
  const save = t.mock.method(tracking, 'save', async () => tracking);
  const log = t.mock.method(ScanLog, 'create', async (entry) => {
    assert.equal(new ScanLog(entry).validateSync(), undefined);
  });
  t.mock.method(Dropbox, 'findOne', async (filter) => {
    assert.deepEqual(filter, { deviceId, isRegistered: true });
    return { primaryUserId: userId, userIds: [] };
  });
  t.mock.method(Tracking, 'findOne', async (query) => {
    assert.deepEqual(query.userId, { $in: [userId] });
    return query.trackingId.$regex.test(tracking.trackingId) ? tracking : null;
  });
  const emit = t.mock.fn();
  const app = { get: () => ({ to: () => ({ emit }) }) };

  async function scan(barcode = tracking.trackingId) {
    let status = 200;
    let body;
    const res = {
      status(code) { status = code; return this; },
      json(value) { body = value; return this; },
    };
    await verifyBarcode({ body: { deviceId, barcode }, app }, res);
    return { status, body };
  }

  for (let attempt = 0; attempt < 2; attempt++) {
    const response = await scan();
    assert.equal(response.status, 200);
    assert.equal(response.body.allowed, true);
    assert.equal(response.body.action, 'open_door');
  }
  assert.equal(tracking.status, 'pending');
  assert.equal(tracking.deliveredAt, undefined);
  assert.equal(save.mock.callCount(), 0);
  assert.equal(emit.mock.callCount(), 0);
  assert.equal(log.mock.calls[0].arguments[0].status, 'authorized');

  tracking.mode = 'pick_up';
  assert.equal((await scan()).body.allowed, false);
  tracking.mode = 'drop_off';
  tracking.status = 'delivered';
  assert.equal((await scan()).body.allowed, false);
  assert.equal((await scan('UNREGISTERED')).status, 404);
});
