const express = require('express');
const { authMiddleware } = require('../utils/auth');
const { pairedBoxForUser, getDoorState, isDeviceOnline, commandDoor } = require('../utils/deviceSessions');

const router = express.Router();
let io;
const doorTypes = { parcel: 'top', user: 'pickup', top: 'top', pickup: 'pickup', received: 'received' };
const failures = {
  invalid_command: [400, 'Invalid door or lock action'],
  device_offline: [503, 'The paired dropbox is offline'],
  command_pending: [409, 'The dropbox is processing another door command'],
  confirmation_timeout: [504, 'The dropbox did not confirm the command. Check its state before trying again.'],
  device_rejected: [409, 'The dropbox did not apply the requested lock state'],
};

function setSocketIO(socketIO) {
  io = socketIO;
}

router.post('/', authMiddleware, async (req, res) => {
  try {
    const box = await pairedBoxForUser(req.userId);
    if (!box || (req.body?.deviceId && req.body.deviceId !== box.deviceId)) {
      return res.status(403).json({ success: false, message: 'No access to the requested dropbox' });
    }
    const type = req.body?.doorType;
    const result = await commandDoor(io, box.deviceId, Object.hasOwn(doorTypes, type) ? doorTypes[type] : null, req.body?.command);
    if (!result.ok) {
      const [status, message] = failures[result.reason] || [500, 'Door control failed'];
      return res.status(status).json({ success: false, reason: result.reason, message, doorState: result.doorState });
    }
    res.json({ success: true, doorState: result.doorState });
  } catch (error) {
    console.error('Device control failed:', error.message);
    res.status(500).json({ success: false, message: 'Door control failed' });
  }
});

router.get('/', authMiddleware, async (req, res) => {
  try {
    const box = await pairedBoxForUser(req.userId);
    if (!box) return res.status(403).json({ success: false, message: 'No paired dropbox found' });
    const state = isDeviceOnline(io, box.deviceId) && getDoorState(box.deviceId);
    if (!state) return res.status(503).json({ success: false, message: 'No current lock state from the dropbox' });
    res.json(state);
  } catch (error) {
    console.error('Could not get door state:', error.message);
    res.status(500).json({ success: false, message: 'Could not get door state' });
  }
});

router.get('/health', authMiddleware, async (req, res) => {
  try {
    const box = await pairedBoxForUser(req.userId);
    res.json({ esp32Connected: isDeviceOnline(io, box?.deviceId), timestamp: new Date() });
  } catch {
    res.status(500).json({ esp32Connected: false });
  }
});

module.exports = { router, setSocketIO };
