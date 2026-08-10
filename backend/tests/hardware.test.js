const test = require('node:test');
const assert = require('node:assert/strict');
const { initToken, pendingRegistrations } = require('../controllers/hardwareController');

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
