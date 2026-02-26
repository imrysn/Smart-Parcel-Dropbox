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
#define DEBUG_WS      false // Toggle for verbose Socket.IO logs
#define DEBUG_SERIAL  true

#include <WiFi.h>
#include <SocketIOclient.h>
#include <ArduinoJson.h>

// ============================================================
//  CONFIGURATION — Credentials live in config.h (NOT committed)
// ============================================================
#include "config.h"  // ⚠ Add config.h to .gitignore — contains WiFi password

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
#define COLOR_ACCENT  0x3DFF  // Cyan
#define COLOR_BLUE    0x001F  // Primary Blue
#define COLOR_PURPLE  0x780F  // Deep Purple
#define COLOR_GREEN   0x07E0
#define COLOR_RED     0xF800
#define COLOR_GREY    0x7BEF
#define COLOR_GOLD    0xFDE0

// ============================================================
//  STATE MACHINE
// ============================================================
enum SystemState {
  IDLE,
  // ── Pick Up sub-menu states ─────────────────────────────────
  SELECTING_PICKUP_TYPE,    // ATM sub-menu: [Owner | Rider]
  OWNER_SELECTING_MODE,     // ATM sub-menu: [Single | Multiple]
  OWNER_SCANNING,           // Owner scans tracking ID(s) to register
  OWNER_ADD_MORE_PROMPT,    // ATM prompt: [Add More | Done]
  RIDER_VERIFYING,          // Rider scans their QR → server check
  RIDER_DOOR_OPEN,          // Pickup bin door unlocked, wait for open+close
  RIDER_SCANNING_PARCELS,   // Rider scans each parcel → status=done
  RIDER_PICKUP_PROMPT,      // ATM prompt: [Pick Up More | Done]
  // ── Drop Off states (unchanged) ─────────────────────────────
  WAITING_FOR_SCAN,
  VERIFYING_SCAN,
  UNLOCKING_ENTRY,
  WAITING_PLACEMENT_STABLE,
  TILTING_PLATFORM,
  CONFIRMING_DROP,
  RESETTING
};

SystemState currentState = IDLE;
bool isReceivingMode     = true;
bool isRiderMode         = false;  // true = Rider Collect flow
bool isMultiMode         = false;  // true = Owner multiple parcels
int  scannedCount        = 0;      // parcels processed in current session
bool stateInitialized    = false;
bool doorWasOpened       = false;
unsigned long stateStartTime     = 0;
unsigned long stabilityStartTime = 0;
unsigned long lastDebugTime      = 0;

// Non-blocking action delay helper
unsigned long actionDelayStart  = 0;
bool          actionDelayActive = false;
SystemState   pendingNextState  = IDLE;

// Rider verification result
bool riderVerifyReceived = false;
bool riderVerifyValid    = false;

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
void emitVerifyRider(const String& riderId);
void emitRegisterOwnerPickup(const String& trackingId);
void emitStatusUpdate(const String& trackingId, const String& status, const String& mode);
void emitDoorState();
void handleRegisterTracking(const String& payload);
void handleScanResult(const String& payload);
void handleRiderVerifyResult(const String& payload);
void handleControlDoor(const String& payload);
float getDistance(const int pins[]);
void checkSerialCommands();
void printSerialMenu();
void showHomeScreen();
void drawStatusBar();
void drawScannerBg();
void drawPickupSelectScreen();
void drawOwnerModeScreen();
void drawAddMorePrompt();
void drawRiderScanIdScreen();
void drawRiderScanParcelScreen();
void drawRiderPickupMorePrompt();
void drawIconLock(int x, int y, uint16_t color, bool open);
void drawIconBox(int x, int y, uint16_t color);
void drawIconCheck(int x, int y, uint16_t color);
void drawIconX(int x, int y, uint16_t color);
void drawWiFiSignal(int x, int y, uint16_t color);
void reinitTFT();

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

  // TFT Display Hardware Reset
  pinMode(TFT_RST, OUTPUT);
  digitalWrite(TFT_RST, LOW);
  delay(100);
  digitalWrite(TFT_RST, HIGH);
  delay(150);

  SPI.begin(TFT_SCK, TFT_MISO, TFT_MOSI, TFT_CS);
  tft.begin();
  tft.setRotation(3);
  tft.fillScreen(COLOR_BG);

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
          isRiderMode     = false;
          triggerBuzzer(1);
          changeState(WAITING_FOR_SCAN);
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) {
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.println("[FLOW] User selected: PICK UP → showing sub-menu.");
          isReceivingMode = false;
          triggerBuzzer(1);
          changeState(SELECTING_PICKUP_TYPE);
        }
      }
      break;

    // ── SELECTING PICKUP TYPE (ATM: Owner | Rider) ────────
    case SELECTING_PICKUP_TYPE:
      if (!stateInitialized) {
        drawPickupSelectScreen();
        Serial.println("[FLOW] Sub-menu: Waiting for Owner or Rider selection.");
        stateInitialized = true;
      }
      if (digitalRead(BTN_RECEIVE) == LOW) {          // Left = Owner
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
          Serial.println("[FLOW] Sub-menu: OWNER selected.");
          isRiderMode = false;
          triggerBuzzer(1);
          changeState(OWNER_SELECTING_MODE);
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) {   // Right = Rider
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.println("[FLOW] Sub-menu: RIDER selected.");
          isRiderMode = true;
          triggerBuzzer(2);
          changeState(RIDER_VERIFYING);
        }
      }
      break;

    // ── OWNER SELECTING MODE (ATM: Single | Multiple) ─────
    case OWNER_SELECTING_MODE:
      if (!stateInitialized) {
        drawOwnerModeScreen();
        Serial.println("[FLOW] Owner sub-menu: Single or Multiple?");
        stateInitialized = true;
      }
      if (digitalRead(BTN_RECEIVE) == LOW) {          // Left = Single
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
          Serial.println("[FLOW] Owner Mode: SINGLE pick up.");
          isMultiMode  = false;
          scannedCount = 0;
          triggerBuzzer(1);
          changeState(OWNER_SCANNING);
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) {   // Right = Multiple
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.println("[FLOW] Owner Mode: MULTIPLE pick up.");
          isMultiMode  = true;
          scannedCount = 0;
          triggerBuzzer(2);
          changeState(OWNER_SCANNING);
        }
      }
      break;

    // ── OWNER SCANNING (register tracking ID) ─────────────
    case OWNER_SCANNING:
      if (!stateInitialized) {
        tft.fillScreen(COLOR_BG);
        drawStatusBar();
        drawScannerBg();
        tft.setCursor(20, 185); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
        if (isMultiMode) {
          String lbl = "Multi-Scan #" + String(scannedCount + 1);
          tft.print(lbl);
        } else {
          tft.print("Scan Waybill QR");
        }
        Serial.println("[FLOW] Owner: Waiting for tracking ID scan...");
        stateInitialized = true;
      }
      if (Serial2.available()) {
        String scanned = Serial2.readStringUntil('\n');
        scanned.trim();
        if (scanned.length() > 2 && scanned.indexOf('[') == -1 && scanned.indexOf(']') == -1) {
          currentTrackingId = scanned;
          scannedCount++;
          Serial.print("[FLOW] Owner scanned ID #"); Serial.print(scannedCount);
          Serial.print(": "); Serial.println(scanned);
          String label = "#" + String(scannedCount) + " " + scanned.substring(0, 10);
          displayMessage("REGISTERED", label.c_str());
          triggerBuzzer(2);
          emitRegisterOwnerPickup(scanned);
          pendingNextState  = isMultiMode ? OWNER_ADD_MORE_PROMPT : RESETTING;
          actionDelayStart  = millis();
          actionDelayActive = true;
        }
      }
      if (actionDelayActive && millis() - actionDelayStart >= 1500) {
        actionDelayActive = false;
        changeState(pendingNextState);
        pendingNextState = IDLE;
      }
      break;

    // ── OWNER ADD MORE PROMPT (ATM: Add More | Done) ──────
    case OWNER_ADD_MORE_PROMPT:
      if (!stateInitialized) {
        drawAddMorePrompt();
        Serial.print("[FLOW] Owner: Add more parcel? (registered so far: ");
        Serial.print(scannedCount); Serial.println(")");
        stateInitialized = true;
      }
      if (digitalRead(BTN_RECEIVE) == LOW) {          // Left = Add More
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
          Serial.println("[FLOW] Owner: Adding more parcels.");
          triggerBuzzer(1);
          changeState(OWNER_SCANNING);
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) {   // Right = Done
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.print("[FLOW] Owner: Done. Total registered: "); Serial.println(scannedCount);
          triggerBuzzer(1);
          changeState(RESETTING);
        }
      }
      break;

    // ── RIDER VERIFYING (scan rider QR → server check) ────
    case RIDER_VERIFYING:
      if (!stateInitialized) {
        drawRiderScanIdScreen();
        riderVerifyReceived = false;
        riderVerifyValid    = false;
        stateStartTime      = millis();
        stateInitialized    = true;
        Serial.println("[FLOW] Rider: Waiting for Rider QR scan...");
      }
      if (Serial2.available() && !actionDelayActive) {
        String riderId = Serial2.readStringUntil('\n');
        riderId.trim();
        if (riderId.length() > 2 && riderId.indexOf('[') == -1 && riderId.indexOf(']') == -1) {
          Serial.print("[FLOW] Rider ID scanned: "); Serial.println(riderId);
          displayMessage("VERIFYING...", "Please wait");
          if (socketIO.isConnected()) {
            emitVerifyRider(riderId);
          } else {
            Serial.println("[WARN] Rider verify: offline — cannot verify.");
            displayMessage("OFFLINE", "No server");
            triggerBuzzer(3);
            pendingNextState  = RIDER_VERIFYING;
            actionDelayStart  = millis();
            actionDelayActive = true;
          }
        }
      }
      if (riderVerifyReceived && !actionDelayActive) {
        riderVerifyReceived = false;
        if (riderVerifyValid) {
          Serial.println("[FLOW] Rider: VERIFIED.");
          displayMessage("VERIFIED", "Opening Bin...");
          triggerBuzzer(2);
          pendingNextState  = RIDER_DOOR_OPEN;
        } else {
          Serial.println("[FLOW] Rider: NOT AUTHORIZED.");
          displayMessage("REJECTED", "Retry Scan");
          triggerBuzzer(3);
          pendingNextState  = RIDER_VERIFYING;
        }
        actionDelayStart  = millis();
        actionDelayActive = true;
      }
      if (actionDelayActive && millis() - actionDelayStart >= 2000) {
        actionDelayActive = false;
        changeState(pendingNextState);
        pendingNextState = IDLE;
      }
      break;

    // ── RIDER DOOR OPEN (unlock bin, wait open+close) ──────
    case RIDER_DOOR_OPEN:
      if (!stateInitialized) {
        digitalWrite(LOCK_PICKUP, LOW);   // Unlock pickup bin
        lockPickupOpen = true;
        emitDoorState();
        displayMessage("DOOR OPEN", "Collect Parcels");
        doorWasOpened    = false;
        stateInitialized = true;
        scannedCount     = 0;
        triggerBuzzer(2);
        Serial.println("[FLOW] Rider: Pickup bin UNLOCKED.");
      }
      if (digitalRead(REED_PICKUP) == 1 && !doorWasOpened) {
        Serial.println("[FLOW] Rider: Bin door OPENED.");
        doorWasOpened = true;
        triggerBuzzer(1);
        drawRiderScanParcelScreen();
      }
      if (doorWasOpened && digitalRead(REED_PICKUP) == 0) {
        digitalWrite(LOCK_PICKUP, HIGH);  // Re-lock
        lockPickupOpen = false;
        emitDoorState();
        Serial.println("[FLOW] Rider: Bin door CLOSED → Locked.");
        triggerBuzzer(1);
        changeState(RIDER_SCANNING_PARCELS);
      }
      break;

    // ── RIDER SCANNING PARCELS ─────────────────────────────
    case RIDER_SCANNING_PARCELS:
      if (!stateInitialized) {
        drawRiderScanParcelScreen();
        Serial.println("[FLOW] Rider: Waiting for parcel scan...");
        stateInitialized = true;
      }
      if (Serial2.available() && !actionDelayActive) {
        String scanned = Serial2.readStringUntil('\n');
        scanned.trim();
        if (scanned.length() > 2 && scanned.indexOf('[') == -1 && scanned.indexOf(']') == -1) {
          scannedCount++;
          Serial.print("[FLOW] Rider scanned parcel #"); Serial.print(scannedCount);
          Serial.print(": "); Serial.println(scanned);
          emitStatusUpdate(scanned, "done", "rider_collect");
          String label = "#" + String(scannedCount) + " " + scanned.substring(0, 10);
          displayMessage("SCANNED", label.c_str());
          triggerBuzzer(1);
          pendingNextState  = RIDER_PICKUP_PROMPT;
          actionDelayStart  = millis();
          actionDelayActive = true;
        }
      }
      if (actionDelayActive && millis() - actionDelayStart >= 1000) {
        actionDelayActive = false;
        changeState(pendingNextState);
        pendingNextState = IDLE;
      }
      break;

    // ── RIDER PICKUP PROMPT (ATM: Pick Up More | Done) ────
    case RIDER_PICKUP_PROMPT:
      if (!stateInitialized) {
        drawRiderPickupMorePrompt();
        Serial.print("[FLOW] Rider: Parcels scanned so far: "); Serial.println(scannedCount);
        stateInitialized = true;
      }
      if (digitalRead(BTN_RECEIVE) == LOW) {         // Left = Pick Up More
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
          Serial.println("[FLOW] Rider: Scanning more parcels.");
          triggerBuzzer(1);
          changeState(RIDER_SCANNING_PARCELS);
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) {  // Right = Done
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.print("[FLOW] Rider: DONE. Total parcels: "); Serial.println(scannedCount);
          triggerBuzzer(1);
          changeState(RESETTING);
        }
      }
      break;

    // ── WAITING FOR SCAN ──────────────────────────────────
    case WAITING_FOR_SCAN:
      if (!stateInitialized) {
        tft.fillScreen(COLOR_BG);
        drawStatusBar();
        drawScannerBg();
        tft.setCursor(40, 190); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
        tft.print(isReceivingMode ? "Mode: DROP OFF" : "Mode: PICK UP");
        Serial.println("[FLOW] Waiting for scan data on Serial2...");
        stateInitialized = true;
      }
      if (Serial2.available()) {
        String scanned = Serial2.readStringUntil('\n');
        scanned.trim();
        // Sanity check: Barcodes should not contain debug symbols like [ or ]
        if (scanned.length() > 2 && scanned.indexOf('[') == -1 && scanned.indexOf(']') == -1) {
          currentTrackingId = scanned;
          String modeName = isReceivingMode ? "drop_off" : "pick_up";
          Serial.print("[FLOW] Scanned: "); Serial.println(scanned);

          // Phase 9: Hybrid Verification (Local-First)
          String& localID = isReceivingMode ? registeredDropOff : registeredPickup;
          
          if (localID.length() > 0 && scanned == localID) {
            Serial.println("[FLOW] LOCAL AUTHORIZATION: Match found in manual registry.");
            displayMessage("VALID ID", "LOCAL AUTH");
            triggerBuzzer(2);
            // Notify server if connected for logging, but don't wait for response
            if (socketIO.isConnected()) {
              emitStatusUpdate(scanned, isReceivingMode ? "delivered" : "retrieved", modeName);
            }
            // Non-blocking 1s display pause before unlocking
            pendingNextState  = UNLOCKING_ENTRY;
            actionDelayStart  = millis();
            actionDelayActive = true;
          } 
          else if (socketIO.isConnected()) {
            // No local match, but server is available -> Fallback to Online Check
            Serial.println("[FLOW] No local match. Requesting server verification...");
            displayMessage("VERIFYING...", "Please wait");
            emitVerifyScan(scanned, modeName);
            scanResultReceived = false;
            scanResultValid    = false;
            changeState(VERIFYING_SCAN);
          } 
          else {
            // Offline and NO local match
            Serial.println("[WARN] Offline and No local ID match.");
            displayMessage("INVALID ID", "RETRY SCAN");
            triggerBuzzer(3);
            currentTrackingId = ""; 
            pendingNextState  = WAITING_FOR_SCAN;
            actionDelayStart  = millis();
            actionDelayActive = true;
          }
        }
      }
      // Non-blocking delay: 1s pause → UNLOCKING_ENTRY (success), 2s → retry (fail/offline)
      if (actionDelayActive) {
        unsigned long pauseMs = (pendingNextState == UNLOCKING_ENTRY) ? 1000 : 2000;
        if (millis() - actionDelayStart >= pauseMs) {
          actionDelayActive = false;
          if (pendingNextState == WAITING_FOR_SCAN) {
            // Redraw scanner UI before looping back
            tft.fillScreen(COLOR_BG);
            drawStatusBar();
            drawScannerBg();
            tft.setCursor(40, 190); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
            tft.print(isReceivingMode ? "Mode: DROP OFF" : "Mode: PICK UP");
            pendingNextState = IDLE;  // reset flag, stay in WAITING_FOR_SCAN
          } else {
            changeState(pendingNextState);
            pendingNextState = IDLE;
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

      if (scanResultReceived && !actionDelayActive) {
        if (scanResultValid) {
          Serial.print("[FLOW] Server APPROVED ID: "); Serial.println(currentTrackingId);
          displayMessage("VALID ID", "Authorized Access");
          triggerBuzzer(2);
          // Non-blocking 1s display pause before unlocking
          pendingNextState  = UNLOCKING_ENTRY;
          actionDelayStart  = millis();
          actionDelayActive = true;
        } else {
          Serial.print("[FLOW] Server REJECTED ID: "); Serial.println(currentTrackingId);
          displayMessage("REJECTED", "RETRY SCAN");
          triggerBuzzer(3);
          currentTrackingId  = "";
          scanResultReceived = false;
          pendingNextState   = WAITING_FOR_SCAN;
          actionDelayStart   = millis();
          actionDelayActive  = true;
        }
      } else if (!actionDelayActive && millis() - stateStartTime > 8000) {
        // Timeout: 8 seconds
        Serial.println("[FLOW] Server verification timed out.");
        displayMessage("TIMEOUT", "RETRY SCAN");
        triggerBuzzer(3);
        currentTrackingId  = "";
        pendingNextState   = WAITING_FOR_SCAN;
        actionDelayStart   = millis();
        actionDelayActive  = true;
      }
      // Non-blocking pause: 1s (success → UNLOCKING_ENTRY) or 2s (fail/timeout → WAITING_FOR_SCAN)
      if (actionDelayActive) {
        unsigned long pauseMs = (pendingNextState == UNLOCKING_ENTRY) ? 1000 : 2000;
        if (millis() - actionDelayStart >= pauseMs) {
          actionDelayActive = false;
          changeState(pendingNextState);
          pendingNextState = IDLE;
        }
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

        // Wait for door to physically close (reed=0) before engaging solenoid
        // Prevents the lock pin from driving against an open door frame
        if (doorWasOpened && digitalRead(REED_TOP) == 0) {
          digitalWrite(LOCK_TOP, HIGH);  // LOCK
          lockTopOpen = false;
          emitDoorState();              // 🔔 notify app: door is now locked
          Serial.println("[FLOW] Door closed → Lock ENGAGED. Proceeding.");
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
        if (d > 1.0 && d <= 20.0) { // Strict 20cm threshold as requested
          Serial.println("[FLOW] Parcel detected. Tilting platform...");
          triggerBuzzer(2);
          changeState(TILTING_PLATFORM);
        }
      }
      break;

    // ── TILTING PLATFORM ──────────────────────────────────
    case TILTING_PLATFORM:
      if (!stateInitialized) {
        displayMessage("SORTING", isReceivingMode ? "To DROP OFF Bin" : "To PICK UP Bin");
        Serial.println("[FLOW] Action: Tilting Tray...");
        triggerBuzzer(1);
        moveServoSmoothly(90, isReceivingMode ? 0 : 180);
        actionDelayStart  = millis();   // non-blocking settle wait (2s)
        actionDelayActive = true;
        stateInitialized  = true;
      }
      if (actionDelayActive && millis() - actionDelayStart >= 2000) {
        actionDelayActive = false;
        moveServoSmoothly(platformServo.read(), 90);
        changeState(CONFIRMING_DROP);
      }
      break;
    // ── CONFIRMING DROP ───────────────────────────────────
    case CONFIRMING_DROP:
      {
        if (!stateInitialized) {
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
          actionDelayStart  = millis();   // 3s display pause before reset
          actionDelayActive = true;
          stateInitialized  = true;
        }
        if (actionDelayActive && millis() - actionDelayStart >= 3000) {
          actionDelayActive = false;
          changeState(RESETTING);
        }
      }
      break;

    // ── RESETTING ─────────────────────────────────────────
    case RESETTING:
      triggerBuzzer(1);
      digitalWrite(LOCK_TOP,      HIGH);
      digitalWrite(LOCK_PICKUP,   HIGH);
      digitalWrite(LOCK_RECEIVED, HIGH);
      lockTopOpen = false; lockPickupOpen = false; lockReceivedOpen = false;
      emitDoorState();  // notify app: all doors locked on reset
      platformServo.write(90);
      currentTrackingId   = "";
      scanResultReceived  = false;
      isRiderMode         = false;
      isMultiMode         = false;
      scannedCount        = 0;
      riderVerifyReceived = false;
      riderVerifyValid    = false;
      changeState(IDLE);
      showHomeScreen();
      Serial.println("--- [FLOW] SYSTEM RESET TO IDLE ---");
      break;
  }
}

void drawScannerBg() {
  tft.drawRect(60, 60, 200, 100, COLOR_GREY);
  tft.drawRect(58, 58, 204, 104, COLOR_ACCENT);
  tft.fillRect(70, 110, 180, 2, COLOR_RED); // red scanner line
  tft.setTextSize(2); tft.setTextColor(COLOR_GREY);
  tft.setCursor(85, 75); tft.print("SCAN BARCODE");
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
  socketIO.begin(SERVER_HOST, SERVER_PORT, SERVER_PATH);  // Plain WS (no SSL) for local server
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
      if (DEBUG_WS) { Serial.print("[WS] Event: "); Serial.println(msg); }

      StaticJsonDocument<1024> doc;
      DeserializationError err = deserializeJson(doc, payload, length);
      if (err) {
        Serial.print("[WS] JSON parse error: "); Serial.println(err.c_str());
        break;
      }

      String eventName = doc[0].as<String>();

      if (eventName == "scanResult") {
        String data;
        serializeJson(doc[1], data);
        handleScanResult(data);

      } else if (eventName == "riderVerifyResult") {
        // Server responded to our verifyRider request
        String data;
        serializeJson(doc[1], data);
        handleRiderVerifyResult(data);

      } else if (eventName == "registerTracking") {
        String data;
        serializeJson(doc[1], data);
        handleRegisterTracking(data);

      } else if (eventName == "controlDoor") {
        String data;
        serializeJson(doc[1], data);
        handleControlDoor(data);

      } else if (eventName == "getStatus") {
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
  if (DEBUG_WS) { Serial.print("[WS] Emitted verifyScan: "); Serial.println(output); }
}

// ============================================================
//  EMIT: Send verifyRider to server
// ============================================================
void emitVerifyRider(const String& riderId) {
  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("verifyRider");
  JsonObject data = arr.createNestedObject();
  data["riderId"] = riderId;

  String output;
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output.c_str());
  if (DEBUG_WS) { Serial.print("[WS] Emitted verifyRider: "); Serial.println(output); }
}

// ============================================================
//  EMIT: Register owner pickup tracking ID via scanner
// ============================================================
void emitRegisterOwnerPickup(const String& trackingId) {
  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("registerOwnerPickup");
  JsonObject data = arr.createNestedObject();
  data["trackingId"] = trackingId;

  String output;
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output.c_str());
  if (DEBUG_WS) { Serial.print("[WS] Emitted registerOwnerPickup: "); Serial.println(output); }
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
  if (DEBUG_WS) { Serial.print("[WS] Emitted statusUpdate: "); Serial.println(output); }
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
  if (DEBUG_WS) { Serial.print("[WS] Emitted doorStateUpdate: "); Serial.println(output); }
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
}

// ============================================================
//  HANDLE: riderVerifyResult from server
// ============================================================
void handleRiderVerifyResult(const String& payload) {
  StaticJsonDocument<256> doc;
  deserializeJson(doc, payload);

  bool valid = doc["valid"].as<bool>();
  Serial.print("[WS] riderVerifyResult → valid: "); Serial.println(valid ? "YES" : "NO");

  riderVerifyValid    = valid;
  riderVerifyReceived = true;
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
      Serial.print("  Server     : ws://"); Serial.print(SERVER_HOST); Serial.print(":"); Serial.println(SERVER_PORT);
      Serial.print("  Socket.IO  : "); Serial.println(socketIO.isConnected() ? "Connected" : "Disconnected");
    } else if (cmd == 'N') {
      Serial.println("[MANUAL] Bypassing current step...");
      forceNextStep();
    } else if (cmd == 'T') {
      Serial.println("[MANUAL] Re-initializing TFT Display...");
      reinitTFT();
    }
  }
}

void reinitTFT() {
  digitalWrite(TFT_RST, LOW);
  delay(100);
  digitalWrite(TFT_RST, HIGH);
  delay(150);
  tft.begin();
  tft.setRotation(3);
  showHomeScreen();
}

void forceNextStep() {
  switch (currentState) {
    case SELECTING_PICKUP_TYPE:
      Serial.println("[FLOW] Bypass: Defaulting to OWNER mode.");
      isRiderMode = false;
      changeState(OWNER_SELECTING_MODE);
      break;
    case OWNER_SELECTING_MODE:
      Serial.println("[FLOW] Bypass: Defaulting to SINGLE mode.");
      isMultiMode = false; scannedCount = 0;
      changeState(OWNER_SCANNING);
      break;
    case OWNER_SCANNING:
      Serial.println("[FLOW] Bypass: Skipping owner scan.");
      changeState(RESETTING);
      break;
    case OWNER_ADD_MORE_PROMPT:
      Serial.println("[FLOW] Bypass: Ending multi-scan.");
      changeState(RESETTING);
      break;
    case RIDER_VERIFYING:
      Serial.println("[FLOW] Bypass: Skipping rider verification.");
      changeState(RIDER_DOOR_OPEN);
      break;
    case RIDER_DOOR_OPEN:
      Serial.println("[FLOW] Bypass: Skipping bin door wait.");
      changeState(RIDER_SCANNING_PARCELS);
      break;
    case RIDER_SCANNING_PARCELS:
      Serial.println("[FLOW] Bypass: Skipping parcel scan.");
      changeState(RIDER_PICKUP_PROMPT);
      break;
    case RIDER_PICKUP_PROMPT:
      Serial.println("[FLOW] Bypass: Ending rider session.");
      changeState(RESETTING);
      break;
    case WAITING_FOR_SCAN:
      Serial.println("[FLOW] Bypass: Bypassing Scan.");
      changeState(UNLOCKING_ENTRY);
      break;
    case UNLOCKING_ENTRY:
      Serial.println("[FLOW] Bypass: Bypassing Reed Switch.");
      changeState(WAITING_PLACEMENT_STABLE);
      break;
    case WAITING_PLACEMENT_STABLE:
      Serial.println("[FLOW] Bypass: Bypassing Platform Sensor.");
      changeState(TILTING_PLATFORM);
      break;
    case TILTING_PLATFORM:
      changeState(CONFIRMING_DROP);
      break;
    case CONFIRMING_DROP:
      changeState(RESETTING);
      break;
    default:
      Serial.println("[FLOW] Bypass: No bypass action for current state.");
      break;
  }
}

void printSerialMenu() {
  Serial.println();
  Serial.println("==========================================");
  Serial.println("     SMART PARCEL DROPBOX SYSTEM");
  Serial.println("==========================================");
  Serial.println("  [BTN1] Drop Off     [BTN2] Pick Up");
  Serial.println("------------------------------------------");
  Serial.println("  S=Reset  | U=Unlock All | D=US Diag | N=Next | T=TFT Reset");
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
    socketIO.loop();  // keep Socket.IO heartbeat alive during slow tilt
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
  uint16_t bgColor = (strstr(title, "SUCCESS") || strstr(title, "VALID"))                                         ? COLOR_GREEN :
                     (strstr(title, "ERROR")   || strstr(title, "INVALID") || strstr(title, "REJECTED") ||
                      strstr(title, "TIMEOUT") || strstr(title, "WARN"))                                          ? COLOR_RED   : COLOR_BLUE;

  tft.fillScreen(bgColor);
  drawStatusBar();
  
  if (bgColor == COLOR_GREEN) drawIconCheck(160, 100, COLOR_TEXT);
  else if (bgColor == COLOR_RED) drawIconX(160, 100, COLOR_TEXT);
  else drawIconBox(160, 100, COLOR_TEXT);

  tft.setCursor(0, 160);  tft.setTextSize(3); tft.setTextColor(COLOR_TEXT); 
  tft.setTextWrap(false);
  
  // Center alignment logic (approximate for 320px width)
  int titleX = 160 - (strlen(title) * 9); 
  tft.setCursor(max(0, titleX), 160);
  tft.println(title);

  tft.setTextSize(2);
  int msgX = 160 - (strlen(msg) * 6);
  tft.setCursor(max(0, msgX), 200);
  tft.println(msg);
}


void showHomeScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Draw Mode Selection Tiles
  // Left: Drop Off (Blue)
  tft.fillRoundRect(10, 50, 145, 170, 10, COLOR_BLUE);
  drawIconBox(82, 110, COLOR_TEXT);
  tft.setCursor(35, 180); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
  tft.print("DROP OFF");
  tft.setCursor(45, 205); tft.setTextSize(1);
  tft.print("[Btn Red]");

  // Right: Pick Up (Purple)
  tft.fillRoundRect(165, 50, 145, 170, 10, COLOR_PURPLE);
  drawIconLock(237, 110, COLOR_TEXT, true);
  tft.setCursor(195, 180); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
  tft.print("PICK UP");
  tft.setCursor(215, 205); tft.setTextSize(1);
  tft.print("[Btn Blue]");
  
  printSerialMenu();
}

void drawStatusBar() {
  tft.fillRect(0, 0, 320, 32, 0x2104); // Dark grey bar
  tft.drawFastHLine(0, 32, 320, COLOR_GREY);
  
  // WiFi Icon
  drawWiFiSignal(10, 10, (WiFi.status() == WL_CONNECTED) ? COLOR_GREEN : COLOR_RED);
  
  // App/Server Status Dot
  tft.fillCircle(300, 16, 5, socketIO.isConnected() ? COLOR_GREEN : COLOR_RED);
  tft.setCursor(240, 12); tft.setTextSize(1); tft.setTextColor(COLOR_TEXT);
  tft.print(socketIO.isConnected() ? "ONLINE" : "OFFLINE");

  // Mode Text
  tft.setCursor(100, 10); tft.setTextSize(1); tft.setTextColor(COLOR_ACCENT);
  tft.print("SMART PARCEL DROPBOX");
}

void drawWiFiSignal(int x, int y, uint16_t color) {
  for(int i=0; i<4; i++) {
    tft.fillRect(x + (i*4), y + (12 - (i*3)), 3, (i*3) + 3, color);
  }
}

void drawIconLock(int x, int y, uint16_t color, bool open) {
  // Shackle
  if (open) {
    tft.drawCircle(x, y-5, 10, color);
    tft.fillRect(x+5, y-5, 10, 10, COLOR_BG); // break the circle
  } else {
    tft.drawCircle(x, y, 10, color);
  }
  // Body
  tft.fillRoundRect(x-12, y+2, 24, 18, 3, color);
  tft.fillCircle(x, y+11, 3, COLOR_BG); // keyhole
}

void drawIconBox(int x, int y, uint16_t color) {
  tft.drawRect(x-15, y-10, 30, 25, color);
  tft.drawRect(x-16, y-11, 32, 27, color);
  tft.drawLine(x-15, y-10, x+15, y+15, color); 
  tft.drawLine(x-15, y+15, x+15, y-10, color);
}

void drawIconCheck(int x, int y, uint16_t color) {
  tft.drawLine(x-20, y, x-5, y+15, color);
  tft.drawLine(x-21, y, x-6, y+15, color);
  tft.drawLine(x-5, y+15, x+25, y-20, color);
  tft.drawLine(x-6, y+15, x+24, y-20, color);
}

void drawIconX(int x, int y, uint16_t color) {
  tft.drawLine(x-20, y-20, x+20, y+20, color);
  tft.drawLine(x-21, y-20, x+19, y+20, color);
  tft.drawLine(x+20, y-20, x-20, y+20, color);
  tft.drawLine(x+21, y-20, x-19, y+20, color);
}

// ============================================================
//  ATM SCREEN: Pick Up Type Selection [Owner | Rider]
// ============================================================
void drawPickupSelectScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  tft.setCursor(50, 38); tft.setTextSize(2); tft.setTextColor(COLOR_ACCENT);
  tft.print("SELECT PICK UP TYPE");
  // Left tile: Owner (Blue)
  tft.fillRoundRect(8, 58, 147, 155, 10, COLOR_BLUE);
  drawIconLock(82, 108, COLOR_TEXT, true);
  tft.setCursor(25, 178); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
  tft.print("OWNER");
  tft.setCursor(22, 200); tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
  tft.print("[Left Button]");
  // Right tile: Rider (Purple)
  tft.fillRoundRect(165, 58, 147, 155, 10, COLOR_PURPLE);
  drawIconBox(238, 108, COLOR_TEXT);
  tft.setCursor(187, 178); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
  tft.print("RIDER");
  tft.setCursor(178, 200); tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
  tft.print("[Right Button]");
}

// ============================================================
//  ATM SCREEN: Owner Mode Selection [Single | Multiple]
// ============================================================
void drawOwnerModeScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  tft.setCursor(60, 38); tft.setTextSize(2); tft.setTextColor(COLOR_ACCENT);
  tft.print("OWNER PICK UP");
  // Left tile: Single (Blue)
  tft.fillRoundRect(8, 58, 147, 155, 10, COLOR_BLUE);
  drawIconBox(82, 108, COLOR_TEXT);
  tft.setCursor(32, 175); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
  tft.print("SINGLE");
  tft.setCursor(25, 197); tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
  tft.print("1 parcel");
  tft.setCursor(22, 210); tft.setTextSize(1);
  tft.print("[Left Button]");
  // Right tile: Multiple (Purple)
  tft.fillRoundRect(165, 58, 147, 155, 10, COLOR_PURPLE);
  drawIconBox(238, 98, COLOR_TEXT);
  drawIconBox(238, 118, COLOR_TEXT);
  tft.setCursor(175, 175); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
  tft.print("MULTIPLE");
  tft.setCursor(187, 197); tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
  tft.print("2+ parcels");
  tft.setCursor(178, 210); tft.setTextSize(1);
  tft.print("[Right Button]");
}

// ============================================================
//  ATM SCREEN: Add More Parcel Prompt [Add More | Done]
// ============================================================
void drawAddMorePrompt() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  String countStr = "Parcel #" + String(scannedCount) + " registered!";
  tft.setCursor(max(0, (int)(160 - countStr.length() * 6)), 40);
  tft.setTextSize(2); tft.setTextColor(COLOR_GREEN);
  tft.print(countStr);
  // Left tile: Add More (Blue)
  tft.fillRoundRect(8, 70, 147, 145, 10, COLOR_BLUE);
  tft.setCursor(22, 120); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
  tft.print("ADD MORE");
  tft.setCursor(22, 185); tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
  tft.print("[Left Button]");
  // Right tile: Done (Green)
  tft.fillRoundRect(165, 70, 147, 145, 10, COLOR_GREEN);
  drawIconCheck(238, 120, COLOR_TEXT);
  tft.setCursor(190, 165); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
  tft.print("DONE");
  tft.setCursor(178, 185); tft.setTextSize(1); tft.setTextColor(0x0000);
  tft.print("[Right Button]");
}

// ============================================================
//  SCREEN: Rider Scan ID
// ============================================================
void drawRiderScanIdScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  drawScannerBg();
  tft.setCursor(55, 185); tft.setTextSize(2); tft.setTextColor(COLOR_ACCENT);
  tft.print("Scan Rider ID");
  tft.setCursor(40, 210); tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
  tft.print("Scan your rider QR code");
}

// ============================================================
//  SCREEN: Rider Scan Parcel
// ============================================================
void drawRiderScanParcelScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  drawScannerBg();
  String prompt = "Scan Parcel #" + String(scannedCount + 1);
  tft.setCursor(max(0, (int)(160 - prompt.length() * 6)), 185);
  tft.setTextSize(2); tft.setTextColor(COLOR_ACCENT);
  tft.print(prompt);
  tft.setCursor(30, 210); tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
  tft.print("Scan each parcel barcode");
}

// ============================================================
//  ATM SCREEN: Rider Pickup More Prompt [Pick Up More | Done]
// ============================================================
void drawRiderPickupMorePrompt() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  String countStr = "#" + String(scannedCount) + " marked DONE";
  tft.setCursor(max(0, (int)(160 - countStr.length() * 6)), 40);
  tft.setTextSize(2); tft.setTextColor(COLOR_GREEN);
  tft.print(countStr);
  // Left tile: Pick Up More (Purple)
  tft.fillRoundRect(8, 70, 147, 145, 10, COLOR_PURPLE);
  tft.setCursor(15, 110); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
  tft.print("PICK UP");
  tft.setCursor(22, 132); tft.setTextSize(2);
  tft.print("MORE");
  tft.setCursor(22, 185); tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
  tft.print("[Left Button]");
  // Right tile: Done (Green)
  tft.fillRoundRect(165, 70, 147, 145, 10, COLOR_GREEN);
  drawIconCheck(238, 120, COLOR_TEXT);
  tft.setCursor(190, 165); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
  tft.print("DONE");
  tft.setCursor(178, 185); tft.setTextSize(1); tft.setTextColor(0x0000);
  tft.print("[Right Button]");
}