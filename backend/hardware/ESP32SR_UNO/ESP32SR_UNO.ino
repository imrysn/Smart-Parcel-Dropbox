/*
 * SMART PARCEL DROPBOX - ESP32-S3 Main Controller
 * 
 * Reed Status: 0 = Magnet Near (Closed), 1 = Magnet Away (Open)
 * Solenoids:   Active LOW (LOW = Unlock)
 * 
 * Network: Connects to WiFi and communicates with backend via Socket.IO
 * 
 * Required Libraries (Arduino Library Manager):
 *   - ESP32Servo          (by Kevin Harrington)
 *   - Adafruit GFX        (by Adafruit)
 *   - Adafruit ILI9341    (by Adafruit)
 *   - arduinoWebSockets   (by Markus Sattler) — provides SocketIOclient
 *   - ArduinoJson         (by Benoit Blanchon, v6.x)
 */

#include <ESP32Servo.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
#include <SPI.h>
#include <WiFi.h>
#include <SocketIOclient.h>
#include <ArduinoJson.h>

// ============================================================
//  CONFIGURATION — Edit these before flashing
// ============================================================
const char* WIFI_SSID     = "Android";
const char* WIFI_PASSWORD = "Perez@543210";

// Backend server — Render.com hosted backend (HTTPS/WSS)
const char* SERVER_HOST = "smart-parcel-dropbox.onrender.com";
const uint16_t SERVER_PORT = 443;    // HTTPS/WSS port
const char* SERVER_PATH = "/socket.io/?EIO=4&transport=websocket";

// ============================================================
//  PINOUT
// ============================================================
#define TFT_CS    10
#define TFT_DC    21
#define TFT_RST   20
#define TFT_MOSI  11
#define TFT_SCK   12
#define TFT_MISO  13

#define BTN_RECEIVE      40
#define BTN_PICKUP       2
#define BUZZER_PIN       3

#define LOCK_TOP         1
#define LOCK_PICKUP      38
#define LOCK_RECEIVED    39

#define REED_TOP         9
#define REED_PICKUP      35
#define REED_RECEIVED    45

const int US_PLATFORM[2] = {15,  4};  // TRIG: 15, ECHO: 4
const int US_PICKUP[2]   = { 7, 16};  // TRIG: 7,  ECHO: 16
const int US_DROPOFF[2]  = {18,  8};  // TRIG: 18, ECHO: 8

#define SERVO_PIN        14

// ============================================================
//  DISPLAY COLORS
// ============================================================
#define COLOR_BG      0x0000
#define COLOR_TEXT    0xFFFF
#define COLOR_ACCENT  0xFD20
#define COLOR_GREEN   0x07E0
#define COLOR_RED     0xF800

// ============================================================
//  STATE MACHINE
// ============================================================
enum SystemState {
  IDLE,
  WAITING_FOR_SCAN,
  VERIFYING_SCAN,      // NEW: waiting for server scanResult response
  UNLOCKING_ENTRY,
  WAITING_PLACEMENT_STABLE,
  TILTING_PLATFORM,
  CONFIRMING_DROP,
  RESETTING
};

SystemState currentState = IDLE;
bool isReceivingMode     = true;
bool stateInitialized    = false;
bool doorWasOpened       = false;
unsigned long stateStartTime    = 0;
unsigned long stabilityStartTime = 0;
unsigned long lastDebugTime     = 0;

// ============================================================
//  TRACKING IDs
// ============================================================
String registeredDropOff  = "";  // Set via server 'registerTracking' or Serial R1:<id>
String registeredPickup   = "";  // Set via server 'registerTracking' or Serial R2:<id>
String currentTrackingId  = "";  // The ID that was scanned and verified this cycle

// Scan verification result from server
bool scanResultReceived = false;
bool scanResultValid    = false;

// Door / lock states (mirrors to app via emitDoorState)
// These track the logical state the solenoids are in
bool lockTopOpen      = false;  // true = unlocked (parcel entry door)
bool lockPickupOpen   = false;  // true = unlocked (pickup bin door)
bool lockReceivedOpen = false;  // true = unlocked (received bin door)

// ============================================================
//  OBJECTS
// ============================================================
Servo            platformServo;
Adafruit_ILI9341 tft = Adafruit_ILI9341(TFT_CS, TFT_DC, TFT_RST);
SocketIOclient   socketIO;

// ============================================================
//  FORWARD DECLARATIONS
// ============================================================
void setupWiFi();
void setupSocketIO();
void socketIOEvent(socketIOmessageType_t type, uint8_t* payload, size_t length);
void emitVerifyScan(const String& trackingId, const String& mode);
void emitStatusUpdate(const String& trackingId, const String& status, const String& mode);
void emitDoorState();
void handleRegisterTracking(const String& payload);
void handleScanResult(const String& payload);
void handleControlDoor(const String& payload);
float getDistance(const int pins[]);
void checkSerialCommands();
void printSerialMenu();
void changeState(SystemState newState);
void moveServoSmoothly(int from, int to);
void triggerBuzzer(int beeps);
void displayMessage(const char* title, const char* msg);
void displayMessageStr(const String& title, const String& msg);
void showHomeScreen();

// ============================================================
//  SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000);

  Serial.println("\n--- [SYSTEM STARTUP] ---");

  // Solenoids (Active LOW: HIGH = Locked)
  pinMode(LOCK_TOP,      OUTPUT); digitalWrite(LOCK_TOP,      HIGH);
  pinMode(LOCK_PICKUP,   OUTPUT); digitalWrite(LOCK_PICKUP,   HIGH);
  pinMode(LOCK_RECEIVED, OUTPUT); digitalWrite(LOCK_RECEIVED, HIGH);

  // Inputs
  pinMode(BTN_RECEIVE,   INPUT_PULLUP);
  pinMode(BTN_PICKUP,    INPUT_PULLUP);
  pinMode(REED_TOP,      INPUT_PULLUP);
  pinMode(REED_PICKUP,   INPUT_PULLUP);
  pinMode(REED_RECEIVED, INPUT_PULLUP);
  pinMode(BUZZER_PIN,    OUTPUT);

  // Ultrasonic sensors
  pinMode(US_PLATFORM[0], OUTPUT); pinMode(US_PLATFORM[1], INPUT);
  pinMode(US_PICKUP[0],   OUTPUT); pinMode(US_PICKUP[1],   INPUT);
  pinMode(US_DROPOFF[0],  OUTPUT); pinMode(US_DROPOFF[1],  INPUT);
  digitalWrite(US_PLATFORM[0], LOW);
  digitalWrite(US_PICKUP[0],   LOW);
  digitalWrite(US_DROPOFF[0],  LOW);

  // Scanner serial: Arduino Uno TX → GPIO17 (ESP32 RX). TX=-1 frees GPIO18.
  Serial2.begin(9600, SERIAL_8N1, 17, -1);

  // TFT Display
  SPI.begin(TFT_SCK, TFT_MISO, TFT_MOSI, TFT_CS);
  tft.begin();
  tft.setRotation(3);

  // Servo
  platformServo.attach(SERVO_PIN);
  platformServo.write(90);

  // Network
  setupWiFi();
  setupSocketIO();

  showHomeScreen();
  printSerialMenu();
}

// ============================================================
//  MAIN LOOP
// ============================================================
void loop() {
  yield();
  socketIO.loop();        // Keep Socket.IO connection alive
  checkSerialCommands();

  switch (currentState) {

    // ── IDLE ──────────────────────────────────────────────
    case IDLE:
      if (digitalRead(BTN_RECEIVE) == LOW) {
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
          Serial.println("[FLOW] User selected: DROP OFF.");
          isReceivingMode = true;
          triggerBuzzer(1);
          changeState(WAITING_FOR_SCAN);
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) {
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.println("[FLOW] User selected: PICK UP.");
          isReceivingMode = false;
          triggerBuzzer(1);
          changeState(WAITING_FOR_SCAN);
        }
      }
      break;

    // ── WAITING FOR SCAN ──────────────────────────────────
    case WAITING_FOR_SCAN:
      if (!stateInitialized) {
        displayMessage("SCANNING", isReceivingMode ? "Mode: DROP OFF" : "Mode: PICK UP");
        Serial.println("[FLOW] Waiting for scan data on Serial2...");
        stateInitialized = true;
      }
      if (Serial2.available()) {
        String scanned = Serial2.readStringUntil('\n');
        scanned.trim();
        if (scanned.length() > 2) {
          currentTrackingId = scanned;
          String modeName = isReceivingMode ? "drop_off" : "pick_up";
          Serial.print("[FLOW] Scanned: "); Serial.println(scanned);
          displayMessage("VERIFYING...", "Please wait");

          // Send to server for verification (replaces local ID check)
          if (socketIO.isConnected()) {
            emitVerifyScan(scanned, modeName);
            scanResultReceived = false;
            scanResultValid    = false;
            changeState(VERIFYING_SCAN);
          } else {
            // Offline fallback: check local registered ID
            Serial.println("[WARN] Server offline — using local ID check.");
            String& registered = isReceivingMode ? registeredDropOff : registeredPickup;
            if (registered.length() == 0) {
              displayMessage("NOT REGISTERED", "Register ID first");
              triggerBuzzer(3);
              delay(3000);
              changeState(RESETTING);
            } else if (scanned == registered) {
              triggerBuzzer(2);
              changeState(UNLOCKING_ENTRY);
            } else {
              displayMessage("SCAN FAILED", "Please scan again");
              triggerBuzzer(3);
              delay(2000);
              displayMessage("SCANNING", isReceivingMode ? "Mode: DROP OFF" : "Mode: PICK UP");
            }
          }
        }
      }
      break;

    // ── VERIFYING SCAN (waiting for server scanResult) ────
    case VERIFYING_SCAN:
      if (!stateInitialized) {
        stateStartTime = millis();
        stateInitialized = true;
      }

      if (scanResultReceived) {
        if (scanResultValid) {
          Serial.print("[FLOW] Server APPROVED ID: "); Serial.println(currentTrackingId);
          triggerBuzzer(2);
          changeState(UNLOCKING_ENTRY);
        } else {
          Serial.print("[FLOW] Server REJECTED ID: "); Serial.println(currentTrackingId);
          displayMessage("SCAN FAILED", "Not authorized");
          triggerBuzzer(3);
          delay(2000);
          changeState(RESETTING);
        }
      } else if (millis() - stateStartTime > 8000) {
        // Timeout: 8 seconds
        Serial.println("[FLOW] Server verification timed out.");
        displayMessage("TIMEOUT", "Server not responding");
        triggerBuzzer(3);
        delay(2000);
        changeState(RESETTING);
      }
      break;

    // ── UNLOCKING ENTRY ───────────────────────────────────
    case UNLOCKING_ENTRY:
      {
        if (!stateInitialized) {
          digitalWrite(LOCK_TOP, LOW);  // UNLOCK
          lockTopOpen = true;
          emitDoorState();             // 🔔 notify app: door is now unlocked
          displayMessage("UNLOCKED", "Please Open Door");
          doorWasOpened   = false;
          stateInitialized = true;
          triggerBuzzer(2);
          Serial.println("[FLOW] Lock: UNLOCKED. Waiting for Reed (1=Open).");
        }

        if (digitalRead(REED_TOP) == 1) {
          if (!doorWasOpened) {
            Serial.println("[FLOW] Reed: Door OPEN.");
            triggerBuzzer(1);
            doorWasOpened = true;
          }
        }

        if (doorWasOpened) {
          digitalWrite(LOCK_TOP, HIGH);  // LOCK
          lockTopOpen = false;
          emitDoorState();              // 🔔 notify app: door is now locked
          Serial.println("[FLOW] Door opened → Lock ENGAGED. Proceeding.");
          triggerBuzzer(1);
          changeState(WAITING_PLACEMENT_STABLE);
        }
      }
      break;

    // ── WAITING FOR PLACEMENT ─────────────────────────────
    case WAITING_PLACEMENT_STABLE:
      {
        if (!stateInitialized) {
          displayMessage("PLACEMENT", "Place on Tray");
          Serial.println("[FLOW] Waiting for parcel on platform...");
          stateInitialized = true;
        }

        float d = getDistance(US_PLATFORM);
        if (d > 1.0 && d < 18.0) {
          Serial.println("[FLOW] Parcel detected. Tilting platform...");
          triggerBuzzer(2);
          changeState(TILTING_PLATFORM);
        }
      }
      break;

    // ── TILTING PLATFORM ──────────────────────────────────
    case TILTING_PLATFORM:
      displayMessage("SORTING", isReceivingMode ? "To DROP OFF Bin" : "To PICK UP Bin");
      Serial.println("[FLOW] Action: Tilting Tray...");
      triggerBuzzer(1);
      moveServoSmoothly(90, isReceivingMode ? 0 : 180);
      delay(2000);
      moveServoSmoothly(platformServo.read(), 90);
      changeState(CONFIRMING_DROP);
      break;

    // ── CONFIRMING DROP ───────────────────────────────────
    case CONFIRMING_DROP:
      {
        float binDist = isReceivingMode ? getDistance(US_DROPOFF) : getDistance(US_PICKUP);
        String binName = isReceivingMode ? "DROP OFF" : "PICKUP";
        Serial.print("[BIN CHECK] "); Serial.print(binName);
        Serial.print(" bin dist: ");
        Serial.println(binDist < 900 ? String(binDist, 1) + "cm" : "OOR");

        String newStatus = isReceivingMode ? "delivered" : "retrieved";
        String modeStr   = isReceivingMode ? "drop_off"  : "pick_up";

        if (binDist < 25.0) {
          displayMessage("SUCCESS", "Stored Safely");
          Serial.println("[FLOW] Parcel confirmed in bin.");
          triggerBuzzer(2);
          // Notify backend → updates DB and pushes to mobile app
          if (currentTrackingId.length() > 0) {
            emitStatusUpdate(currentTrackingId, newStatus, modeStr);
          }
        } else {
          displayMessage("DONE", "Check Bin");
          Serial.println("[FLOW] WARNING: Bin sensor did not detect parcel!");
          triggerBuzzer(3);
        }
        delay(3000);
        changeState(RESETTING);
      }
      break;

    // ── RESETTING ─────────────────────────────────────────
    case RESETTING:
      triggerBuzzer(1);
      digitalWrite(LOCK_TOP,      HIGH);
      digitalWrite(LOCK_PICKUP,   HIGH);
      digitalWrite(LOCK_RECEIVED, HIGH);
      lockTopOpen = false; lockPickupOpen = false; lockReceivedOpen = false;
      emitDoorState();  // 🔔 notify app: all doors locked on reset
      platformServo.write(90);
      currentTrackingId  = "";
      scanResultReceived = false;
      changeState(IDLE);
      showHomeScreen();
      printSerialMenu();
      Serial.println("--- [FLOW] SYSTEM RESET TO IDLE ---");
      break;
  }
}

// ============================================================
//  WIFI SETUP
// ============================================================
void setupWiFi() {
  Serial.print("[WiFi] Connecting to: ");
  Serial.println(WIFI_SSID);

  tft.fillScreen(COLOR_BG);
  tft.setCursor(10, 60); tft.setTextSize(2); tft.setTextColor(COLOR_ACCENT);
  tft.println("Connecting WiFi...");

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.print("[WiFi] Connected! IP: ");
    Serial.println(WiFi.localIP());
    tft.fillScreen(COLOR_BG);
    tft.setCursor(10, 60); tft.setTextColor(COLOR_GREEN);
    tft.println("WiFi Connected!");
    tft.setCursor(10, 90); tft.setTextSize(1); tft.setTextColor(COLOR_TEXT);
    tft.println(WiFi.localIP().toString());
    delay(1500);
  } else {
    Serial.println();
    Serial.println("[WiFi] FAILED to connect. Running offline.");
    tft.fillScreen(COLOR_BG);
    tft.setCursor(10, 60); tft.setTextColor(COLOR_RED);
    tft.println("WiFi FAILED");
    tft.setCursor(10, 90); tft.setTextSize(1); tft.setTextColor(COLOR_TEXT);
    tft.println("Running in offline mode");
    delay(2000);
  }
}

// ============================================================
//  SOCKET.IO SETUP
// ============================================================
void setupSocketIO() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WS] Skipping Socket.IO — no WiFi.");
    return;
  }

  Serial.print("[WS] Connecting to server: ");
  Serial.print(SERVER_HOST); Serial.print(":"); Serial.println(SERVER_PORT);

  // Use beginSSL() for Render.com (WSS). The library will auto-reconnect
  // in the background via socketIO.loop() in the main loop — no blocking wait.
  // This is important for Render.com free tier which can take 30-60s to wake up.
  socketIO.onEvent(socketIOEvent);
  socketIO.beginSSL(SERVER_HOST, SERVER_PORT, SERVER_PATH);
  socketIO.setReconnectInterval(5000);  // Retry every 5 seconds until connected

  Serial.println("[WS] Socket.IO initiated — connecting in background...");
  Serial.println("[WS] (Render.com may take up to 60s on cold start)");
}

// ============================================================
//  SOCKET.IO EVENT HANDLER
// ============================================================
void socketIOEvent(socketIOmessageType_t type, uint8_t* payload, size_t length) {
  switch (type) {

    case sIOtype_CONNECT:
      Serial.println("[WS] Socket.IO connected.");
      // Identify as hardware device to the server
      socketIO.send(sIOtype_EVENT, "[\"join\",\"esp32_device\"]");
      break;

    case sIOtype_DISCONNECT:
      Serial.println("[WS] Socket.IO disconnected.");
      break;

    case sIOtype_EVENT: {
      // Parse the incoming event array: ["eventName", { ...data... }]
      String msg = String((char*)payload, length);
      Serial.print("[WS] Event: "); Serial.println(msg);

      StaticJsonDocument<512> doc;
      DeserializationError err = deserializeJson(doc, payload, length);
      if (err) {
        Serial.print("[WS] JSON parse error: "); Serial.println(err.c_str());
        break;
      }

      String eventName = doc[0].as<String>();

      if (eventName == "scanResult") {
        // Server responded to our verifyScan request
        String data;
        serializeJson(doc[1], data);
        handleScanResult(data);

      } else if (eventName == "registerTracking") {
        // Mobile app pushed a tracking ID to register on the hardware
        String data;
        serializeJson(doc[1], data);
        handleRegisterTracking(data);

      } else if (eventName == "controlDoor") {
        // Mobile app or admin requested manual door control
        // Payload: { type: "top"|"pickup"|"received", action: "open"|"close" }
        String data;
        serializeJson(doc[1], data);
        handleControlDoor(data);

      } else if (eventName == "getStatus") {
        // App requested current door states + parcel sensor readings
        emitDoorState();
      }
      break;
    }

    case sIOtype_ERROR:
      Serial.println("[WS] Socket.IO error.");
      break;

    default:
      break;
  }
}

// ============================================================
//  EMIT: Send verifyScan to server
// ============================================================
void emitVerifyScan(const String& trackingId, const String& mode) {
  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("verifyScan");
  JsonObject data = arr.createNestedObject();
  data["trackingId"] = trackingId;
  data["mode"]       = mode;

  String output;
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output.c_str());
  Serial.print("[WS] Emitted verifyScan: "); Serial.println(output);
}

// ============================================================
//  EMIT: Send statusUpdate to server (→ updates DB → notifies app)
// ============================================================
void emitStatusUpdate(const String& trackingId, const String& status, const String& mode) {
  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("statusUpdate");
  JsonObject data = arr.createNestedObject();
  data["trackingId"] = trackingId;
  data["status"]     = status;
  data["mode"]       = mode;

  String output;
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output.c_str());
  Serial.print("[WS] Emitted statusUpdate: "); Serial.println(output);
}

// ============================================================
//  EMIT: Broadcast all door/lock states + parcel sensor to app
//  This is what the Flutter app's doorStateUpdates stream receives.
//  Mirrors what ESP32_DoorControl.ino's GET /status endpoint returned,
//  but via Socket.IO instead of HTTP.
// ============================================================
void emitDoorState() {
  // Read parcel detection from the platform ultrasonic sensor
  float platformDist = getDistance(US_PLATFORM);
  bool parcelOnPlatform = (platformDist > 1.0 && platformDist < 18.0);
  bool parcelInDropOff  = (getDistance(US_DROPOFF) < 25.0);
  bool parcelInPickup   = (getDistance(US_PICKUP)  < 25.0);

  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("doorStateUpdate");
  JsonObject data = arr.createNestedObject();
  data["parcelDoorOpen"]    = lockTopOpen;       // parcel entry lock
  data["pickupDoorOpen"]    = lockPickupOpen;    // pickup bin lock
  data["receivedDoorOpen"]  = lockReceivedOpen;  // received bin lock
  data["parcelDetected"]    = parcelOnPlatform;  // parcel on tray
  data["parcelInDropOff"]   = parcelInDropOff;   // parcel in drop-off bin
  data["parcelInPickup"]    = parcelInPickup;    // parcel in pickup bin
  data["systemState"]       = (int)currentState; // current FSM state index

  String output;
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output.c_str());
  Serial.print("[WS] Emitted doorStateUpdate: "); Serial.println(output);
}

// ============================================================
//  HANDLE: controlDoor from server (app-triggered manual control)
//  Replaces ESP32_DoorControl.ino's POST /door HTTP endpoint.
//  Payload: { "type": "top"|"pickup"|"received", "action": "open"|"close" }
//  Use for admin overrides / emergency access only — does NOT
//  change the state machine; it directly drives the solenoid.
// ============================================================
void handleControlDoor(const String& payload) {
  StaticJsonDocument<256> doc;
  deserializeJson(doc, payload);

  String type   = doc["type"].as<String>();    // "top", "pickup", "received"
  String action = doc["action"].as<String>();  // "open", "close"

  Serial.print("[DOOR] Manual control: "); Serial.print(type);
  Serial.print(" → "); Serial.println(action);

  bool isOpen = (action == "open");

  if (type == "top") {
    digitalWrite(LOCK_TOP, isOpen ? LOW : HIGH);
    lockTopOpen = isOpen;
  } else if (type == "pickup") {
    digitalWrite(LOCK_PICKUP, isOpen ? LOW : HIGH);
    lockPickupOpen = isOpen;
  } else if (type == "received") {
    digitalWrite(LOCK_RECEIVED, isOpen ? LOW : HIGH);
    lockReceivedOpen = isOpen;
  } else {
    Serial.println("[DOOR] Unknown door type. Use: top, pickup, received");
    return;
  }

  String displayTitle = isOpen ? "UNLOCKED" : "LOCKED";
  String displayMsg   = type + " door " + action + "d";
  displayMessage(displayTitle.c_str(), displayMsg.c_str());
  triggerBuzzer(isOpen ? 2 : 1);

  // Immediately broadcast the new state to the app
  emitDoorState();
}

// ============================================================
//  HANDLE: scanResult from server
// ============================================================
void handleScanResult(const String& payload) {
  StaticJsonDocument<256> doc;
  deserializeJson(doc, payload);

  bool valid = doc["valid"].as<bool>();
  Serial.print("[WS] scanResult → valid: "); Serial.println(valid ? "YES" : "NO");

  scanResultValid    = valid;
  scanResultReceived = true;
  // The VERIFYING_SCAN state will react to these flags on the next loop()
}

// ============================================================
//  HANDLE: registerTracking from server (relayed from mobile app)
// ============================================================
void handleRegisterTracking(const String& payload) {
  StaticJsonDocument<256> doc;
  deserializeJson(doc, payload);

  String trackingId = doc["trackingId"].as<String>();
  String mode       = doc["mode"].as<String>();  // "drop_off" or "pick_up"

  if (mode == "drop_off") {
    registeredDropOff = trackingId;
    Serial.print("[REG] Drop Off ID registered via app: "); Serial.println(registeredDropOff);
    displayMessage("ID REGISTERED", ("Drop Off: " + trackingId.substring(0, 10)).c_str());
  } else if (mode == "pick_up") {
    registeredPickup = trackingId;
    Serial.print("[REG] Pick Up ID registered via app: "); Serial.println(registeredPickup);
    displayMessage("ID REGISTERED", ("Pick Up: " + trackingId.substring(0, 10)).c_str());
  } else {
    Serial.print("[REG] Unknown mode: "); Serial.println(mode);
    return;
  }

  triggerBuzzer(1);
  delay(1500);
  if (currentState == IDLE) showHomeScreen();
}

// ============================================================
//  UTILS
// ============================================================
float getDistance(const int pins[]) {
  digitalWrite(pins[0], LOW);
  delayMicroseconds(2);
  digitalWrite(pins[0], HIGH);
  delayMicroseconds(10);
  digitalWrite(pins[0], LOW);
  long dur = pulseIn(pins[1], HIGH, 30000);
  if (dur == 0) return 999.0;
  return (dur * 0.034) / 2.0;
}

void checkSerialCommands() {
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    char cmd = toupper(input.charAt(0));

    if (cmd == 'S') {
      changeState(RESETTING);
    } else if (cmd == 'U') {
      digitalWrite(LOCK_TOP, LOW);
      digitalWrite(LOCK_PICKUP, LOW);
      digitalWrite(LOCK_RECEIVED, LOW);
      Serial.println("[MANUAL] Override: All Solenoids UNLOCKED.");
    } else if (cmd == 'D') {
      Serial.println("[DIAG] === Ultrasonic Sensor Diagnostic ===");
      float d1 = getDistance(US_PLATFORM);
      float d2 = getDistance(US_PICKUP);
      float d3 = getDistance(US_DROPOFF);
      Serial.print("  US1 Platform : "); Serial.println(d1 < 900 ? String(d1,1)+"cm" : "OUT_OF_RANGE");
      Serial.print("  US2 Pickup   : "); Serial.println(d2 < 900 ? String(d2,1)+"cm" : "OUT_OF_RANGE");
      Serial.print("  US3 DropOff  : "); Serial.println(d3 < 900 ? String(d3,1)+"cm" : "OUT_OF_RANGE");
      Serial.println("[DIAG] Done.");
    } else if (cmd == 'R') {
      // Format: R1:<tracking_id>  or  R2:<tracking_id>
      if (input.length() > 3 && input.charAt(2) == ':') {
        char slot  = input.charAt(1);
        String newId = input.substring(3);
        newId.trim();
        if (slot == '1') {
          registeredDropOff = newId;
          Serial.print("[REG] Drop Off ID (manual): "); Serial.println(registeredDropOff);
        } else if (slot == '2') {
          registeredPickup = newId;
          Serial.print("[REG] Pick Up ID (manual): "); Serial.println(registeredPickup);
        } else {
          Serial.println("[REG] Invalid slot. Use R1:<id> or R2:<id>");
        }
      } else {
        Serial.println("[REG] Format: R1:<tracking_id> or R2:<tracking_id>");
      }
    } else if (cmd == 'V') {
      Serial.println("[REG] === Registered IDs ===");
      Serial.print("  Drop Off : "); Serial.println(registeredDropOff.length() ? registeredDropOff : "(none)");
      Serial.print("  Pick Up  : "); Serial.println(registeredPickup.length()  ? registeredPickup  : "(none)");
      Serial.print("  WiFi     : "); Serial.println(WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString() : "Not connected");
      Serial.print("  Server   : "); Serial.println(socketIO.isConnected() ? "Connected" : "Disconnected");
    } else if (cmd == 'W') {
      Serial.println("[DIAG] === Network Status ===");
      Serial.print("  WiFi SSID  : "); Serial.println(WiFi.SSID());
      Serial.print("  WiFi IP    : "); Serial.println(WiFi.localIP());
      Serial.print("  WiFi RSSI  : "); Serial.print(WiFi.RSSI()); Serial.println(" dBm");
      Serial.print("  Server     : wss://"); Serial.print(SERVER_HOST); Serial.print(":"); Serial.println(SERVER_PORT);
      Serial.print("  Socket.IO  : "); Serial.println(socketIO.isConnected() ? "Connected" : "Disconnected");
    }
  }
}

void printSerialMenu() {
  Serial.println();
  Serial.println("==========================================");
  Serial.println("     SMART PARCEL DROPBOX SYSTEM");
  Serial.println("==========================================");
  Serial.println("  [BTN1] Drop Off     [BTN2] Pick Up");
  Serial.println("------------------------------------------");
  Serial.println("  S=Reset  | U=Unlock All | D=US Diag");
  Serial.println("  V=View IDs & Status   | W=Network Info");
  Serial.println("  R1:<id> = Register Drop Off ID (offline)");
  Serial.println("  R2:<id> = Register Pick Up ID  (offline)");
  Serial.println("  IDs auto-registered via mobile app (online)");
  Serial.println("==========================================");
  Serial.println();
}

void changeState(SystemState newState) {
  currentState     = newState;
  stateStartTime   = millis();
  stateInitialized = false;
  tft.fillScreen(COLOR_BG);
}

void moveServoSmoothly(int from, int to) {
  int step = (from < to) ? 1 : -1;
  for (int i = from; i != to; i += step) {
    platformServo.write(i);
    delay(15);
  }
}

void triggerBuzzer(int beeps) {
  for (int i = 0; i < beeps; i++) {
    digitalWrite(BUZZER_PIN, HIGH); delay(100);
    digitalWrite(BUZZER_PIN, LOW);  delay(100);
  }
}

void displayMessage(const char* title, const char* msg) {
  tft.fillRect(0, 50, 320, 100, COLOR_BG);
  tft.setCursor(20, 80);  tft.setTextSize(3); tft.setTextColor(COLOR_ACCENT); tft.println(title);
  tft.setCursor(20, 120); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);   tft.println(msg);
}

void displayMessageStr(const String& title, const String& msg) {
  displayMessage(title.c_str(), msg.c_str());
}

void showHomeScreen() {
  tft.fillScreen(COLOR_BG);
  tft.setTextColor(COLOR_ACCENT); tft.setTextSize(2);
  tft.setCursor(40, 40); tft.println("Smart Parcel Dropbox");
  tft.drawFastHLine(20, 70, 280, COLOR_ACCENT);
  tft.setTextColor(COLOR_TEXT);
  tft.setCursor(20, 110); tft.println("1. Drop Off | 2. Pick up");

  // WiFi/server status indicator at bottom
  tft.setTextSize(1);
  tft.setCursor(10, 210);
  if (WiFi.status() == WL_CONNECTED) {
    tft.setTextColor(COLOR_GREEN);
    tft.print("WiFi: ");
    tft.print(WiFi.localIP());
    tft.print(socketIO.isConnected() ? "  ● Online" : "  ○ Server offline");
  } else {
    tft.setTextColor(COLOR_RED);
    tft.print("WiFi: Not connected (offline mode)");
  }

  printSerialMenu();
}