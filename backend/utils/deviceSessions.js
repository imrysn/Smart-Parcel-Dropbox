const { createHmac, randomBytes, randomUUID, timingSafeEqual } = require('node:crypto');
const Dropbox = require('../models/Dropbox');

const pendingCommands = new Map();
const doorStates = new Map();
const doorTypes = { top: 'parcelDoorOpen', pickup: 'pickupDoorOpen', received: 'receivedDoorOpen' };

const normalizeDeviceId = (value) => typeof value === 'string' ? value.trim().toUpperCase() : '';
const deviceRoom = (deviceId) => `device:${normalizeDeviceId(deviceId)}`;

function deviceKey(deviceId) {
  try {
    const keys = JSON.parse(process.env.SPD_DEVICE_KEYS || '{}');
    const id = normalizeDeviceId(deviceId);
    if (!id || !keys || typeof keys !== 'object') return null;
    const key = Object.entries(keys).find(([name]) => normalizeDeviceId(name) === id)?.[1];
    if (typeof key !== 'string' || key.length < 32) return null;
    return Object.values(keys).filter(value => value === key).length === 1 ? key : null;
  } catch {
    return null;
  }
}

function sameSecret(expected, supplied) {
  if (typeof supplied !== 'string' || typeof expected !== 'string') return false;
  const left = Buffer.from(expected);
  const right = Buffer.from(supplied);
  return left.length === right.length && timingSafeEqual(left, right);
}

function verifyDeviceProof(deviceId, nonce, proof) {
  const key = deviceKey(deviceId);
  if (!key || !nonce) return false;
  const expected = createHmac('sha256', key).update(`${normalizeDeviceId(deviceId)}:${nonce}`).digest('hex');
  return sameSecret(expected, proof);
}

function offlineClockChallenge(deviceId, nonce, now = Date.now()) {
  if (typeof nonce !== 'string' || !/^[a-f0-9]{32}$/.test(nonce)) return null;
  const key = deviceKey(deviceId);
  if (!key) return null;
  const seconds = Math.floor(now / 1000);
  const proof = createHmac('sha256', key)
    .update(`SPD-BLE-CLOCK-V1|${normalizeDeviceId(deviceId)}|${nonce}|${seconds}`).digest('hex');
  return { seconds, proof };
}

function issueOfflineUnlockGrant(deviceId, now = Date.now()) {
  const key = deviceKey(deviceId);
  if (!key) return null;
  const id = normalizeDeviceId(deviceId);
  const grantId = randomBytes(16).toString('hex');
  const expiresAt = Math.floor(now / 1000) + 8 * 60 * 60;
  const secret = createHmac('sha256', key)
    .update(`SPD-BLE-GRANT-V1|${id}|${grantId}|${expiresAt}`).digest('hex');
  return { deviceId: id, grantId, expiresAt, secret };
}

function canIssueOfflineUnlockGrant(io, deviceId) {
  const sockets = io?.sockets;
  const room = sockets?.adapter.rooms.get(deviceRoom(deviceId));
  return [...(room || [])].some(id => sockets.sockets.get(id)?.offlineClockReady === true);
}

function authenticateDeviceHttp(req, res, next) {
  const id = normalizeDeviceId(req.get('X-SPD-Device-ID'));
  const key = deviceKey(id);
  if (!key || !sameSecret(`Device ${key}`, req.get('Authorization'))) {
    return res.status(401).json({ message: 'Device authentication required' });
  }
  const target = req.params.deviceId ?? req.body?.deviceId ?? req.query.deviceId;
  if (normalizeDeviceId(target) !== id) {
    return res.status(403).json({ message: 'Device identity does not match request' });
  }
  req.deviceId = id;
  if (req.params.deviceId) req.params.deviceId = id;
  if (req.body?.deviceId) req.body.deviceId = id;
  if (req.query.deviceId) req.query.deviceId = id;
  next();
}

function membersOf(box) {
  return [...new Set([...(box?.userIds || []), box?.primaryUserId, box?.userId].filter(Boolean).map(String))];
}

function pairedBoxForUser(userId) {
  if (!userId) return null;
  return Dropbox.findOne({ isRegistered: true, $or: [{ userIds: userId }, { primaryUserId: userId }, { userId }] });
}

function registeredBoxForDevice(deviceId) {
  if (!deviceId) return null;
  return Dropbox.findOne({ deviceId: normalizeDeviceId(deviceId), isRegistered: true });
}

function emitToMembers(io, box, event, data) {
  if (!io || !box) return;
  for (const userId of membersOf(box)) io.to(userId).emit(event, { ...data, deviceId: box.deviceId });
}

function isDeviceOnline(io, deviceId) {
  return Boolean(deviceId && io?.sockets.adapter.rooms.get(deviceRoom(deviceId))?.size);
}

function recordDoorState(deviceId, data) {
  const state = { deviceId: normalizeDeviceId(deviceId), status: 'idle' };
  for (const field of [...Object.values(doorTypes), 'parcelDetected', 'parcelInDropOff', 'parcelInPickup',
    'REED_TOP', 'REED_PICKUP', 'REED_RECEIVED']) {
    if (typeof data?.[field] === 'boolean') state[field] = data[field];
  }
  if (!Object.values(doorTypes).every(field => typeof state[field] === 'boolean')) return null;
  state.userDoorOpen = state.pickupDoorOpen;
  doorStates.set(state.deviceId, state);
  return state;
}

function getDoorState(deviceId) {
  return doorStates.get(normalizeDeviceId(deviceId));
}

function settle(deviceId, result) {
  const pending = pendingCommands.get(deviceId);
  if (!pending) return;
  clearTimeout(pending.timer);
  pendingCommands.delete(deviceId);
  pending.resolve(result);
}

function commandDoor(io, id, type, action, timeoutMs = 6500) {
  const deviceId = normalizeDeviceId(id);
  if (!Object.hasOwn(doorTypes, type) || !['open', 'close'].includes(action)) {
    return Promise.resolve({ ok: false, reason: 'invalid_command' });
  }
  if (!isDeviceOnline(io, deviceId)) return Promise.resolve({ ok: false, reason: 'device_offline' });
  if (pendingCommands.has(deviceId)) return Promise.resolve({ ok: false, reason: 'command_pending' });
  return new Promise(resolve => {
    const requestId = randomUUID();
    const timer = setTimeout(() => settle(deviceId, { ok: false, reason: 'confirmation_timeout' }), timeoutMs);
    pendingCommands.set(deviceId, { requestId, type, action, resolve, timer });
    io.to(deviceRoom(deviceId)).emit('controlDoor', { type, action, requestId });
  });
}

function confirmDoorCommand(deviceId, payload, state) {
  const pending = pendingCommands.get(deviceId);
  if (!pending || pending.requestId !== payload?.requestId) return;
  const field = doorTypes[pending.type];
  if (payload.ok === true && state?.[field] === (pending.action === 'open')) {
    settle(deviceId, { ok: true, doorState: state });
  } else {
    settle(deviceId, { ok: false, reason: 'device_rejected', doorState: state });
  }
}

function deviceDisconnected(id) {
  const deviceId = normalizeDeviceId(id);
  doorStates.delete(deviceId);
  settle(deviceId, { ok: false, reason: 'device_offline' });
}

module.exports = {
  authenticateDeviceHttp, verifyDeviceProof, normalizeDeviceId, deviceRoom,
  offlineClockChallenge, issueOfflineUnlockGrant, canIssueOfflineUnlockGrant,
  membersOf, pairedBoxForUser, registeredBoxForDevice, emitToMembers, isDeviceOnline,
  recordDoorState, getDoorState, commandDoor, confirmDoorCommand, deviceDisconnected,
};
