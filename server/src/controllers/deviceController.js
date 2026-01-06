const DeviceControl = require('../models/DeviceControl');
const DeliveryLog = require('../models/DeliveryLog');

// @desc    Send command to device
// @route   POST /api/device-control
exports.sendCommand = async (req, res) => {
    try {
        const { command, userId } = req.body;
        const deviceControl = await DeviceControl.create({
            command,
            userId,
            status: 'pending'
        });

        // Log the event
        await DeliveryLog.create({
            userId: userId || 'unknown',
            eventType: command === 'open' ? 'door_opened_manually' : 'door_closed_manually',
            details: `Door ${command} command sent via app`,
            trackingId: 'MANUAL'
        });

        // Manual WebSocket emission as fallback
        const io = req.app.get('io');
        if (io) {
            io.emit('doorStateUpdate', deviceControl);
            console.log(`[SOCKET] Manual doorStateUpdate emitted: ${command}`);
        }

        res.status(201).json(deviceControl);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get latest device state/command
// @route   GET /api/device-control/latest
exports.getLatestCommand = async (req, res) => {
    try {
        const command = await DeviceControl.findOne().sort({ timestamp: -1 });
        res.json(command);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
