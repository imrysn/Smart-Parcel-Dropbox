const io = require('socket.io-client');

// ============================================================
//  Smart Parcel Dropbox — Hardware Simulator (CS Depth)
//  Used for testing the mobile app without raw hardware.
// ============================================================

const SERVER_URL = 'https://smart-parcel-dropbox-depth.onrender.com';
const socket = io(SERVER_URL, {
  transports: ['websocket'],
  query: { EIO: '3' } // Match ESP32 protocol version
});

console.log(`🤖 Connecting to Depth Server: ${SERVER_URL}...`);

socket.on('connect', () => {
  console.log('✅ SIMULATOR CONNECTED: Acting as ESP32 Hardware.');

  // 1. Send Initial Status (Bin 45% full, Door Locked)
  const initialStatus = {
    connected: true,
    doorLocked: true,
    binFillPercent: 45,
    lastAction: 'SIMULATOR_STAGING',
    timestamp: new Date().toISOString()
  };

  console.log('📤 Emitting simulated status: 45% Full...');
  socket.emit('updateStatus', initialStatus);

  // 2. Loop: Randomize Bin Growth every 30s to simulate usage
  let currentFill = 45;
  setInterval(() => {
    currentFill = Math.min(100, currentFill + Math.floor(Math.random() * 5));
    socket.emit('updateStatus', {
      connected: true,
      doorLocked: true,
      binFillPercent: currentFill,
      lastAction: 'SIM_USAGE',
      timestamp: new Date().toISOString()
    });
    console.log(`📊 Updated Fill: ${currentFill}%`);
  }, 30000);
});

// Handle remote lock commands from the App
socket.on('controlDevice', (data) => {
  console.log(`📥 RECEIVED REMOTE COMMAND: ${data.action}`);
  
  // Simulate the action
  const newState = {
    connected: true,
    doorLocked: (data.action === 'lock'),
    binFillPercent: 45,
    lastAction: `REMOTE_${data.action.toUpperCase()}`,
    timestamp: new Date().toISOString()
  };

  setTimeout(() => {
    console.log(`✅ ACTION COMPLETE: Door is now ${newState.doorLocked ? 'LOCKED' : 'UNLOCKED'}`);
    socket.emit('updateStatus', newState);
  }, 1500);
});

socket.on('disconnect', () => {
  console.log('❌ Simulator Disconnected.');
});
