const test = require('node:test');
const assert = require('node:assert/strict');
const { createHmac, randomBytes } = require('node:crypto');
const {
  verifyDeviceProof, deviceRoom, commandDoor, confirmDoorCommand,
  recordDoorState, getDoorState, deviceDisconnected, emitToMembers,
} = require('../utils/deviceSessions');

test('device credentials are bound to the configured device and challenge', () => {
  const keyA = randomBytes(32).toString('hex');
  const keyB = randomBytes(32).toString('hex');
  process.env.SPD_DEVICE_KEYS = JSON.stringify({ 'BOX-A': keyA, 'BOX-B': keyB });
  const nonce = randomBytes(24).toString('hex');
  const proof = createHmac('sha256', keyA).update(`BOX-A:${nonce}`).digest('hex');
  assert.equal(verifyDeviceProof('box-a', nonce, proof), true);
  assert.equal(verifyDeviceProof('BOX-B', nonce, proof), false);
  assert.equal(verifyDeviceProof('BOX-A', randomBytes(24).toString('hex'), proof), false);
  delete process.env.SPD_DEVICE_KEYS;
});

function transport(...deviceIds) {
  const emitted = [];
  const rooms = new Map(deviceIds.map(id => [deviceRoom(id), new Set([id])]));
  return {
    sockets: { adapter: { rooms } },
    emitted,
    to: room => ({ emit: (event, data) => emitted.push({ room, event, data }) }),
  };
}

test('door requests use the intended room and resolve with a matching device result', async () => {
  const io = transport('BOX-A', 'BOX-B');
  const pending = commandDoor(io, 'BOX-A', 'pickup', 'open', 100);
  assert.equal(io.emitted.length, 1);
  assert.equal(io.emitted[0].room, deviceRoom('BOX-A'));
  const { requestId } = io.emitted[0].data;
  const state = recordDoorState('BOX-A', { parcelDoorOpen: false, pickupDoorOpen: true, receivedDoorOpen: false });
  confirmDoorCommand('BOX-B', { requestId, ok: true }, state);
  assert.deepEqual(await commandDoor(io, 'BOX-A', 'pickup', 'close'), { ok: false, reason: 'command_pending' });
  confirmDoorCommand('BOX-A', { requestId, ok: true }, state);
  assert.deepEqual(await pending, { ok: true, doorState: state });
  deviceDisconnected('BOX-A');
  assert.equal(getDoorState('BOX-A'), undefined);
});

test('unavailable and unconfirmed commands do not report success', async () => {
  const io = transport('BOX-A');
  assert.deepEqual(await commandDoor(io, 'BOX-B', 'top', 'open'), { ok: false, reason: 'device_offline' });
  assert.deepEqual(await commandDoor(io, 'BOX-A', 'received', 'close', 10), { ok: false, reason: 'confirmation_timeout' });
});

test('sensor updates are emitted only to the paired household rooms', () => {
  const io = transport();
  emitToMembers(io, { deviceId: 'BOX-A', userIds: ['member'], primaryUserId: 'owner' }, 'binStatusUpdate', { logicalPickupCount: 1 });
  assert.deepEqual(io.emitted.map(entry => entry.room), ['member', 'owner']);
  assert.ok(io.emitted.every(entry => entry.data.deviceId === 'BOX-A'));
});
