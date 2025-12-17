# 🔌 IoT Integration Plan - Smart Parcel Drop Box

## Overview

This document provides a comprehensive plan for integrating the mobile app with the IoT hardware (ESP32-based smart drop box system).

---

## Hardware Components

### Primary Components
1. **ESP32 Development Board** - Main controller
2. **MH-ET LIVE Scanner v3.0** - QR/Barcode scanner
3. **12V Solenoid Lock** - Door locking mechanism
4. **Relay Module** - Control solenoid
5. **HC-SR04 Ultrasonic Sensor** - Parcel detection
6. **HC-SR501 PIR Motion Sensor** - Presence detection
7. **HX711 Load Cell** - Weight measurement
8. **Reed Switch** - Door status
9. **16x2 LCD Display** - Status display
10. **GSM Module (Optional)** - Backup communication

### Power Supply
- 12V DC adapter for solenoid
- 5V regulator for ESP32 and sensors
- Battery backup (optional)

---

## Communication Architecture

### Option 1: Firebase Realtime Database (Recommended)
```
Mobile App ←→ Firebase Realtime DB ←→ ESP32
```

**Advantages:**
- Real-time bidirectional sync
- Automatic offline handling
- No server management needed
- Built-in authentication

**Disadvantages:**
- Requires WiFi on ESP32
- Data usage considerations

### Option 2: MQTT (Alternative)
```
Mobile App ←→ MQTT Broker ←→ ESP32
```

**Advantages:**
- Lightweight protocol
- Good for IoT devices
- Low bandwidth usage

**Disadvantages:**
- Need to set up broker
- More complex setup

### Recommended: Firebase Realtime Database

---

## Phase 1: Basic Communication (Week 1)

### 1.1 Firebase Setup for IoT

#### Create Realtime Database
1. Go to Firebase Console → Realtime Database
2. Create database in same region as Firestore
3. Start in test mode (update rules later)

#### Database Structure
```json
{
  "dropboxes": {
    "dropbox_001": {
      "status": "idle",
      "doorLocked": true,
      "lastUpdate": 1234567890,
      "location": "Bacoor Campus Gate 1"
    }
  },
  "scan_requests": {
    "scan_001": {
      "trackingId": "TRACK123",
      "timestamp": 1234567890,
      "status": "pending",
      "dropboxId": "dropbox_001"
    }
  },
  "unlock_commands": {
    "cmd_001": {
      "dropboxId": "dropbox_001",
      "trackingId": "TRACK123",
      "timestamp": 1234567890,
      "executed": false
    }
  },
  "sensor_data": {
    "dropbox_001": {
      "parcelDetected": false,
      "doorOpen": false,
      "weight": 0,
      "timestamp": 1234567890
    }
  }
}
```

#### Security Rules
```json
{
  "rules": {
    "dropboxes": {
      ".read": "auth != null",
      "$dropboxId": {
        ".write": "auth != null"
      }
    },
    "scan_requests": {
      ".read": "auth != null",
      ".write": "auth != null"
    },
    "unlock_commands": {
      ".read": "auth != null",
      ".write": "auth != null"
    },
    "sensor_data": {
      ".read": "auth != null",
      "$dropboxId": {
        ".write": "auth != null"
      }
    }
  }
}
```

### 1.2 Add Firebase Realtime Database to Flutter App

#### Add Dependencies
```yaml
# pubspec.yaml
dependencies:
  firebase_database: ^10.4.0
```

#### Create IoT Service
```dart
// lib/services/iot_service.dart
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class IoTService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  
  /// Send unlock command to dropbox
  Future<void> sendUnlockCommand({
    required String dropboxId,
    required String trackingId,
  }) async {
    try {
      final cmdRef = _database.ref('unlock_commands').push();
      await cmdRef.set({
        'dropboxId': dropboxId,
        'trackingId': trackingId,
        'timestamp': ServerValue.timestamp,
        'executed': false,
      });
      
      debugPrint('Unlock command sent: ${cmdRef.key}');
    } catch (e) {
      debugPrint('Error sending unlock command: $e');
      throw 'Failed to send unlock command';
    }
  }
  
  /// Listen to dropbox status
  Stream<Map<String, dynamic>> listenToDropboxStatus(String dropboxId) {
    return _database
        .ref('dropboxes/$dropboxId')
        .onValue
        .map((event) {
      if (event.snapshot.value != null) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return <String, dynamic>{};
    });
  }
  
  /// Listen to sensor data
  Stream<Map<String, dynamic>> listenToSensorData(String dropboxId) {
    return _database
        .ref('sensor_data/$dropboxId')
        .onValue
        .map((event) {
      if (event.snapshot.value != null) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return <String, dynamic>{};
    });
  }
  
  /// Get all dropboxes
  Future<List<Map<String, dynamic>>> getDropboxes() async {
    try {
      final snapshot = await _database.ref('dropboxes').get();
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return data.entries.map((entry) {
          final dropboxData = Map<String, dynamic>.from(entry.value);
          dropboxData['id'] = entry.key;
          return dropboxData;
        }).toList();
      }
      
      return [];
    } catch (e) {
      debugPrint('Error getting dropboxes: $e');
      return [];
    }
  }
  
  /// Request scan from dropbox
  Future<void> requestScan({
    required String dropboxId,
    required String trackingId,
  }) async {
    try {
      final scanRef = _database.ref('scan_requests').push();
      await scanRef.set({
        'trackingId': trackingId,
        'dropboxId': dropboxId,
        'timestamp': ServerValue.timestamp,
        'status': 'pending',
      });
      
      debugPrint('Scan request sent: ${scanRef.key}');
    } catch (e) {
      debugPrint('Error requesting scan: $e');
      throw 'Failed to request scan';
    }
  }
}
```

### 1.3 Update TrackingDetailsScreen

Add unlock button and real-time status:

```dart
// lib/screens/tracking_details_screen.dart
import '../services/iot_service.dart';

class TrackingDetailsScreen extends StatefulWidget {
  final TrackingModel tracking;
  
  const TrackingDetailsScreen({super.key, required this.tracking});
  
  @override
  State<TrackingDetailsScreen> createState() => _TrackingDetailsScreenState();
}

class _TrackingDetailsScreenState extends State<TrackingDetailsScreen> {
  final IoTService _iotService = IoTService();
  bool _isUnlocking = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Existing tracking details...
            
            const SizedBox(height: 24),
            
            // Dropbox Status Card
            if (widget.tracking.status == 'delivered')
              _buildDropboxStatusCard(),
            
            const SizedBox(height: 16),
            
            // Unlock Button
            if (widget.tracking.status == 'delivered')
              _buildUnlockButton(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDropboxStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Drop Box Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Real-time status stream
            StreamBuilder<Map<String, dynamic>>(
              stream: _iotService.listenToDropboxStatus('dropbox_001'),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                
                final data = snapshot.data ?? {};
                final status = data['status'] ?? 'unknown';
                final doorLocked = data['doorLocked'] ?? true;
                
                return Column(
                  children: [
                    _buildStatusRow(
                      'Status',
                      status,
                      status == 'idle' ? Colors.green : Colors.orange,
                    ),
                    const Divider(),
                    _buildStatusRow(
                      'Door',
                      doorLocked ? 'Locked' : 'Unlocked',
                      doorLocked ? Colors.green : Colors.orange,
                    ),
                    const Divider(),
                    _buildStatusRow(
                      'Location',
                      data['location'] ?? 'Unknown',
                      Colors.blue,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUnlockButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isUnlocking ? null : _unlockDropbox,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        icon: _isUnlocking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.lock_open),
        label: Text(
          _isUnlocking ? 'Unlocking...' : 'Unlock Drop Box',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
  
  Future<void> _unlockDropbox() async {
    setState(() => _isUnlocking = true);
    
    try {
      await _iotService.sendUnlockCommand(
        dropboxId: 'dropbox_001',
        trackingId: widget.tracking.trackingId,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unlock command sent to drop box'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unlock: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUnlocking = false);
      }
    }
  }
}
```

---

## Phase 2: ESP32 Implementation (Week 2-3)

### 2.1 ESP32 Arduino Code Setup

#### Install Required Libraries
```cpp
// Arduino IDE: Tools → Manage Libraries
// Install:
// - Firebase ESP32 Client
// - ArduinoJson
// - ESP32Servo (for servo if using)
```

#### Basic ESP32 Code
```cpp
// esp32_dropbox.ino
#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// WiFi credentials
#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

// Firebase credentials
#define API_KEY "YOUR_FIREBASE_API_KEY"
#define DATABASE_URL "YOUR_DATABASE_URL"
#define USER_EMAIL "dropbox@yourdomain.com"
#define USER_PASSWORD "your_secure_password"

// Pin definitions
#define SOLENOID_PIN 26
#define DOOR_SENSOR_PIN 27
#define PIR_SENSOR_PIN 14
#define ULTRASONIC_TRIG 12
#define ULTRASONIC_ECHO 13

// Firebase objects
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

String dropboxId = "dropbox_001";
bool doorLocked = true;

void setup() {
  Serial.begin(115200);
  
  // Initialize pins
  pinMode(SOLENOID_PIN, OUTPUT);
  pinMode(DOOR_SENSOR_PIN, INPUT_PULLUP);
  pinMode(PIR_SENSOR_PIN, INPUT);
  pinMode(ULTRASONIC_TRIG, OUTPUT);
  pinMode(ULTRASONIC_ECHO, INPUT);
  
  // Lock the door initially
  digitalWrite(SOLENOID_PIN, LOW);
  
  // Connect to WiFi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(300);
  }
  Serial.println("\nConnected to WiFi");
  Serial.println(WiFi.localIP());
  
  // Configure Firebase
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;
  config.token_status_callback = tokenStatusCallback;
  
  // Initialize Firebase
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  
  // Wait for authentication
  Serial.println("Waiting for authentication...");
  while (!Firebase.ready()) {
    delay(100);
  }
  Serial.println("Firebase authenticated!");
  
  // Update initial status
  updateDropboxStatus();
  
  // Start listening for unlock commands
  Firebase.RTDB.beginStream(&fbdo, "/unlock_commands");
  Firebase.RTDB.setStreamCallback(&fbdo, streamCallback, streamTimeoutCallback);
}

void loop() {
  // Read sensors
  bool doorOpen = !digitalRead(DOOR_SENSOR_PIN); // Reed switch
  bool motionDetected = digitalRead(PIR_SENSOR_PIN);
  bool parcelDetected = checkParcelPresence();
  
  // Update sensor data every 5 seconds
  static unsigned long lastUpdate = 0;
  if (millis() - lastUpdate > 5000) {
    updateSensorData(parcelDetected, doorOpen);
    lastUpdate = millis();
  }
  
  // Handle door lock timeout
  handleDoorLockTimeout();
  
  delay(100);
}

void streamCallback(FirebaseStream data) {
  Serial.println("Stream data available...");
  
  if (data.dataType() == "json") {
    FirebaseJson *json = data.to<FirebaseJson *>();
    FirebaseJsonData jsonData;
    
    // Parse the unlock command
    json->get(jsonData, "executed");
    if (!jsonData.to<bool>()) {
      json->get(jsonData, "dropboxId");
      if (jsonData.to<String>() == dropboxId) {
        // Execute unlock command
        unlockDoor();
        
        // Mark as executed
        String path = data.dataPath();
        Firebase.RTDB.setBool(&fbdo, path + "/executed", true);
      }
    }
  }
}

void streamTimeoutCallback(bool timeout) {
  if (timeout) {
    Serial.println("Stream timeout, resuming...");
  }
}

void unlockDoor() {
  Serial.println("Unlocking door...");
  digitalWrite(SOLENOID_PIN, HIGH);
  doorLocked = false;
  updateDropboxStatus();
  
  // Auto-lock after 30 seconds
  delay(30000);
  lockDoor();
}

void lockDoor() {
  Serial.println("Locking door...");
  digitalWrite(SOLENOID_PIN, LOW);
  doorLocked = true;
  updateDropboxStatus();
}

void updateDropboxStatus() {
  String path = "/dropboxes/" + dropboxId;
  FirebaseJson json;
  json.set("status", doorLocked ? "idle" : "unlocked");
  json.set("doorLocked", doorLocked);
  json.set("lastUpdate/.sv", "timestamp");
  json.set("location", "Bacoor Campus Gate 1");
  
  if (Firebase.RTDB.setJSON(&fbdo, path.c_str(), &json)) {
    Serial.println("Status updated");
  } else {
    Serial.println("Failed to update status: " + fbdo.errorReason());
  }
}

void updateSensorData(bool parcel, bool door) {
  String path = "/sensor_data/" + dropboxId;
  FirebaseJson json;
  json.set("parcelDetected", parcel);
  json.set("doorOpen", door);
  json.set("weight", 0); // TODO: Add load cell reading
  json.set("timestamp/.sv", "timestamp");
  
  Firebase.RTDB.setJSON(&fbdo, path.c_str(), &json);
}

bool checkParcelPresence() {
  // Ultrasonic sensor reading
  digitalWrite(ULTRASONIC_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(ULTRASONIC_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(ULTRASONIC_TRIG, LOW);
  
  long duration = pulseIn(ULTRASONIC_ECHO, HIGH);
  float distance = duration * 0.034 / 2;
  
  // If distance < 20cm, parcel is present
  return distance < 20 && distance > 0;
}

void handleDoorLockTimeout() {
  // Auto-lock logic if needed
}
```

---

## Phase 3: Scanner Integration (Week 4)

### 3.1 Add QR Scanner to ESP32

```cpp
// Add to esp32_dropbox.ino
#include <SoftwareSerial.h>

SoftwareSerial scanner(16, 17); // RX, TX pins

void setup() {
  // ... existing setup code
  
  // Initialize scanner
  scanner.begin(9600);
  Serial.println("Scanner initialized");
}

void loop() {
  // ... existing loop code
  
  // Check for scanned data
  if (scanner.available()) {
    String scannedCode = scanner.readStringUntil('\n');
    scannedCode.trim();
    
    if (scannedCode.length() > 0) {
      handleScannedCode(scannedCode);
    }
  }
}

void handleScannedCode(String code) {
  Serial.println("Scanned: " + code);
  
  // Save scan attempt to Firebase
  String path = "/scan_requests";
  FirebaseJson json;
  json.set("trackingId", code);
  json.set("dropboxId", dropboxId);
  json.set("timestamp/.sv", "timestamp");
  json.set("status", "scanned");
  
  if (Firebase.RTDB.pushJSON(&fbdo, path.c_str(), &json)) {
    Serial.println("Scan saved to Firebase");
    
    // Verify tracking ID
    verifyTrackingId(code);
  }
}

void verifyTrackingId(String trackingId) {
  // Query Firestore via Cloud Function (recommended)
  // Or query Realtime DB if tracking data is synced there
  
  // For now, assume valid and unlock
  // In production, verify against database first
  unlockDoor();
}
```

### 3.2 Add Cloud Function for Verification

```javascript
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.verifyTrackingId = functions.database
  .ref('/scan_requests/{scanId}')
  .onCreate(async (snapshot, context) => {
    const scan = snapshot.val();
    const trackingId = scan.trackingId;
    
    try {
      // Query Firestore for tracking ID
      const trackingDoc = await admin.firestore()
        .collection('tracking_ids')
        .doc(trackingId)
        .get();
      
      if (trackingDoc.exists) {
        const data = trackingDoc.data();
        
        // Check if delivered and not retrieved
        if (data.status === 'delivered') {
          // Grant access
          await snapshot.ref.update({
            status: 'verified',
            accessGranted: true
          });
          
          // Send unlock command
          await admin.database()
            .ref('unlock_commands')
            .push({
              dropboxId: scan.dropboxId,
              trackingId: trackingId,
              timestamp: admin.database.ServerValue.TIMESTAMP,
              executed: false
            });
          
          // Create notification for user
          await admin.firestore()
            .collection('notifications')
            .add({
              userId: data.userId,
              type: 'parcel_retrieved',
              title: 'Parcel Retrieved',
              message: `Your parcel ${trackingId} has been accessed`,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              isRead: false
            });
          
          // Update tracking status
          await trackingDoc.ref.update({
            status: 'retrieved',
            retrievedAt: admin.firestore.FieldValue.serverTimestamp()
          });
          
          return null;
        } else {
          // Access denied - wrong status
          await snapshot.ref.update({
            status: 'denied',
            accessGranted: false,
            reason: `Parcel status is ${data.status}`
          });
        }
      } else {
        // Access denied - not found
        await snapshot.ref.update({
          status: 'denied',
          accessGranted: false,
          reason: 'Tracking ID not found'
        });
      }
    } catch (error) {
      console.error('Error verifying tracking ID:', error);
      await snapshot.ref.update({
        status: 'error',
        accessGranted: false,
        reason: error.message
      });
    }
    
    return null;
  });
```

---

## Phase 4: Testing & Integration (Week 5)

### 4.1 Integration Testing Checklist

- [ ] WiFi connection stable
- [ ] Firebase authentication works
- [ ] Real-time database sync working
- [ ] Unlock command received and executed
- [ ] Sensor data updates in real-time
- [ ] Scanner reads QR codes correctly
- [ ] Cloud function verifies tracking IDs
- [ ] Notifications sent to users
- [ ] Door locks/unlocks properly
- [ ] Auto-lock timeout works
- [ ] Mobile app displays real-time status

### 4.2 Safety Features

```cpp
// Add to ESP32 code
#define MAX_UNLOCK_TIME 60000 // 60 seconds max unlock time
#define AUTO_LOCK_TIME 30000  // 30 seconds auto-lock

unsigned long unlockStartTime = 0;

void loop() {
  // ... existing code
  
  // Emergency auto-lock if unlocked too long
  if (!doorLocked && (millis() - unlockStartTime > MAX_UNLOCK_TIME)) {
    Serial.println("Emergency auto-lock triggered");
    lockDoor();
  }
}

void unlockDoor() {
  Serial.println("Unlocking door...");
  digitalWrite(SOLENOID_PIN, HIGH);
  doorLocked = false;
  unlockStartTime = millis();
  updateDropboxStatus();
}
```

---

## Troubleshooting Guide

### WiFi Issues
```cpp
// Add WiFi reconnection logic
void checkWiFi() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi disconnected, reconnecting...");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
      delay(500);
      Serial.print(".");
      attempts++;
    }
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\nReconnected to WiFi");
    }
  }
}
```

### Firebase Connection Issues
```cpp
void checkFirebase() {
  if (!Firebase.ready()) {
    Serial.println("Firebase not ready, reinitializing...");
    Firebase.begin(&config, &auth);
  }
}
```

---

## Bill of Materials (BOM)

| Component | Quantity | Est. Cost (PHP) |
|-----------|----------|-----------------|
| ESP32 Dev Board | 1 | ₱400 |
| QR Scanner Module | 1 | ₱800 |
| 12V Solenoid Lock | 1 | ₱300 |
| Relay Module | 1 | ₱50 |
| HC-SR04 Ultrasonic | 1 | ₱80 |
| HC-SR501 PIR | 1 | ₱50 |
| HX711 + Load Cell | 1 | ₱250 |
| Reed Switch | 1 | ₱30 |
| 16x2 LCD | 1 | ₱150 |
| 12V Power Supply | 1 | ₱300 |
| Jumper Wires | 1 pack | ₱100 |
| Breadboard | 1 | ₱150 |
| Enclosure | 1 | ₱500 |
| **Total** | | **~₱3,160** |

---

## Timeline

| Week | Tasks | Deliverables |
|------|-------|--------------|
| 1 | Firebase setup, IoT service | Working unlock command |
| 2 | ESP32 basic code | WiFi + Firebase connection |
| 3 | Sensor integration | Real-time sensor data |
| 4 | Scanner + Cloud Function | Automated verification |
| 5 | Testing & refinement | Fully working system |

---

## Next Steps

1. ✅ Review this plan
2. Order hardware components
3. Set up Firebase Realtime Database
4. Implement IoTService in Flutter app
5. Write ESP32 code
6. Test individual components
7. Integrate everything
8. Deploy Cloud Functions
9. Full system testing
10. Document for thesis

---

**Status:** 📋 Ready for Implementation  
**Priority:** ⭐⭐⭐ Critical for Thesis  
**Timeline:** 5 weeks  
**Budget:** ~₱3,200

---

*Hardware + Software = Smart Parcel Drop Box! 🚀*
