const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { once } = require('node:events');
const Notification = require('../models/Notification');
const Tracking = require('../models/Tracking');
const PushInstallation = require('../models/PushInstallation');
const notificationRoutes = require('../routes/notificationRoutes');
const { generateToken } = require('../utils/auth');
const { sendDelivery } = require('../utils/deliveryPush');

test('delivery push sends only to current installations and drops invalid tokens', async t => {
  const event = {
    _id: 'abc', userId: 'owner', trackingId: 'PRIVATE-TRACKING-ID', timestamp: new Date(),
    pushSentInstallations: ['already-sent'],
  };
  t.mock.method(PushInstallation, 'find', async filter => {
    assert.equal(filter.userId, 'owner');
    assert.deepEqual(filter._id.$nin, ['already-sent']);
    return [
      { _id: 'working', token: 'working-token' },
      { _id: 'invalid', token: 'invalid-token' },
      { _id: 'reassigned', token: 'reassigned-token' },
    ];
  });
  t.mock.method(PushInstallation, 'exists', async filter => {
    assert.equal(filter.userId, 'owner');
    return filter._id !== 'reassigned';
  });
  const remove = t.mock.method(PushInstallation, 'deleteOne', async () => ({}));
  const sent = [];
  const result = await sendDelivery(event, new Date(), async message => {
    sent.push(message);
    if (message.token === 'invalid-token') {
      throw Object.assign(new Error('Token expired'), { code: 'messaging/registration-token-not-registered' });
    }
  });
  assert.deepEqual(result, { retry: false, sent: ['working'] });
  assert.deepEqual(sent.map(message => message.token), ['working-token', 'invalid-token']);
  for (const message of sent) {
    assert.deepEqual(message.data, { type: 'parcel_delivered', notificationId: 'abc' });
    assert.equal(message.android.notification.tag, 'abc');
    assert.equal(JSON.stringify(message).includes(event.trackingId), false);
  }
  assert.deepEqual(remove.mock.calls[0].arguments[0], {
    _id: 'invalid', token: 'invalid-token', userId: 'owner',
  });
});

test('opening a delivery alert requires the parcel owner session', async t => {
  const previousSecret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = 'test-delivery-push-signing-key-with-at-least-32-characters';
  t.after(() => {
    if (previousSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = previousSecret;
  });
  const eventId = '6a55135295cb6702ab991309';
  t.mock.method(Notification, 'findOne', async filter => {
    assert.equal(filter._id, eventId);
    return filter.userId === 'owner' ? { trackingId: 'SPD-DEMO' } : null;
  });
  t.mock.method(Tracking, 'findOne', async filter => ({ ...filter }));
  const app = express();
  app.use('/notifications', notificationRoutes);
  const server = app.listen(0, '127.0.0.1');
  t.after(() => new Promise(resolve => server.close(resolve)));
  await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}/notifications/${eventId}/parcel`;
  assert.equal((await fetch(url)).status, 401);
  const fetchParcel = userId => fetch(url, { headers: { authorization: `Bearer ${generateToken(userId)}` } });
  assert.equal((await fetchParcel('other')).status, 404);
  const response = await fetchParcel('owner');
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { trackingId: 'SPD-DEMO', userId: 'owner' });
});
