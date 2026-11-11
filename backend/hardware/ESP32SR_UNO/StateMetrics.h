#pragma once

#include <Arduino.h>
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
#define TFT_RST   7   // Moved from GPIO 20 (native USB_D+) to GPIO 7 to prevent white screen
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

// ============================================================
//  AVAILABLE / RESERVED FREE PINS (Hardware components removed)
// ============================================================
// GPIO 14: Available (Servo motor removed)
// GPIO 15: Available (Platform Ultrasonic Trig removed)
// GPIO  4: Available (Platform Ultrasonic Echo removed)
// GPIO  7: Assigned to TFT_RST (Moved from GPIO 20)
// GPIO 16: Available (Pickup Ultrasonic Echo removed)
// GPIO 20: Dedicated to ESP32-S3 Native USB_D+
#define SERVO_PIN        14  // Available GPIO 14

// ============================================================
//  DISPLAY COLORS (Sci-Fi Robotic HUD Theme)
// ============================================================
#define COLOR_BG      0x0000  // Pure Black
#define COLOR_CARD    0x0841  // Deep Charcoal (Very Dark Grey)
#define COLOR_TEXT    0xFFFF  // Pure White
#define COLOR_ACCENT  0x07FF  // Neon Cyan / Electric Blue
#define COLOR_BLUE    0x001F  // Deep Sci-Fi Blue
#define COLOR_PURPLE  0x780F  // Deep Purple
#define COLOR_GREEN   0x07E0  // Neon Green
#define COLOR_RED     0xF800  // Warning Red
#define COLOR_GREY    0x7BEF  // Steel Grey
#define COLOR_GOLD    0xFFE0  // Amber / Warning Yellow
#define COLOR_NEON_ORANGE 0xFD20 // Neon Orange
#define COLOR_NEON_CYAN   0x07FF // Neon Cyan

// UI Constants
#define HUD_MARGIN    10
#define HUD_CORNER    6
#define BAR_HEIGHT    24
#define TFT_SPI_FREQ  14000000UL  // 14MHz noise-damped SPI clock for ground noise immunity

// Network & Setup Constants
#define CAPTIVE_AP_SSID   "SmartParcelBox_Setup"

// ============================================================
//  STATE MACHINE
// ============================================================
enum SystemState {
  DEVICE_UNREGISTERED,
  SHOWING_REGISTRATION_QR,
  IDLE,
  PICKUP_DOOR_OPEN,
  WAITING_FOR_SCAN,
  VERIFYING_SCAN,
  UNLOCKING_ENTRY,
  CONFIRMING_DROP,
  SCAN_FAILED_PROMPT,
  SCAN_TIMEOUT_PROMPT,
  WAITING_FOR_WIFI_CONFIG,
  SETUP_NO_SERVER,
  SETTINGS_MENU,
  RESETTING,
  LOCKSCREEN
};

#define RIDER_DOOR_OPEN PICKUP_DOOR_OPEN

#define IDLE_TIMEOUT_MS 30000

enum RobotEmotion {
  NEUTRAL,
  HAPPY,
  WINK,
  SQUINT
};

extern RobotEmotion currentEmotion;

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
extern bool          isScannerTestActive;
extern bool          isUsDiagContinuousActive;
extern unsigned long lastStateChangeTime;
extern unsigned long scannerTestStartTime;

extern bool   riderVerifyReceived;
extern bool   riderVerifyValid;
extern char serial2Buffer[128];

extern Preferences nvsPrefs;
extern char nvsWifiSSID[33];
extern char nvsWifiPassword[64];
extern bool   deviceRegistered;
extern unsigned long previousMillisWiFi;
extern unsigned long intervalWiFi;

extern char registrationToken[32];
extern bool   regTokenReceived;
extern bool   regQrDrawn;
extern bool   deviceJustRegistered;

extern char registeredDropOff[64];
extern char registeredPickup[64];
extern char currentTrackingId[64];

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
extern char offlineQueue[MAX_OFFLINE_QUEUE][64];
extern int offlineQueueCount;

extern unsigned long lastLockscreenUpdate;
extern int eyeX, eyeY;
extern int pupilX, pupilY;
extern int targetPupilX, targetPupilY;
extern bool isBlinking;
extern unsigned long nextBlinkTime;
extern unsigned long nextTextTime;
extern bool showingText;
extern int textX;
extern int currentOffsetX;
extern int targetOffsetX;
extern unsigned long lastMoveTime;
extern unsigned long lastEmotionTime;

extern unsigned long dropOffRegisterTime;
extern unsigned long pickupRegisterTime;
extern const unsigned long TIMEOUT_MS;

// Non-blocking hardware state
extern float lastUsPlatformDist;
extern float lastUsPickupDist;
extern float lastUsDropoffDist;
extern float dropoffBaselineDist;
extern unsigned long lastUsPlatformTime;
extern unsigned long lastUsPickupTime;
extern unsigned long lastUsDropoffTime;

extern Adafruit_ILI9341 tft;
extern SocketIOclient   socketIO;

// --- Global Function Prototypes (Hardware & UI) ---
void processSensors();
void triggerCyberChirp(int pattern);
void triggerBuzzer(int beeps);
void updateDynamicIndicators();
void updateProcessingHUD(const char* status);
void showHomeScreen();
void displayMessage(const char* title, const char* msg);
void drawTimeoutScreen(const char* title, const char* subtitle);
void drawRobotEyeLockscreen(int x, int y, int offsetX, bool blink, RobotEmotion emotion);
void drawLockscreenText(const char* line1, const char* line2);
void drawDeviceUnregisteredScreen();
void changeState(SystemState newState);
void emitDoorState();
void emitVerifyRider(const String& riderId);
void emitStatusUpdate(const String& trackingId, const String& status, const String& mode);
void handleRequestWiFiScan();
void handleApplyHardwareConfig(const String& payload);
void handleScanResult(const String& payload);
void handleRiderVerifyResult(const String& payload);
void handleRegisterTracking(const String& payload);
void handleControlDoor(const String& payload);
void emitWifiScanResult(int n);
int  readReedDebounced(int pin);
void setPickupLock(bool unlock);

extern const int US_PLATFORM[2];
extern const int US_PICKUP[2];
extern const int US_DROPOFF[2];

// Utility inline helper for String-based displayMessage calls
inline void displayMessage(const String& title, const String& subtitle) {
  displayMessage(title.c_str(), subtitle.c_str());
}
