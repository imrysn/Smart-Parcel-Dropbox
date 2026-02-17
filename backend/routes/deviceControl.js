/**
 * Device Control Routes
 * Handles door control and status endpoints
 */

const express = require('express');
const router = express.Router();
const DoorState = require('../models/DoorState');
const esp32Controller = require('../hardware/esp32Controller');

// Global socket.io instance (set by server.js)
let io = null;

function setSocketIO(socketIO) {
  io = socketIO;
}

/**
 * POST /device-control
 * Control a specific door (parcel or user)
 */
router.post('/', async (req, res) => {
  try {
    const { userId, command, doorType } = req.body;

    if (!userId || !command || !doorType) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields: userId, command, doorType'
      });
    }

    if (!['open', 'close'].includes(command)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid command. Must be "open" or "close"'
      });
    }

    if (!['parcel', 'user'].includes(doorType)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid doorType. Must be "parcel" or "user"'
      });
    }

    console.log(`🚪 Door Control Request: ${doorType} door ${command} by ${userId}`);

    // Get current state
    const doorState = await DoorState.getInstance();
    doorState.status = 'processing';
    doorState.userId = userId;
    await doorState.save();

    // Broadcast processing status
    if (io) {
      io.emit('doorStateUpdate', {
        parcelDoorOpen: doorState.parcelDoorOpen,
        userDoorOpen: doorState.userDoorOpen,
        status: 'processing',
        parcelDetected: doorState.parcelDetected,
        userId: doorState.userId
      });
    }

    // Send command to ESP32
    const result = await esp32Controller.controlDoor(doorType, command);

    if (result.success) {
      // Update door state
      if (doorType === 'parcel') {
        doorState.parcelDoorOpen = (command === 'open');
      } else {
        doorState.userDoorOpen = (command === 'open');
      }
      doorState.status = 'idle';
      doorState.lastUpdate = new Date();
      await doorState.save();

      // Broadcast new state
      if (io) {
        io.emit('doorStateUpdate', {
          parcelDoorOpen: doorState.parcelDoorOpen,
          userDoorOpen: doorState.userDoorOpen,
          status: 'idle',
          parcelDetected: doorState.parcelDetected,
          userId: doorState.userId
        });
      }

      const doorName = doorType === 'parcel' ? 'Parcel door' : 'User door';
      res.json({
        success: true,
        message: `${doorName} ${command === 'open' ? 'opened' : 'closed'} successfully`,
        doorState: {
          parcelDoorOpen: doorState.parcelDoorOpen,
          userDoorOpen: doorState.userDoorOpen,
          status: doorState.status,
          parcelDetected: doorState.parcelDetected
        }
      });
    } else {
      doorState.status = 'idle';
      await doorState.save();

      res.status(500).json({
        success: false,
        message: 'Failed to control door',
        error: result.error
      });
    }
  } catch (error) {
    console.error('❌ Device Control Error:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error',
      error: error.message
    });
  }
});

/**
 * GET /device-control
 * Get current door states
 */
router.get('/', async (req, res) => {
  try {
    const doorState = await DoorState.getInstance();

    res.json({
      parcelDoorOpen: doorState.parcelDoorOpen,
      userDoorOpen: doorState.userDoorOpen,
      status: doorState.status,
      parcelDetected: doorState.parcelDetected,
      userId: doorState.userId
    });
  } catch (error) {
    console.error('❌ Get Door State Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get door state',
      error: error.message
    });
  }
});

/**
 * GET /device-control/health
 * Check ESP32 connection health
 */
router.get('/health', async (req, res) => {
  const esp32Online = await esp32Controller.ping();
  
  res.json({
    esp32Connected: esp32Online,
    timestamp: new Date()
  });
});

module.exports = {
  router,
  setSocketIO
};
