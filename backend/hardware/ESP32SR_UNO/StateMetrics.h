#pragma once

#include <Arduino.h>
#include <ESP32Servo.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
#include <SocketIOclient.h>
#include <Preferences.h>
#include <Fonts/FreeSans9pt7b.h>
#include <Fonts/FreeSans12pt7b.h>
#include <Fonts/FreeSansBold12pt7b.h>

// ============================================================
//  PINOUT DEFINITIONS
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

#define SERVO_PIN        14

// ============================================================
//  DISPLAY COLORS (Material Dark Theme)
// ============================================================
#define COLOR_BG      0x10A2  // #121212 Very Dark Grey
#define COLOR_CARD    0x2124  // #1E1E1E Elevated Grey
#define COLOR_TEXT    0xFFFF  // Pure White
#define COLOR_ACCENT  0x3DFF  // Cyan Highlight
#define COLOR_BLUE    0x041A  // Material Blue #4285F4
#define COLOR_PURPLE  0x780F  // Deep Purple
#define COLOR_GREEN   0x05E6  // Material Green #34A853
#define COLOR_RED     0xF800  // Material Red #EA4335
#define COLOR_GREY    0x8410  // #888888 Light Grey
#define COLOR_GOLD    0xFDE0  // Material Yellow/Gold

// ============================================================
//  STATE MACHINE
// ============================================================
enum SystemState {
  DEVICE_UNREGISTERED,
  SHOWING_REGISTRATION_QR,
  IDLE,
  SELECTING_PICKUP_TYPE,
  OWNER_VERIFYING,
  OWNER_SELECTING_MODE,
  OWNER_SCANNING,
  OWNER_ADD_MORE_PROMPT,
  RIDER_VERIFYING,
  RIDER_DOOR_OPEN,
  RIDER_SCANNING_PARCELS,
  RIDER_PICKUP_PROMPT,
  WAITING_FOR_SCAN,
  VERIFYING_SCAN,
  UNLOCKING_ENTRY,
  WAITING_PLACEMENT_STABLE,
  TILTING_PLATFORM,
  CONFIRMING_DROP,
  SCAN_FAILED_PROMPT,
  SCAN_TIMEOUT_PROMPT,
  WAITING_FOR_WIFI_CONFIG,
  SETUP_NO_SERVER,
  RESETTING
};

// ============================================================
//  EXTERN GLOBALS (Defined in Globals.cpp)
// ============================================================

extern SystemState currentState;
extern bool isReceivingMode;
extern bool isRiderMode;
extern bool isMultiMode;
extern int  scannedCount;
extern int  consecutiveScanFails;
extern bool stateInitialized;
extern bool doorWasOpened;
extern unsigned long stateStartTime;
extern unsigned long stabilityStartTime;
extern unsigned long lastDebugTime;

extern unsigned long actionDelayStart;
extern bool          actionDelayActive;
extern SystemState   pendingNextState;

extern bool   riderVerifyReceived;
extern bool   riderVerifyValid;
extern String serial2Buffer;

extern String ownerSessionToken;
extern bool   ownerApprovalReceived;
extern bool   ownerApprovalValid;
extern bool   ownerQrDrawn;
extern bool   ownerVerifyTimedOut;

extern Preferences nvsPrefs;
extern String nvsWifiSSID;
extern String nvsWifiPassword;
extern bool   deviceRegistered;
extern unsigned long previousMillisWiFi;
extern unsigned long intervalWiFi;

extern String registrationToken;
extern bool   regTokenReceived;
extern bool   regQrDrawn;
extern bool   deviceJustRegistered;

extern String registeredDropOff;
extern String registeredPickup;
extern String currentTrackingId;

extern bool scanResultReceived;
extern bool scanResultValid;

extern bool lockTopOpen;
extern bool lockPickupOpen;
extern bool lockReceivedOpen;

extern bool lastWifiState;
extern bool lastSocketState;
extern bool lastDoorState;
extern unsigned long lastIndicatorUpdate;

#define MAX_OFFLINE_QUEUE 20
extern String offlineQueue[MAX_OFFLINE_QUEUE];
extern int offlineQueueCount;

extern unsigned long dropOffRegisterTime;
extern unsigned long pickupRegisterTime;
extern const unsigned long TIMEOUT_MS;

extern Servo            platformServo;
extern Adafruit_ILI9341 tft;
extern SocketIOclient   socketIO;

extern const int US_PLATFORM[2];
extern const int US_PICKUP[2];
extern const int US_DROPOFF[2];

// Utility Forward declarations for globally used functions
void changeState(SystemState newState);
void displayMessage(const String& title, const String& subtitle);
void drawTimeoutScreen(const char* title, const char* subtitle);
