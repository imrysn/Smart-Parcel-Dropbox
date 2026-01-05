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

### Protocol: WebSockets (Socket.io)

```
Mobile App ←→ Node.js Backend (Socket.io) ←→ ESP32 S3
```

**Advantages:**
- True real-time bidirectional communication
- Lower latency than polling or cloud database sync
- Full control over data validation on the server
- Consistent with the MongoDB/Node.js tech stack

---

## Phase 1: Basic Communication (Setup)

### 1.1 Backend Configuration

#### Socket.io Integration
The backend is already configured to use Socket.io. The server watches MongoDB collections and emits events to the corresponding user rooms.

#### Event Mapping
1. **`doorStateUpdate`**: Emitted when a new command is added to the `devicecontrols` collection.
2. **`sensorData`**: ESP32 emits this to send ultrasonic/PIR data to the server.
3. **`scanLogNew`**: Emitted when a delivery person scans a QR code.

### 1.2 IoT Service in Flutter
The `IoTService` in `lib/services/iot_service.dart` acts as the interface for the mobile app to send commands to the backend.

### 1.3 ESP32 Connection String
The ESP32 will connect to:
`ws://[YOUR_SERVER_IP]:5000`


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
---

## Phase 2: ESP32 Implementation (WebSockets)

### 2.1 ESP32 S3 Setup

#### Required Libraries (Arduino IDE)
- `SocketIoClient` by Markus Sattler
- `WebSocketsClient` by Markus Sattler
- `ArduinoJson` by Benoit Blanchon

#### ESP32 WebSocket Client (Example Code)
```cpp
#include <WiFi.h>
#include <SocketIoClient.h>
#include <ArduinoJson.h>

// WiFi credentials
const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";

// Server details
const char* serverHost = "YOUR_SERVER_IP"; 
const int serverPort = 5000;

SocketIoClient socket;
String userId = "USER_ID_FROM_APP"; // Replace with actual user ID

// Pin definitions
#define SOLENOID_PIN 26
#define DOOR_SENSOR_PIN 27
#define PIR_SENSOR_PIN 14
#define ULTRASONIC_TRIG 12
#define ULTRASONIC_ECHO 13

void setup() {
    Serial.begin(115200);
    
    // Initialize pins
    pinMode(SOLENOID_PIN, OUTPUT);
    digitalWrite(SOLENOID_PIN, LOW); // Locked
    
    // Connect to WiFi
    WiFi.begin(ssid, password);
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\nWiFi Connected!");

    // Set up Socket.io event listeners
    socket.on("doorStateUpdate", handleDoorCommand);
    socket.on("connect", onConnect);
    
    // Start Connection
    socket.begin(serverHost, serverPort);
}

void loop() {
    socket.loop();
    
    // Send sensor data periodically
    static unsigned long lastUpdate = 0;
    if (millis() - lastUpdate > 5000) {
        sendSensorData();
        lastUpdate = millis();
    }
}

void onConnect(const char * payload, size_t length) {
    Serial.println("Connected to Server!");
    // Join the user's specific room
    socket.emit("join", userId.c_str());
}

void handleDoorCommand(const char * payload, size_t length) {
    StaticJsonDocument<200> doc;
    deserializeJson(doc, payload);
    
    const char* command = doc["command"];
    if (String(command) == "open") {
        Serial.println("Opening Door...");
        digitalWrite(SOLENOID_PIN, HIGH);
    } else {
        Serial.println("Closing Door...");
        digitalWrite(SOLENOID_PIN, LOW);
    }
}

void sendSensorData() {
    // Logic to read HC-SR04 and PIR
    long duration, distance;
    digitalWrite(ULTRASONIC_TRIG, LOW);
    delayMicroseconds(2);
    digitalWrite(ULTRASONIC_TRIG, HIGH);
    delayMicroseconds(10);
    digitalWrite(ULTRASONIC_TRIG, LOW);
    duration = pulseIn(ULTRASONIC_ECHO, HIGH);
    distance = (duration/2) / 29.1;

    StaticJsonDocument<200> doc;
    doc["userId"] = userId;
    doc["parcelDetected"] = (distance < 20);
    doc["doorOpen"] = digitalRead(DOOR_SENSOR_PIN) == LOW;

    String output;
    serializeJson(doc, output);
    socket.emit("sensorData", output.c_str());
}
```

---

## Phase 3: Scanner & Authentication

### 3.1 QR Scanner Logic
The ESP32 reads the QR code and emits a `scanRequest` event.
1. ESP32 scans tracking ID.
2. ESP32 emits `socket.emit("verifyScan", trackingId)`.
3. Server receives event, checks MongoDB `trackings` collection.
4. If valid, server emits `doorStateUpdate` to "open".

---

## Phase 4: Testing & Deployment

### 4.1 Integration Checklist
- [ ] ESP32 connects to local Node.js server successfully.
- [ ] `join` event works (ESP32 enters the correct user room).
- [ ] Mobile app "Open Door" updates MongoDB and triggers WebSocket event to ESP32.
- [ ] ESP32 sensor data (parcel detection) reflects in Mobile App UI.
- [ ] Scanner triggers the "delivered" flow in the backend.

---

## Bill of Materials (BOM)

| Component | Quantity | Est. Cost (PHP) |
|-----------|----------|-----------------|
| ESP32 S3 Dev Board | 1 | ₱550 |
| MH-ET LIVE QR Scanner v3.0 | 1 | ₱850 |
| 12V Solenoid Lock | 1 | ₱350 |
| 1-Channel Relay Module | 1 | ₱50 |
| HC-SR04/HC-SR04+ | 1 | ₱90 |
| HC-SR501 PIR Sensor | 1 | ₱45 |
| **Total** | | **~₱1,935** |

---

## Next Steps

1. **Local Server Setup**: Ensure `server/src/app.js` IP is accessible by the ESP32.
2. **Environment Specs**: Update `.env` with the local IP of your development machine.
3. **Hardcode User ID**: For testing, hardcode your MongoDB User ID into the ESP32 code.
4. **Physical Build**: Assemble the sensors and relay according to the Pin Mapping.

**Status:** 🚀 Migrated to MongoDB/WebSockets  
**Priority:** ⭐⭐⭐ High (Core Thesis Functionality)  
**Architecture:** MERN-like (Mongo, Express, React-Native/Flutter, Node) + Socket.io  
