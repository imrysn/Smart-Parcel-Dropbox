/**
 * 🔌 Smart Parcel Drop Box - ESP32 S3 Firmware
 * 
 * Features:
 * - Secure WebSocket (Socket.io) Communication
 * - Solenoid Lock Control (Relay)
 * - Sensor Data Reporting (Ultrasonic, PIR, Reed Switch)
 * - MH-ET LIVE v3.0 QR Scanner Integration
 */

#include <WiFi.h>
#include <WebSocketsClient.h>
#include <SocketIoClient.h>
#include <ArduinoJson.h>

// --- Configuration ---
const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";
const char* host = "192.168.18.78"; // Your local server IP
const int port = 5000;
const char* userId = "USER_ID_GOES_HERE"; // Hardcode your MongoDB User ID for testing

// --- Pin Definitions ---
#define SOLENOID_PIN 26
#define DOOR_SENSOR_PIN 27
#define PIR_PIN 14
#define TRIG_PIN 12
#define ECHO_PIN 13

// Serial2 for QR Scanner (MH-ET LIVE v3.0)
// Pin 16 (RX2), Pin 17 (TX2)
#define RXD2 16
#define TXD2 17

SocketIoClient socket;

// --- Helper Functions ---

void onConnect(const char * payload, size_t length) {
    Serial.println("[SOCKET] Connected to Server!");
    // Automatically join the user's room for targeted updates
    socket.emit("join", userId);
}

void handleDoorCommand(const char * payload, size_t length) {
    Serial.printf("[SOCKET] Door command received: %s\n", payload);
    StaticJsonDocument<200> doc;
    deserializeJson(doc, payload);
    
    const char* command = doc["command"];
    if (String(command) == "open") {
        Serial.println("[LOCK] Unlocking...");
        digitalWrite(SOLENOID_PIN, HIGH);
        delay(5000); // Keep open for 5 seconds
        digitalWrite(SOLENOID_PIN, LOW);
        Serial.println("[LOCK] Locked.");
    }
}

void handleScanResult(const char * payload, size_t length) {
    Serial.printf("[SOCKET] Scan verification result: %s\n", payload);
    // You can add LED or Buzzer feedback here
}

void sendSensorData() {
    // 1. Ultrasonic Distance (Parcel Detection)
    digitalWrite(TRIG_PIN, LOW);
    delayMicroseconds(2);
    digitalWrite(TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(TRIG_PIN, LOW);
    long duration = pulseIn(ECHO_PIN, HIGH);
    int distance = duration * 0.034 / 2;

    // 2. PIR Motion
    bool motion = digitalRead(PIR_PIN);

    // 3. Door State
    bool doorOpen = digitalRead(DOOR_SENSOR_PIN) == LOW; // Assuming LOW means open (Reed Switch)

    StaticJsonDocument<256> doc;
    doc["userId"] = userId;
    doc["parcelDetected"] = (distance > 0 && distance < 20); // Item within 20cm
    doc["distance"] = distance;
    doc["motionDetected"] = motion;
    doc["doorOpen"] = doorOpen;

    String output;
    serializeJson(doc, output);
    socket.emit("sensorData", output.c_str());
}

// --- Main Setup & Loop ---

void setup() {
    Serial.begin(115200);
    Serial2.begin(9600, SERIAL_8N1, RXD2, TXD2); // Scanner Serial

    pinMode(SOLENOID_PIN, OUTPUT);
    pinMode(DOOR_SENSOR_PIN, INPUT_PULLUP);
    pinMode(PIR_PIN, INPUT);
    pinMode(TRIG_PIN, OUTPUT);
    pinMode(ECHO_PIN, INPUT);

    digitalWrite(SOLENOID_PIN, LOW); // Start Locked

    // Connect to WiFi
    Serial.printf("[WIFI] Connecting to %s ", ssid);
    WiFi.begin(ssid, password);
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\n[WIFI] Connected!");

    // Setup Socket.IO
    socket.on("connect", onConnect);
    socket.on("doorStateUpdate", handleDoorCommand);
    socket.on("scanResult", handleScanResult);
    
    // Start WebSocket connection
    socket.begin(host, port);
}

void loop() {
    socket.loop();

    // Check Scanner Serial
    if (Serial2.available()) {
        String trackingId = Serial2.readStringUntil('\n');
        trackingId.trim();
        if (trackingId.length() > 0) {
            Serial.printf("[SCAN] Scanned ID: %s\n", trackingId.c_str());
            
            StaticJsonDocument<128> doc;
            doc["trackingId"] = trackingId;
            String output;
            serializeJson(doc, output);
            socket.emit("verifyScan", output.c_str());
        }
    }

    // Periodically send sensor data (every 5 seconds)
    static unsigned long lastUpdate = 0;
    if (millis() - lastUpdate > 5000) {
        sendSensorData();
        lastUpdate = millis();
    }
}
