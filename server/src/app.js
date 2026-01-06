const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const mongoose = require('mongoose');
const cors = require('cors');
const dotenv = require('dotenv');
const connectDB = require('./config/db');

// Load env vars
dotenv.config();

// Connect to database
connectDB();

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: "*",
    }
});

// Store io in express app
app.set('io', io);

// Body parser
app.use(express.json());

// Enable CORS
app.use(cors());

// Request logging middleware
app.use((req, res, next) => {
    console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
    next();
});

// WebSocket Connection
io.on('connection', (socket) => {
    console.log('A user connected:', socket.id);

    socket.on('join', (userId) => {
        socket.join(userId);
        console.log(`User ${userId} joined their room`);
    });

    socket.on('disconnect', () => {
        console.log('User disconnected');
    });
});

// Watch for MongoDB Changes
mongoose.connection.once('open', () => {
    console.log('Watching for changes in MongoDB...');

    // Watch Tracking collection
    const trackingChangeStream = mongoose.connection.collection('trackings').watch([], { fullDocument: 'updateLookup' });
    trackingChangeStream.on('change', (change) => {
        if (change.operationType === 'insert' || change.operationType === 'update') {
            const doc = change.fullDocument;
            const userId = doc?.userId;
            if (userId) {
                io.to(userId).emit('trackingUpdate', change);
            }
            // Also notify admins (global)
            io.emit('allTrackingUpdate', change);
        }
    });

    // Watch Notifications collection
    const notificationChangeStream = mongoose.connection.collection('notifications').watch();
    notificationChangeStream.on('change', (change) => {
        if (change.operationType === 'insert') {
            const userId = change.fullDocument.userId;
            io.to(userId).emit('notificationNew', change.fullDocument);
        }
    });

    // Watch DeviceControl collection
    const deviceChangeStream = mongoose.connection.collection('devicecontrols').watch([], { fullDocument: 'updateLookup' });
    deviceChangeStream.on('change', (change) => {
        if (change.operationType === 'insert' || change.operationType === 'update') {
            const doc = change.fullDocument;
            io.emit('doorStateUpdate', doc);
        }
    });

    // Watch Scan Logs (Admin)
    const scanLogChangeStream = mongoose.connection.collection('scanlogs').watch();
    scanLogChangeStream.on('change', (change) => {
        if (change.operationType === 'insert') {
            io.emit('scanLogNew', change.fullDocument);
        }
    });

    // Watch Delivery Logs (Admin)
    const deliveryLogChangeStream = mongoose.connection.collection('deliverylogs').watch();
    deliveryLogChangeStream.on('change', (change) => {
        if (change.operationType === 'insert') {
            io.emit('deliveryLogNew', change.fullDocument);
        }
    });

    // Watch Users (Admin)
    const userChangeStream = mongoose.connection.collection('users').watch();
    userChangeStream.on('change', (change) => {
        if (change.operationType === 'insert' || change.operationType === 'update') {
            io.emit('userUpdate', change);
        }
    });
});

// Basic health check
app.get('/', (req, res) => {
    res.send('Smart Parcel Drop Box API with WebSockets is running...');
});

// Import Routes
const userRoutes = require('./routes/userRoutes');
const trackingRoutes = require('./routes/trackingRoutes');
const scanLogRoutes = require('./routes/scanLogRoutes');
const notificationRoutes = require('./routes/notificationRoutes');
const deviceRoutes = require('./routes/deviceRoutes');
const deliveryLogRoutes = require('./routes/deliveryLogRoutes');

app.use('/api/users', userRoutes);
app.use('/api/tracking', trackingRoutes);
app.use('/api/scan-logs', scanLogRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/device-control', deviceRoutes);
app.use('/api/delivery-logs', deliveryLogRoutes);

const PORT = process.env.PORT || 5000;

server.listen(PORT, () => {
    console.log(`Server running in ${process.env.NODE_ENV} mode on port ${PORT}`);
});
