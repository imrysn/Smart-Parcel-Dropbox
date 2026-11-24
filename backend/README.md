# Smart Parcel Drop Box - Backend Server

Backend server for the Smart Parcel Drop Box system with ESP32-S3 door control and Arduino barcode scanner integration.

## Features

- ✅ **Two-Door Control** - Independent control of parcel entrance and user retrieval doors
- ✅ **ESP32-S3 Integration** - HTTP-based communication with ESP32-S3
- ✅ **Arduino Scanner** - Serial communication with MH-ET Live Scanner v3
- ✅ **Real-time Updates** - WebSocket broadcasting for instant UI updates
- ✅ **MongoDB Storage** - Persistent door state management
- ✅ **RESTful API** - Clean API endpoints for mobile app

## Quick Start

### 1. Install Dependencies

```bash
cd backend
npm install
```

### 2. Configure Environment

Copy `.env.example` to `.env` and update:

```bash
cp .env.example .env
```

Edit `.env`:

```env
PORT=3000
MONGODB_URI=mongodb://localhost:27017/smart_parcel_dropbox

# ESP32-S3 Configuration
ESP32_IP=192.168.1.100
ESP32_PORT=80

# Arduino Scanner Configuration
SCANNER_PORT=COM3
SCANNER_BAUD_RATE=9600
```

### 3. Start MongoDB

```bash
# Windows
mongod

# Or use MongoDB Atlas (cloud)
```

### 4. Run Server

```bash
# Development (with auto-reload)
npm run dev

# Production
npm start
```

Server will start on `http://localhost:3000`

## API Endpoints

### POST `/device-control`

Control a specific door.

**Request:**

```json
{
  "userId": "user_id",
  "command": "open",
  "doorType": "parcel"
}
```

**Response:**

```json
{
  "success": true,
  "message": "Parcel door opened successfully",
  "doorState": {
    "parcelDoorOpen": true,
    "userDoorOpen": false,
    "status": "idle"
  }
}
```

### GET `/device-control`

Get current door states.

**Response:**

```json
{
  "parcelDoorOpen": false,
  "userDoorOpen": false,
  "status": "idle",
  "parcelDetected": false,
  "userId": "current_user"
}
```

### GET `/device-control/health`

Check ESP32 connection status.

**Response:**

```json
{
  "esp32Connected": true,
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

## WebSocket Events

### `confirmedDeposit`

Authenticated firmware can replay one confirmed inbound deposit at a time using a Socket.IO acknowledgment callback. Send a stable `eventId` (1–64 letters, digits, underscores, or hyphens) and the MongoDB `trackingRecordId` from the box's authorization record. Include `occurredAt` as a UTC ISO timestamp with milliseconds when the box has trusted time. Otherwise omit it, and the server uses its receipt time.

Discard the local event only after the matching `{ ok: true, eventId, duplicate, notificationId }` acknowledgment. Retry a lost acknowledgment or server failure with the same payload. Keep an event with an eligibility or identity conflict for operator review. The replay transaction requires a [MongoDB replica set or sharded cluster](https://www.mongodb.com/docs/manual/core/transactions/).

To exercise replay from a simulated box, set `SPD_TEST_MONGO_URI` to an isolated test replica set and run `node --test backend/tests/deposit_replay_integration.test.js` from the repository root. The test creates and drops its own randomly named database.

### Multiple Parcels bench trial

Enable the ESP32's Multiple Parcels menu only after testing the chute and latch on a supervised unit. In its private `device_secrets.h`, set the measured `SPD_BATCH_CHUTE_NEAR_CM`, the sensor's supported `SPD_BATCH_CHUTE_SAMPLE_MS`, and the supervised `SPD_BATCH_MAX_ITEMS` (up to 32 saved items). This limit bounds the batch; it does not measure remaining bin capacity.

The rider scans and drops one parcel at a time. **Red** stops new scans while the rider closes the entry door. Closing the door also stops new scans and finishes the batch if the rider skips Red. The firmware resolves any active attempt and requires reed-confirmed closure before replay. It retains one batch in flash until acknowledged. New scans require online authorization in this trial. If the connection drops, the box can finish and preserve the items already authorized. A reboot during an open batch sends its retained items for owner review after the door is closed.

The owner opens **Dropbox → Manage → Drop-off batches** and scans the waybill for any item marked **Needs review**. The backend applies delivery status, bin count, and notification together after confirmation. A rejected flash record stays available for reconciliation and prevents another batch on that unit.

### `doorStateUpdate`

Emitted when door state changes.

```json
{
  "parcelDoorOpen": false,
  "userDoorOpen": true,
  "status": "idle",
  "parcelDetected": true,
  "userId": "user_id"
}
```

### `barcodeScan`

Emitted when barcode is scanned.

```json
{
  "barcode": "1234567890",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

## ESP32-S3 Setup

Your ESP32-S3 should expose these HTTP endpoints:

### POST `/door`

```json
{
  "type": "parcel",
  "action": "open"
}
```

### GET `/status`

```json
{
  "parcelDoorOpen": false,
  "userDoorOpen": false,
  "parcelDetected": false
}
```

### GET `/ping`

Health check endpoint.

## Arduino Scanner Setup

The Arduino UNO R3 with MH-ET Live Scanner v3 should:

1. Read barcode data from scanner
2. Send barcode via Serial (9600 baud)
3. Format: `BARCODE_DATA\n`

## Project Structure

```
backend/
├── server.js                  # Main server file
├── routes/
│   └── deviceControl.js       # API routes
├── models/
│   └── DoorState.js           # MongoDB schema
├── hardware/
│   ├── esp32Controller.js     # ESP32-S3 HTTP client
│   └── arduinoScanner.js      # Arduino serial client
├── package.json
├── .env.example
└── README.md
```

## Troubleshooting

### ESP32 Not Responding

1. Check ESP32 IP address in `.env`
2. Verify ESP32 is on same network
3. Test with: `curl http://10.63.248.205/ping`

### Arduino Scanner Not Working

1. Check COM port in Device Manager
2. Verify baud rate matches Arduino code
3. Test serial connection with Arduino IDE

### MongoDB Connection Failed

1. Ensure MongoDB is running
2. Check connection string in `.env`
3. Server will run without DB but features limited

## Development

```bash
# Install nodemon for auto-reload
npm install -g nodemon

# Run in development mode
npm run dev
```

## Deployment

For production deployment:

1. Use PM2 for process management
2. Set up MongoDB Atlas for cloud database
3. Configure firewall for port 3000
4. Use HTTPS with reverse proxy (nginx)

```bash
# Install PM2
npm install -g pm2

# Start with PM2
pm2 start server.js --name dropbox-backend

# Save PM2 config
pm2 save
pm2 startup
```

## License

MIT
