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
#include "qrcode.h"       // Local copy — avoids ESP32 core qrcode symbol conflict
#define DEBUG_WS      false // Toggle for verbose Socket.IO logs
#define DEBUG_SERIAL  true

#include <WiFi.h>
#include <WiFiClientSecure.h> // Required for WSS
#include <WebServer.h>        // Required for Captive Portal
#include <DNSServer.h>        // Required for Captive Portal
#include <SocketIOclient.h>
#include <ArduinoJson.h>
#include <esp_task_wdt.h> // ESP32 Task Watchdog Timer
#include <Preferences.h>  // NVS (Non-Volatile Storage) for persisting credentials

#define WDT_TIMEOUT 8 // Watchdog timeout in seconds

// ============================================================
//  ISRG Root X1 - Root CA for Let's Encrypt (used by Render.com)
//  This certificate is valid until 2035 and allows the ESP32
//  to verify the Render.com SSL certificate during the handshake.
// ============================================================
static const char RENDER_ROOT_CA[] PROGMEM = R"EOF(
-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----
)EOF";

// ============================================================
//  CONFIGURATION — Credentials live in config.h (NOT committed)
// ============================================================
#include "config.h"  // ⚠ Add config.h to .gitignore — contains WiFi password

#include "StateMetrics.h"

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
void emitRequestOwnerSession();
void handleRegisterTracking(const String& payload);
void handleScanResult(const String& payload);
void handleRiderVerifyResult(const String& payload);
void handleOwnerSessionToken(const String& payload);
void handleOwnerApprovalResult(const String& payload);
void handleControlDoor(const String& payload);
float getDistance(const int pins[]);
void emitRequestDeviceRegistration();
void drawRegistrationQRScreen(const String& token, const String& pin);
void drawSettingsMenu();
void drawNoServerOptionsScreen();
void drawWiFiConfigQRScreen(const char* ssid);
void setupCaptivePortal();
void loopCaptivePortal();
void stopCaptivePortal();
void checkFactoryReset();
void printSerialMenu();
void showHomeScreen();
void drawStatusBar();
void drawOwnerVerifyingScreen(const String& token);
void drawQRCode(int x, int y, int moduleSize, const String& text);
void drawScannerBg();
void drawPickupSelectScreen();
void drawOwnerModeScreen();
void drawAddMorePrompt();
void drawRiderScanIdScreen();
void drawRiderScanParcelScreen();
void drawRiderPickupMorePrompt();
void drawScanFailedPrompt();
void drawIconLock(int x, int y, uint16_t color, bool open);
void drawIconBox(int x, int y, uint16_t color);
void drawIconCheck(int x, int y, uint16_t color);
void drawIconX(int x, int y, uint16_t color);
void drawWiFiSignal(int x, int y, uint16_t color);
void drawWiFiSignal(int x, int y, uint16_t color);
void reinitTFT();

// --- Non-blocking Hardware Hooks ---
void processServo(); 
void processSensors();
void triggerCyberChirp(int pattern);
void triggerBuzzer(int beeps);
void updateDynamicIndicators();
void updateProcessingHUD(const char* status);
void shakeServo(int targetAngle);
void moveServoSmoothly(int to);
void showHomeScreen();
void displayMessage(const char* title, const char* msg);
void drawTimeoutScreen(const char* title, const char* subtitle);
void drawRobotEyeLockscreen(int x, int y, int offsetX, bool blink, RobotEmotion emotion);
void drawLockscreenText(const char* line1, const char* line2);
void drawDeviceUnregisteredScreen();

// ============================================================
//  SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000);

  Serial.println("\n--- [SYSTEM STARTUP] ---");

  // --- SAFE HARDWARE INIT ---
  // Ensure solenoids and buzzer don't float and trigger during the servo boot delay
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW); // Assumes HIGH = beep

  pinMode(LOCK_TOP,      OUTPUT); digitalWrite(LOCK_TOP,      HIGH); // HIGH = Locked
  pinMode(LOCK_PICKUP,   OUTPUT); digitalWrite(LOCK_PICKUP,   HIGH);
  pinMode(LOCK_RECEIVED, OUTPUT); digitalWrite(LOCK_RECEIVED, HIGH);

  // --- EARLY SERVO INIT ---
  // Prevents floating and uncontrolled spinning on power up
  ESP32PWM::allocateTimer(0);
  ESP32PWM::allocateTimer(1);
  ESP32PWM::allocateTimer(2);
  ESP32PWM::allocateTimer(3);
  platformServo.setPeriodHertz(50); // Standard 50Hz servo
  platformServo.attach(SERVO_PIN, 500, 2500); // Expanded 180° servo pulse range
  platformServo.write(90);          // Drive to center to stabilize
  delay(500);                       // Give it time to reach center
  platformServo.detach();           // Detach: stops PWM output → servo holds position passively

  // Inputs
  pinMode(BTN_RECEIVE,   INPUT_PULLUP);
  pinMode(BTN_PICKUP,    INPUT_PULLUP);
  pinMode(REED_TOP,      INPUT_PULLUP);
  pinMode(REED_PICKUP,   INPUT_PULLUP);
  pinMode(REED_RECEIVED, INPUT_PULLUP);

  // Watchdog initialization will be moved to the end of setup() to prevent reboots during WiFi sync

  // Ultrasonic sensors - Ensure pins start in a stable state
  pinMode(US_PLATFORM[0], OUTPUT); pinMode(US_PLATFORM[1], INPUT_PULLDOWN);
  pinMode(US_PICKUP[0],   OUTPUT); pinMode(US_PICKUP[1],   INPUT_PULLDOWN);
  pinMode(US_DROPOFF[0],  OUTPUT); pinMode(US_DROPOFF[1],  INPUT_PULLDOWN);
  digitalWrite(US_PLATFORM[0], LOW);
  digitalWrite(US_PICKUP[0],   LOW);
  digitalWrite(US_DROPOFF[0],  LOW);
  delay(50); // Give the sensors and pull-downs time to stabilize

  // Scanner serial: Arduino Uno TX → GPIO17 (ESP32 RX). TX=-1 as no return wire exists.
  // We use a pullup on RX to prevent floating noise from being interpreted as data.
  pinMode(17, INPUT_PULLUP);
  Serial2.begin(9600, SERIAL_8N1, 17, -1);
  Serial2.setRxBufferSize(1024); // Increase RX buffer to handle long barcodes without dropping

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

  // Network — load credentials from NVS first
  nvsPrefs.begin("smartbox", false); 
  String s_ssid = nvsPrefs.getString("ssid", "");
  String s_pass = nvsPrefs.getString("password", "");
  strncpy(nvsWifiSSID, s_ssid.c_str(), sizeof(nvsWifiSSID)-1);
  strncpy(nvsWifiPassword, s_pass.c_str(), sizeof(nvsWifiPassword)-1);
  deviceRegistered = nvsPrefs.getBool("registered", false);
  nvsPrefs.end();

  Serial.print("[NVS] Registered: "); Serial.println(deviceRegistered ? "YES" : "NO");
  Serial.print("[NVS] SSID: "); Serial.println(strlen(nvsWifiSSID) ? nvsWifiSSID : "(none)");

  if (strlen(nvsWifiSSID) > 0) {
    setupWiFi();
    setupSocketIO();
  } else {
    Serial.println("[BOOT] No saved SSID. WiFi will be set up during registration.");
  }

  if (!deviceRegistered) {
    // Go to setup mode but don't return early if we have WiFi to attempt
    Serial.println("[BOOT] Device UNREGISTERED. Entering setup mode.");
    triggerCyberChirp(3);
    changeState(DEVICE_UNREGISTERED);
  } else {
    triggerCyberChirp(1); // Success Startup
    showHomeScreen();
  }
  
  printSerialMenu();

  // Final Step: Initialize Task Watchdog Timer (v3.x API)
  // Move this last so it doesn't trigger during the initial setup/WiFi sync
  esp_task_wdt_config_t twdt_config = {
      .timeout_ms = 8000, // 8-second window for the main loop
      .idle_core_mask = (1 << 0) | (1 << 1),
      .trigger_panic = true
  };
  
  // Try initializing, but ignore "already initialized" errors
  esp_err_t err = esp_task_wdt_init(&twdt_config);
  if (err == ESP_OK || err == ESP_ERR_INVALID_STATE) {
    // We REMOVED esp_task_wdt_add(NULL) because socketIO.loop() blocks during TCP 
    // reconnection attempts when the server is offline, which causes the WDT to 
    // panic and reboot. By not adding the main loop, it survives offline periods.
    // esp_task_wdt_add(NULL); 
    Serial.println("[BOOT] Task Watchdog Timer (TWDT) initialized (Monitoring disabled for offline stability).");
  }
}

// ============================================================
//  MAIN LOOP
// ============================================================
void loop() {
  yield();
  // Check factory reset button hold (5s on BTN_PICKUP from any operational state)
  checkFactoryReset();
  
  // 1. Maintain background tasks
  socketIO.loop();
  // esp_task_wdt_reset(); // Disabled to prevent "task not found" spam after detaching main loop
  processServo();
  processSensors();
  
  checkSerialCommands();

  // --- Bug Fix: Drainage for "Always Active" Scanner ---
  // Cooldown: Don't drain for 200ms after a state change to prevent race conditions
  bool cooldownActive = (millis() - lastStateChangeTime < 200);

  if (isScannerTestActive) {
      if (millis() - scannerTestStartTime > 30000) {
        Serial.println("[TEST] Scanner Test timed out after 30s.");
        isScannerTestActive = false;
        serial2Buffer[0] = '\0';  // Clear software accumulator
      } else if (Serial2.available() > 0) {
        // PASSIVE TEST: Accumulate and print to Serial Monitor
            while (Serial2.available()) {
              char c = (char)Serial2.read();
              if (c == '\n' || c == '\r') {
                int len = strlen(serial2Buffer);
                if (len > 0) {
                  Serial.println("\n[SCAN TEST RESULT] --> " + String(serial2Buffer));
                  serial2Buffer[0] = '\0';
                  isScannerTestActive = false;
                }
              } else if (c >= 32 && c <= 126) {
                int len = strlen(serial2Buffer);
                if (len < sizeof(serial2Buffer) - 1) {
                  serial2Buffer[len] = c;
                  serial2Buffer[len+1] = '\0';
                }
              }
            }
    }
  } else if (!cooldownActive && currentState != OWNER_SCANNING && currentState != RIDER_VERIFYING && 
             currentState != RIDER_SCANNING_PARCELS && currentState != WAITING_FOR_SCAN) {
    // Regular Drainage: Clear buffer when NOT in a scan-expectant state
    while (Serial2.available() > 0) Serial2.read();
    serial2Buffer[0] = '\0'; 
  }
  // Skip status-bar repaints while QR verification screens, WiFi setup, or lockscreen are up
  if (currentState != OWNER_VERIFYING && currentState != SHOWING_REGISTRATION_QR && 
      currentState != WAITING_FOR_WIFI_CONFIG && currentState != LOCKSCREEN) {
    updateDynamicIndicators();
  }

  // Active WiFi Monitoring and Auto-Reconnect
  unsigned long currentMillisMillis = millis();
  if (WiFi.status() != WL_CONNECTED && (currentMillisMillis - previousMillisWiFi >= intervalWiFi)) {
    Serial.println("[WiFi] Connection lost. Attempting to reconnect...");
    WiFi.disconnect();
    WiFi.reconnect();
    previousMillisWiFi = currentMillisMillis;
  }
  
  // Clear registered tracking IDs if they timeout (5 minutes)
  if (strlen(registeredDropOff) > 0 && millis() - dropOffRegisterTime > TIMEOUT_MS) {
     Serial.println("[REG] Drop Off ID expired due to timeout.");
     registeredDropOff[0] = '\0';
  }
  if (strlen(registeredPickup) > 0 && millis() - pickupRegisterTime > TIMEOUT_MS) {
     Serial.println("[REG] Pick Up ID expired due to timeout.");
     registeredPickup[0] = '\0';
  }

  switch (currentState) {

    // ── DEVICE UNREGISTERED ───────────────────────────────
    // First boot or factory reset state.
    // Waits for user to press BTN1 to request a registration QR from the server.
    case DEVICE_UNREGISTERED:
      if (!stateInitialized) {
        drawDeviceUnregisteredScreen();
        Serial.println("[SETUP] Device not registered. Press BTN1 to start registration.");
        stateInitialized = true;
      }
      if (digitalRead(BTN_RECEIVE) == LOW) {  // BTN1 = Start Registration
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
          Serial.println("[SETUP] BTN1 pressed. Requesting registration token from server...");
          triggerBuzzer(1);
          // Ensure network is connected before requesting registration
          if (!socketIO.isConnected()) {
            if (strlen(nvsWifiSSID) == 0) {
              // Try connecting with compile-time credentials for first ever setup
              strncpy(nvsWifiSSID, WIFI_SSID, sizeof(nvsWifiSSID)-1);
              strncpy(nvsWifiPassword, WIFI_PASSWORD, sizeof(nvsWifiPassword)-1);
            }
            Serial.println("[SETUP] Not connected. Attempting WiFi/Socket setup...");
            displayMessage("CONNECTING", "Please wait...");
            setupWiFi();
            setupSocketIO();
            
            // Wait for connection (up to 30s) - Cloud SSL takes ~25s
            Serial.println("[WS] Waiting for cloud handshake...");
            unsigned long startWait = millis();
            while (!socketIO.isConnected() && millis() - startWait < 30000) {
              socketIO.loop();
              if ((millis() - startWait) % 1000 < 100) {
                Serial.print(".");
              }
              delay(50);
            }
            Serial.println();
          }

          if (socketIO.isConnected()) {
            Serial.println("[WS] Cloud connection confirmed!");
            regTokenReceived = false; // Reset before requesting
            emitRequestDeviceRegistration();
            changeState(SHOWING_REGISTRATION_QR);
          } else {
            // New V4.0 flow: Go to No Server screen with options
            triggerCyberChirp(2); // Error
            changeState(SETUP_NO_SERVER);
          }
        }
      }
      break;

    // ── V4.0: SETUP NO SERVER ────────────────────────────
    case SETUP_NO_SERVER:
      if (!stateInitialized) {
        drawNoServerOptionsScreen();
        Serial.println("[SETUP] No Server. BTN1=Retry, BTN2=Setup WiFi.");
        stateInitialized = true;
      }
      if (digitalRead(BTN_RECEIVE) == LOW) { // BTN1 = Retry
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
           triggerBuzzer(1);
           changeState(DEVICE_UNREGISTERED); // Go back to try again
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) { // BTN2 = Other (WiFi Setup)
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
           triggerCyberChirp(1);
           changeState(WAITING_FOR_WIFI_CONFIG);
        }
      }
      break;

    // ── V4.0: WAITING FOR WIFI CONFIG (Captive Portal) ─────
    case WAITING_FOR_WIFI_CONFIG:
      if (!stateInitialized) {
        setupCaptivePortal();
        drawWiFiConfigQRScreen("SmartParcelBox_Setup");
        stateInitialized = true;
      }
      loopCaptivePortal();
      
      // Allow manual exit/reboot via BTN2
      if (digitalRead(BTN_PICKUP) == LOW) {
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          triggerCyberChirp(2);
          stopCaptivePortal();
          ESP.restart();
        }
      }
      break;

    // ── SHOWING REGISTRATION QR ───────────────────────────
    // Displaying QR code + human-readable code for in-app hardware registration.
    case SHOWING_REGISTRATION_QR:
      if (!stateInitialized) {
        regQrDrawn         = false;
        deviceJustRegistered = false;
        stateStartTime     = millis();
        stateInitialized   = true;
        displayMessage("REGISTRATION", "Requesting code...");
        Serial.println("[SETUP] Waiting for registration token from server...");
      }

      // Draw QR once token arrives
      if (regTokenReceived && !regQrDrawn) {
        // Extract 6-digit PIN from token (e.g. "SPDB-REG-482913" → "482913")
        String s_token = String(registrationToken);
        String pin = s_token.substring(s_token.lastIndexOf('-') + 1);
        drawRegistrationQRScreen(s_token, pin);
        regQrDrawn    = true;
        stateStartTime = millis(); // reset 60s countdown from QR draw
        Serial.println("[SETUP] Registration QR displayed. Waiting for app scan...");
      }

      // Countdown update
      if (regQrDrawn && !deviceJustRegistered) {
        static int lastRegSec = -1;
        int elapsed   = (millis() - stateStartTime) / 1000;
        int remaining = max(0, 60 - elapsed);
        if (remaining != lastRegSec) {
          lastRegSec = remaining;
          tft.fillRect(0, 218, 320, 22, COLOR_TEXT);
          tft.setTextSize(1); tft.setTextColor(COLOR_BG);
          tft.setCursor(100, 222);
          tft.print("Expires in "); tft.print(remaining); tft.print(" seconds — scan in app");
        }
        // 60s QR timeout
        if (remaining == 0) {
          tft.fillScreen(COLOR_BG);
          tft.setTextSize(2); tft.setTextColor(COLOR_RED);
          tft.setCursor(70, 80); tft.print("TIMED OUT");
          tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
          tft.setCursor(50, 110); tft.print("Token expired. Press BTN1 to retry.");
          regQrDrawn = false;
          regTokenReceived = false;
        }
      }

      // Registration confirmed by backend
      if (deviceJustRegistered) {
        nvsPrefs.begin("smartbox", false);
        nvsPrefs.putBool("registered", true);
        nvsPrefs.end();
        deviceRegistered = true;
        displayMessage("REGISTERED!", "Connect WiFi in app");
        triggerCyberChirp(1);
        delay(2000);
        // Stay here until app pushes WiFi config
        // When applyHardwareConfig is received, firmware reboots
      }

      // Retry: BTN1 re-requests token
      if (!regTokenReceived && stateInitialized && !deviceJustRegistered &&
          millis() - stateStartTime > 10000 && !regQrDrawn) {
        if (digitalRead(BTN_RECEIVE) == LOW) {
          delay(50);
          if (digitalRead(BTN_RECEIVE) == LOW) {
            Serial.println("[SETUP] Retry: requesting new token.");
            emitRequestDeviceRegistration();
            stateStartTime = millis();
            displayMessage("TERMINAL", "Requesting...");
          }
        }
      }
      break;

    // ── IDLE ──────────────────────────────────────────────
    case IDLE:
      // --- Handle Long Press for SETTINGS (2s hold on BTN_RECEIVE) ---
      static unsigned long leftBtnHoldStart = 0;
      static bool leftBtnHolding = false;

      if (digitalRead(BTN_RECEIVE) == LOW) {
        if (!leftBtnHolding) {
          Serial.println("[DEBUG] BTN_RECEIVE (Pin 40) is LOW (Pressed)");
          leftBtnHoldStart = millis();
          leftBtnHolding = true;
        } else if (millis() - leftBtnHoldStart > 2000) {
          Serial.println("[SYSTEM] Long press detected → Entering SETTINGS_MENU.");
          triggerCyberChirp(3);
          leftBtnHolding = false; // Reset for next time
          changeState(SETTINGS_MENU);
          break;
        }
      } else {
        if (leftBtnHolding) {
          leftBtnHolding = false;
          // If released quickly (< 2s), treat as a normal click (Drop Off)
          if (millis() - leftBtnHoldStart < 2000) {
            Serial.println("[FLOW] User selected: DROP OFF.");
            isReceivingMode = true;
            isRiderMode     = false;
            triggerCyberChirp(3);
            changeState(WAITING_FOR_SCAN);
          }
        }
      }
      
      // Right button is still a simple click for PICK UP
      if (digitalRead(BTN_PICKUP) == LOW) {
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.println("[DEBUG] BTN_PICKUP (Pin 2) is LOW (Pressed)");
          Serial.println("[FLOW] User selected: PICK UP → showing sub-menu.");
          isReceivingMode = false;
          triggerCyberChirp(3);
          changeState(SELECTING_PICKUP_TYPE);
        }
      }

      // Added: 30s Inactivity Timeout to Lockscreen
      if (millis() - stateStartTime > IDLE_TIMEOUT_MS) {
        changeState(LOCKSCREEN);
      }
      break;

    // ── SELECTING PICKUP TYPE (ATM: Owner | Rider) ────────
    case SELECTING_PICKUP_TYPE:
      if (!stateInitialized) {
        drawPickupSelectScreen();
        Serial.println("[FLOW] Sub-menu: Waiting for Owner or Rider selection.");
        Serial.println("==========================================");
        Serial.println("  [BTN1] Owner        [BTN2] Rider");
        Serial.println("------------------------------------------");
        stateInitialized = true;
      } else if (digitalRead(BTN_RECEIVE) == LOW) {
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
          Serial.println("[FLOW] Sub-menu: OWNER selected → Requesting QR session.");
          isRiderMode = false;
          triggerCyberChirp(3);
          changeState(OWNER_VERIFYING);
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) {   // Right = Rider
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.println("[FLOW] Sub-menu: RIDER selected.");
          isRiderMode = true;
          triggerCyberChirp(3);
          changeState(RIDER_VERIFYING);
        }
      }
      break;

    // ── OWNER VERIFYING (show QR on LCD; wait for mobile app scan) ────
    case OWNER_VERIFYING:
      if (!stateInitialized) {
        ownerApprovalReceived = false;
        ownerApprovalValid    = false;
        ownerSessionToken[0]  = '\0';
        ownerQrDrawn          = false;
        ownerVerifyTimedOut   = false;
        stateStartTime        = millis();
        stateInitialized      = true;
        Serial.println("[FLOW] Owner QR: Requesting session token from server...");
        displayMessage("VERIFYING", "Connecting...");
        if (socketIO.isConnected()) {
          emitRequestOwnerSession();
        } else {
          Serial.println("[WARN] Owner QR: server offline, cannot generate QR.");
          displayMessage("OFFLINE", "No server");
          triggerCyberChirp(2);
          pendingNextState  = IDLE;
          actionDelayStart  = millis();
          actionDelayActive = true;
        }
      }

      // ── Retry/Exit prompt (shown after timeout) ──────────────
      if (ownerVerifyTimedOut && !actionDelayActive) {
        if (digitalRead(BTN_RECEIVE) == LOW) {      // BTN1 = Retry
          delay(50);
          if (digitalRead(BTN_RECEIVE) == LOW) {
            Serial.println("[FLOW] Owner QR: Retry pressed — requesting new session.");
            ownerVerifyTimedOut   = false;
            ownerApprovalReceived = false;
            ownerApprovalValid    = false;
            ownerSessionToken[0]  = '\0';
            ownerQrDrawn          = false;
            stateStartTime        = millis();
            displayMessage("VERIFYING", "Connecting...");
            if (socketIO.isConnected()) emitRequestOwnerSession();
            triggerCyberChirp(3);
          }
        } else if (digitalRead(BTN_PICKUP) == LOW) { // BTN2 = Exit
          delay(50);
          if (digitalRead(BTN_PICKUP) == LOW) {
            Serial.println("[FLOW] Owner QR: Exit pressed — returning to IDLE.");
            triggerCyberChirp(2);
            ownerVerifyTimedOut = false;
            changeState(IDLE);
          }
        }
        break; // Don't run timer checks while showing Retry/Exit prompt
      }

      // ── Session token received → draw QR once ───────────────
      if (strlen(ownerSessionToken) > 0 && !actionDelayActive) {
        if (!ownerQrDrawn) {
          drawOwnerVerifyingScreen(String(ownerSessionToken));
          ownerQrDrawn = true;
          stateStartTime = millis(); // restart 60s countdown from when QR is shown
          Serial.println("[FLOW] Owner QR: QR code displayed. Owner has 60s to scan.");
        }

        // Feature #5: Update countdown every second (overwrite only the timer area)
        static int lastCountdownSec = -1;
        int elapsed = (millis() - stateStartTime) / 1000;
        int remaining = max(0, 60 - elapsed);
        
        // --- Added: Real-time EXIT check (BTN2) while QR is displayed ---
        if (digitalRead(BTN_PICKUP) == LOW && !actionDelayActive) {
          delay(50);
          if (digitalRead(BTN_PICKUP) == LOW) {
            Serial.println("[FLOW] Owner QR: Exit pressed — returning to IDLE.");
            triggerCyberChirp(2);
            ownerQrDrawn        = false;
            ownerVerifyTimedOut = false;
            changeState(IDLE);
            return; // Exit state handler immediately
          }
        }
        if (remaining != lastCountdownSec) {
          lastCountdownSec = remaining;
          // Overwrite just the bottom line — white bg, black text (QR screen colors)
          tft.fillRect(0, 218, 320, 22, COLOR_TEXT);
          tft.setTextSize(1); tft.setTextColor(COLOR_BG);
          tft.setCursor(100, 222);
          tft.print("Expires in "); tft.print(remaining); tft.print(" seconds");
        }
      }

      // ── Approval result from server ──────────────────────────
      if (ownerApprovalReceived && !actionDelayActive) {
        ownerApprovalReceived = false;
        if (ownerApprovalValid) {
          Serial.println("[FLOW] Owner QR: APPROVED by app scan.");
          displayMessage("VERIFIED", "Access Granted");
          triggerBuzzer(2);
          pendingNextState = OWNER_SELECTING_MODE;
        } else {
          Serial.println("[FLOW] Owner QR: DENIED by app.");
          displayMessage("DENIED", "Access Rejected");
          triggerCyberChirp(2);
          pendingNextState = IDLE;
        }
        actionDelayStart  = millis();
        actionDelayActive = true;
        ownerSessionToken[0] = '\0';
        ownerQrDrawn      = false;
      }

      // ── (A) 8s server non-response timeout ───────────────────
      if (!actionDelayActive && !ownerVerifyTimedOut &&
          strlen(ownerSessionToken) == 0 && !ownerQrDrawn &&
          stateInitialized && millis() - stateStartTime > 8000) {
        Serial.println("[FLOW] Owner QR: Server did not respond. Show Retry/Exit.");
        triggerCyberChirp(2);
        drawTimeoutScreen("TIMED OUT", "Server did not respond");
        ownerVerifyTimedOut = true;
        ownerSessionToken[0] = '\0';
        ownerQrDrawn        = false;
      }

      // ── (B) 60s scan timeout (owner didn't scan in time) ─────
      if (!ownerApprovalReceived && !actionDelayActive && !ownerVerifyTimedOut &&
          ownerQrDrawn && millis() - stateStartTime > 60000) {
        Serial.println("[FLOW] Owner QR: 60s scan timeout. Show Retry/Exit.");
        triggerCyberChirp(2);
        drawTimeoutScreen("TIMED OUT", "");
        ownerVerifyTimedOut = true;
        ownerSessionToken[0] = '\0';
        ownerQrDrawn         = false;
      }

      // ── Delayed state transition (after approved/denied) ─────
      if (actionDelayActive && millis() - actionDelayStart >= 2000) {
        actionDelayActive = false;
        changeState(pendingNextState);
        pendingNextState = IDLE;
      }
      break;

    // ── OWNER SELECTING MODE (ATM: Single | Multiple) ─────
    case OWNER_SELECTING_MODE:
      if (!stateInitialized) {
        drawOwnerModeScreen();
        Serial.println("[FLOW] Owner sub-menu: Single or Multiple?");
        Serial.println("==========================================");
        Serial.println("  [BTN1] Single       [BTN2] Multiple");
        Serial.println("------------------------------------------");
        stateInitialized = true;
      }
      if (digitalRead(BTN_RECEIVE) == LOW) {          // Left = Single
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
          Serial.println("[FLOW] Owner Mode: SINGLE pick up.");
          isMultiMode  = false;
          scannedCount = 0;
          triggerCyberChirp(3);
          changeState(OWNER_SCANNING);
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) {   // Right = Multiple
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.println("[FLOW] Owner Mode: MULTIPLE pick up.");
          isMultiMode  = true;
          scannedCount = 0;
          triggerCyberChirp(3);
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
        while (Serial2.available()) Serial2.read(); // Flush stale buffer
        stateInitialized = true;
      }
      
      // Feature: 60s Timeout while scanning
      if (millis() - stateStartTime > 60000 && !actionDelayActive) {
        pendingNextState = OWNER_SCANNING;
        changeState(SCAN_TIMEOUT_PROMPT);
        break;
      }
      
      // Feature: Manual EXIT via BTN_PICKUP (BTN2)
      if (digitalRead(BTN_PICKUP) == LOW && !actionDelayActive) {
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
           triggerBuzzer(2);
           changeState(IDLE);
           break;
        }
      }
      
      // Non-blocking Serial2 read: accumulate bytes until '\n'
      while (Serial2.available() && !actionDelayActive) {
        char c = (char)Serial2.read();
        if (c == '\n' || c == '\r') {
          // Manual trim and process
          int len = strlen(serial2Buffer);
          if (len > 2) {
             // Process the read tracking ID
             strncpy(currentTrackingId, serial2Buffer, sizeof(currentTrackingId)-1);
             currentTrackingId[sizeof(currentTrackingId)-1] = '\0';
             serial2Buffer[0] = '\0';
             scannedCount++;
             Serial.print("[FLOW] Owner scanned ID #"); Serial.print(scannedCount);
             Serial.print(": "); Serial.println(currentTrackingId);
             char msgBuf[32];
             snprintf(msgBuf, sizeof(msgBuf), "#%d %.15s", scannedCount, currentTrackingId);
             displayMessage("REGISTERED", msgBuf);
             triggerBuzzer(2);
             emitRegisterOwnerPickup(String(currentTrackingId));
             pendingNextState  = UNLOCKING_ENTRY;
             actionDelayStart  = millis();
             actionDelayActive = true;
          }
          serial2Buffer[0] = '\0';
        } else if (c >= 32 && c <= 126) {
          int len = strlen(serial2Buffer);
          if (len < sizeof(serial2Buffer) - 1) {
            serial2Buffer[len] = c;
            serial2Buffer[len+1] = '\0';
          }
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
        Serial.println("==========================================");
        Serial.println("  [BTN1] Add More     [BTN2] Done");
        Serial.println("------------------------------------------");
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
        while (Serial2.available()) Serial2.read(); // Flush stale buffer
        stateInitialized    = true;
        Serial.println("[FLOW] Rider: Waiting for Rider QR scan...");
      }

      // Feature: 60s Timeout while verifying
      if (millis() - stateStartTime > 60000 && !actionDelayActive) {
        pendingNextState = RIDER_VERIFYING;
        changeState(SCAN_TIMEOUT_PROMPT);
        break;
      }
      
      // Feature: Manual EXIT via BTN_PICKUP (BTN2)
      if (digitalRead(BTN_PICKUP) == LOW && !actionDelayActive) {
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
           triggerBuzzer(2);
           changeState(IDLE);
           break;
        }
      }

      // Non-blocking Serial2 read: accumulate bytes until '\n'
      while (Serial2.available() && !actionDelayActive) {
        char c = (char)Serial2.read();
        if (c == '\n' || c == '\r') {
          int len = strlen(serial2Buffer);
          if (len > 0) {
            String riderId = String(serial2Buffer);
            serial2Buffer[0] = '\0';
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
        } else if (c >= 32 && c <= 126) {
          int len = strlen(serial2Buffer);
          if (len < sizeof(serial2Buffer) - 1) {
            serial2Buffer[len] = c;
            serial2Buffer[len+1] = '\0';
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
        while (Serial2.available()) Serial2.read(); // Flush stale buffer
        stateInitialized = true;
      }

      // Feature: 60s Timeout while scanning parcels
      if (millis() - stateStartTime > 60000 && !actionDelayActive) {
        pendingNextState = RIDER_SCANNING_PARCELS;
        changeState(SCAN_TIMEOUT_PROMPT);
        break;
      }
      
      // Feature: Manual EXIT via BTN_PICKUP (BTN2)
      if (digitalRead(BTN_PICKUP) == LOW && !actionDelayActive) {
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
           triggerBuzzer(2);
           changeState(RIDER_PICKUP_PROMPT);
           break;
        }
      }

      // Non-blocking Serial2 read
      while (Serial2.available() && !actionDelayActive) {
        char c = (char)Serial2.read();
        if (c == '\n' || c == '\r') {
          int len = strlen(serial2Buffer);
          if (len > 0) {
            String scanned = String(serial2Buffer);
            serial2Buffer[0] = '\0';
            if (scanned.length() > 2 && scanned.indexOf('[') == -1 && scanned.indexOf(']') == -1) {
              scannedCount++;
              Serial.print("[FLOW] Rider scanned parcel #"); Serial.print(scannedCount);
              Serial.print(": "); Serial.println(scanned);
              emitStatusUpdate(scanned, "retrieved", "rider_collect");
              String label = "#" + String(scannedCount) + " " + scanned.substring(0, 10);
              displayMessage("SCANNED", label.c_str());
              triggerBuzzer(1);
              pendingNextState  = RIDER_PICKUP_PROMPT;
              actionDelayStart  = millis();
              actionDelayActive = true;
            }
          }
        } else if (c >= 32 && c <= 126) {
          int len = strlen(serial2Buffer);
          if (len < sizeof(serial2Buffer) - 1) {
            serial2Buffer[len] = c;
            serial2Buffer[len+1] = '\0';
          }
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
        Serial.println("==========================================");
        Serial.println("  [BTN1] Pick Up More [BTN2] Done");
        Serial.println("------------------------------------------");
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
        tft.setCursor(65, 190); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
        tft.print(isReceivingMode ? "Mode: DROP OFF" : "Mode: PICK UP");
        Serial.println("[FLOW] Waiting for scan data on Serial2...");
        while (Serial2.available()) Serial2.read(); // Flush hardware buffer
        serial2Buffer[0] = '\0';  // Clear software accumulator
        stateInitialized = true;
      }

      // Feature: 60s Timeout while dropping off
      if (millis() - stateStartTime > 60000 && !actionDelayActive) {
        pendingNextState = WAITING_FOR_SCAN;
        changeState(SCAN_TIMEOUT_PROMPT);
        break;
      }
      
      // Feature: Manual EXIT via BTN_PICKUP (BTN2)
      if (digitalRead(BTN_PICKUP) == LOW && !actionDelayActive) {
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
           triggerBuzzer(2);
           changeState(IDLE);
           break;
        }
      }

      // Non-blocking Serial2 read: accumulate bytes each loop tick
      while (Serial2.available() > 0) {
        char c = (char)Serial2.read();
        if (c == '\n' || c == '\r') {
          int len = strlen(serial2Buffer);
          if (len > 0) {
            String scanned = "";
            for (int i = 0; i < len; i++) {
              char ch = serial2Buffer[i];
              if (ch >= 32 && ch <= 126 && ch != '[' && ch != ']') scanned += ch;
            }
            serial2Buffer[0] = '\0';
            scanned.trim();
            if (scanned.length() < 3) break;

            strncpy(currentTrackingId, scanned.c_str(), sizeof(currentTrackingId)-1);
            String modeName = isReceivingMode ? "drop_off" : "pick_up";
            Serial.print("[FLOW] Scanned: "); Serial.println(scanned);

            String localID = String(isReceivingMode ? registeredDropOff : registeredPickup);
            
            if (localID.length() > 0 && scanned == localID) {
              Serial.println("[FLOW] LOCAL AUTHORIZATION: Match found in manual registry.");
              displayMessage("VALID ID", "LOCAL AUTH");
              triggerBuzzer(2);
              if (socketIO.isConnected()) {
                emitStatusUpdate(scanned, isReceivingMode ? "delivered" : "retrieved", modeName);
              }
              consecutiveScanFails = 0; 
              pendingNextState  = UNLOCKING_ENTRY;
              actionDelayStart  = millis();
              actionDelayActive = true;
            } 
            else if (socketIO.isConnected()) {
              Serial.println("[FLOW] No local match. Requesting server verification...");
              displayMessage("VERIFYING...", "Please wait");
              emitVerifyScan(scanned, modeName);
              scanResultReceived = false;
              scanResultValid    = false;
              changeState(VERIFYING_SCAN);
            } 
            else {
              Serial.println("[WARN] Offline and No local ID match.");
              displayMessage("INVALID ID", "RETRY SCAN");
              triggerCyberChirp(2);
              currentTrackingId[0] = '\0'; 
              consecutiveScanFails++;
              pendingNextState  = (consecutiveScanFails >= 3) ? SCAN_FAILED_PROMPT : WAITING_FOR_SCAN;
              actionDelayStart  = millis();
              actionDelayActive = true;
            }
          }
        } else if (c >= 32 && c <= 126 && c != '[' && c != ']') {
          int len = strlen(serial2Buffer);
          if (len < sizeof(serial2Buffer) - 1) {
            serial2Buffer[len] = c;
            serial2Buffer[len+1] = '\0';
          }
        }
      } // end while Serial2.available()

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
            tft.setFont(&FreeSansBold12pt7b);
            tft.setTextColor(COLOR_TEXT);
            tft.setCursor(25, 200);
            tft.print(isReceivingMode ? "Mode: DROP OFF" : "Mode: PICK UP");
            tft.setFont();
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
      
      // Feature: Real-time Processing Animation
      {
        static int scanPos = HUD_MARGIN + 30;
        static int scanDir = 5;
        tft.fillRect(scanPos, 140, 40, 4, COLOR_BG); // clear old
        scanPos += scanDir;
        if (scanPos > 240 || scanPos < 40) scanDir *= -1;
        drawScanningAnimation(140, COLOR_ACCENT);
        tft.fillRect(scanPos, 140, 10, 4, COLOR_GOLD); // moving dot
        triggerCyberChirp(3);
      }

      if (scanResultReceived && !actionDelayActive) {
        if (scanResultValid) {
          Serial.print("[FLOW] Server APPROVED ID: "); Serial.println(currentTrackingId);
          displayMessage("VALID ID", "Authorized Access");
          triggerBuzzer(2);
          consecutiveScanFails = 0; // Reset fails on success
          // Non-blocking 1s display pause before unlocking
          pendingNextState  = UNLOCKING_ENTRY;
          actionDelayStart  = millis();
          actionDelayActive = true;
        } else {
          Serial.print("[FLOW] Server REJECTED ID: "); Serial.println(currentTrackingId);
          displayMessage("REJECTED", "RETRY SCAN");
          triggerBuzzer(3);
          currentTrackingId[0]  = '\0';
          scanResultReceived = false;
          consecutiveScanFails++;
          pendingNextState   = (consecutiveScanFails >= 3) ? SCAN_FAILED_PROMPT : WAITING_FOR_SCAN;
          actionDelayStart   = millis();
          actionDelayActive  = true;
        }
      } else if (!actionDelayActive && millis() - stateStartTime > 8000) {
        // Timeout: 8 seconds
        Serial.println("[FLOW] Server verification timed out.");
        displayMessage("TIMEOUT", "RETRY SCAN");
        triggerBuzzer(3);
        currentTrackingId[0]  = '\0';
        consecutiveScanFails++;
        pendingNextState   = (consecutiveScanFails >= 3) ? SCAN_FAILED_PROMPT : WAITING_FOR_SCAN;
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

    case WAITING_PLACEMENT_STABLE:
      {
        if (!stateInitialized) {
          stateStartTime = millis();
          displayMessage("PLACEMENT", "Place on Tray");
          Serial.println("[FLOW] Waiting for placement (Fallback active).");
          stateInitialized = true;
        }

        // Logical Fallback: Proceed after 5 seconds OR if sensor detects OR if button pressed
        float d = getDistance(US_PLATFORM);
        if (millis() - stateStartTime > 5000 || (d > 1.0 && d <= 20.0) || digitalRead(BTN_RECEIVE) == LOW) {
          Serial.println("[FLOW] Parcel confirmed (Fallback/Detect). Tilting...");
          triggerBuzzer(2);
          changeState(TILTING_PLATFORM);
        }
      }
      break;

    // ── TILTING PLATFORM ──────────────────────────────────
    case TILTING_PLATFORM: {
      if (!stateInitialized) {
        int tiltAngle = isReceivingMode ? 30 : 150; 
        Serial.print("[FLOW] Tilting to "); Serial.print(isReceivingMode ? "DROP-OFF (30)" : "PICKUP (150)");
        Serial.println(" bin.");
        
        updateProcessingHUD(isReceivingMode ? "DROPPING..." : "PICKUP TILT...");
        shakeServo(tiltAngle); // sets target
        stateStartTime = millis();
        stateInitialized = true;
      }
      if (millis() - stateStartTime > 5000) {
        changeState(CONFIRMING_DROP);
      }
      break;
    }

    // ── CONFIRMING DROP ───────────────────────────────────
    case CONFIRMING_DROP:
      {
        if (!stateInitialized) {
          String newStatus = isReceivingMode ? "delivered" : "awaiting_pickup";
          String modeStr   = isReceivingMode ? "drop_off"  : "pick_up";

          // LOGICAL FALLBACK: We trust the physical drop cycle and force +1 / -1
          displayMessage("SUCCESS", "Stored Safely");
          Serial.println("[FLOW] Parcel drop confirmed (Logical Fallback).");
          triggerBuzzer(2);
          
          // Notify backend → marks DB as delivered/retrieved
          if (strlen(currentTrackingId) > 0) {
            emitStatusUpdate(String(currentTrackingId), newStatus, modeStr);
          }
          
          actionDelayStart  = millis();   
          actionDelayActive = true;
          stateInitialized  = true;
        }
        if (actionDelayActive && millis() - actionDelayStart >= 3000) {
          actionDelayActive = false;
          if (!isReceivingMode && !isRiderMode && isMultiMode) {
            changeState(OWNER_ADD_MORE_PROMPT);
          } else {
            changeState(RESETTING);
          }
        }
      }
      break;
      break;

    // ── SCAN FAILED PROMPT ────────────────────────────────
    case SCAN_FAILED_PROMPT:
      if (!stateInitialized) {
        drawScanFailedPrompt();
        Serial.println("[FLOW] Scan failed 3 times! Sub-menu: Retry or Exit.");
        Serial.println("==========================================");
        Serial.println("  [BLUE] Retry        [RED] Exit");
        Serial.println("------------------------------------------");
        stateInitialized = true;
      }
      if (digitalRead(BTN_RECEIVE) == LOW) {         // Left = Retry (Blue)
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
          Serial.println("[FLOW] Retry Scan.");
          consecutiveScanFails = 0;
          triggerBuzzer(1);
          changeState(WAITING_FOR_SCAN);
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) {  // Right = Exit (Red)
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.println("[FLOW] Exiting to Idle.");
          triggerBuzzer(1);
          changeState(RESETTING);
        }
      }
      break;

    // ── SCAN TIMEOUT PROMPT ────────────────────────────────
    case SCAN_TIMEOUT_PROMPT:
      if (!stateInitialized) {
        drawTimeoutScreen("TIMED OUT", "");
        triggerBuzzer(3);
        Serial.println("[FLOW] Prompt: Scan Timed Out. Retry or Exit?");
        stateInitialized = true;
      }
      if (digitalRead(BTN_RECEIVE) == LOW) {
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
          triggerBuzzer(1);
          consecutiveScanFails = 0;
          changeState(pendingNextState); // Return to whichever state timed out
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) {
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          triggerBuzzer(2);
          changeState(RESETTING);
        }
      }
      break;

    // ── LOCKSCREEN ────────────────────────────────────────
    case LOCKSCREEN:
      if (!stateInitialized) {
        tft.fillScreen(COLOR_BG);
        stateInitialized = true;
        showingText   = false;
        isBlinking    = false;
        currentEmotion = NEUTRAL;
        currentOffsetX = 0;
        targetOffsetX = 0;
        nextBlinkTime = millis() + random(3000, 10000);
        lastEmotionTime = millis() + 5000;
        nextTextTime  = millis() + 60000; // Face for 60s
        lastMoveTime  = millis() + 2000; 
        drawRobotEyeLockscreen(160, 120, 0, false, NEUTRAL);
      }
      
      // ANY button press wakes it up
      if (digitalRead(BTN_RECEIVE) == LOW || digitalRead(BTN_PICKUP) == LOW) {
        delay(50); // Debounce
        triggerBuzzer(1);
        changeState(IDLE);
        break;
      }

      if (showingText) {
        if (millis() > nextTextTime) {
          showingText = false;
          nextTextTime = millis() + 60000; 
          tft.fillScreen(COLOR_BG);
          drawRobotEyeLockscreen(160, 120, currentOffsetX, false, currentEmotion);
        }
      } else {
        // Face Mode: Check if it's time for text (after 60s)
        if (millis() > nextTextTime) {
          showingText = true;
          nextTextTime = millis() + 5000; 
          drawLockscreenText("Smart Parcel", "Dropbox");
        } else {
          // Central Animation Tick (10 FPS for Zero Flicker)
          if (millis() - lastLockscreenUpdate > 100) {
            lastLockscreenUpdate = millis();
            bool needsRedraw = false;

            // 1. Random Emotion change
            if (millis() > lastEmotionTime) {
              lastEmotionTime = millis() + random(7000, 15000);
              currentEmotion = (RobotEmotion)random(4);
              needsRedraw = true;
            }

            // 2. Slow Blink (300ms duration)
            bool blinkNow = (millis() >= nextBlinkTime && millis() < nextBlinkTime + 300);
            if (blinkNow != isBlinking) {
              isBlinking = blinkNow;
              needsRedraw = true;
              if (!isBlinking) nextBlinkTime = millis() + random(5000, 15000);
            }

            // 3. Slow Scan Logic (only move if NOT blinking)
            if (!isBlinking && currentEmotion != WINK) {
              if (millis() > lastMoveTime) {
                 int r = random(3);
                 targetOffsetX = (r == 0) ? -25 : (r == 1) ? 25 : 0; 
                 lastMoveTime = millis() + random(3000, 7000);
              }
              if (currentOffsetX != targetOffsetX) {
                // Calm, visible steps
                if (currentOffsetX < targetOffsetX) currentOffsetX += 5;
                else if (currentOffsetX > targetOffsetX) currentOffsetX -= 5;
                needsRedraw = true;
              }
            }

            // 4. Redraw Face area (only if changed)
            if (needsRedraw) {
              tft.fillRect(160-95, 120-40, 190, 85, COLOR_BG); 
              drawRobotEyeLockscreen(160, 120, currentOffsetX, isBlinking, currentEmotion);
            }
          }
        }
      }
      break;
    
    // ── SETTINGS MENU ─────────────────────────────────────
    case SETTINGS_MENU:
      if (!stateInitialized) {
        drawSettingsMenu();
        Serial.println("[SETTINGS] System Menu: BTN1=Add User, BTN2=Back.");
        stateInitialized = true;
      }
      if (digitalRead(BTN_RECEIVE) == LOW) {   // BTN1 = Register (Add User)
        delay(50);
        if (digitalRead(BTN_RECEIVE) == LOW) {
           Serial.println("[SETTINGS] User requested re-registration.");
           triggerBuzzer(1);
           emitRequestDeviceRegistration();
           changeState(SHOWING_REGISTRATION_QR);
        }
      } else if (digitalRead(BTN_PICKUP) == LOW) { // BTN2 = Back
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
           triggerCyberChirp(2);
           changeState(IDLE);
        }
      }
      break;

    // ── RESETTING ─────────────────────────────────────────
    case RESETTING: {
       if (!stateInitialized) {
         Serial.println("[FLOW] Resetting platform and locks.");
         triggerBuzzer(1);
         digitalWrite(LOCK_TOP,      HIGH);
         digitalWrite(LOCK_PICKUP,   HIGH);
         digitalWrite(LOCK_RECEIVED, HIGH);
         lockTopOpen = false; lockPickupOpen = false; lockReceivedOpen = false;
         emitDoorState(); 
         
         moveServoSmoothly(90); 
         currentTrackingId[0] = '\0';
         scanResultReceived  = false;
         isRiderMode         = false;
         isMultiMode         = false;
         scannedCount        = 0;
         consecutiveScanFails= 0;
         riderVerifyReceived = false;
         riderVerifyValid    = false;
         
         stateStartTime = millis();
         stateInitialized = true;
       }
       if (millis() - stateStartTime > 3000) {
         changeState(IDLE);
         showHomeScreen();
       }
       break;
    }
  } // end switch
} // end loop

// ============================================================
//  HELPER: checkFactoryReset
//  Hold BTN_PICKUP for 5 seconds from IDLE/normal states to wipe NVS
// ============================================================
void checkFactoryReset() {
  if (currentState == DEVICE_UNREGISTERED || currentState == SHOWING_REGISTRATION_QR) return;
  static unsigned long holdStart = 0;
  static bool          holding   = false;
  if (digitalRead(BTN_PICKUP) == LOW) {
    if (!holding) { holding = true; holdStart = millis(); }
    else if (millis() - holdStart > 5000) {
      Serial.println("[FACTORY RESET] BTN_PICKUP held 5s → wiping NVS and rebooting!");
      tft.fillScreen(COLOR_BG);
      tft.setTextSize(2); tft.setTextColor(COLOR_RED);
      tft.setCursor(50, 90); tft.print("FACTORY RESET");
      tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
      tft.setCursor(75, 120); tft.print("Wiping settings...");
      nvsPrefs.begin("smartbox", false);
      nvsPrefs.clear();
      nvsPrefs.end();
      delay(2000);
      ESP.restart();
    }
  } else {
    holding = false;
  }
}

// ============================================================
//  EMIT: Request Device Registration (hardware → backend)
// ============================================================
void emitRequestDeviceRegistration() {
  String macAddr = WiFi.macAddress();
  bool connected = (WiFi.status() == WL_CONNECTED);
  
  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("requestDeviceRegistration");
  
  JsonObject data = arr.createNestedObject();
  data["deviceId"] = macAddr;
  data["alreadyConnected"] = connected;
  
  char output[256];
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output);
  Serial.print("[WS] Emitted requestDeviceRegistration: "); 
  Serial.print(macAddr);
  Serial.print(" (alreadyConnected: "); 
  Serial.print(connected ? "true" : "false");
  Serial.println(")");
}

// (Redundant handleApplyHardwareConfig removed; now centralized in NetworkController2.ino)

// ============================================================
//  SCREEN: Device Unregistered (first boot)
// ============================================================
// (QR screens moved to DisplayController.ino)

// (drawScannerBg moved to DisplayController.ino)


// ============================================================
//  WIFI SETUP
// ============================================================
// (Network logic moved to NetworkController*.ino)

// ============================================================
//  UTILS
// ============================================================
// (getDistance moved to HardwareController.ino)

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
          strncpy(registeredDropOff, newId.c_str(), sizeof(registeredDropOff)-1);
          registeredDropOff[sizeof(registeredDropOff)-1] = '\0';
          dropOffRegisterTime = millis();
          Serial.print("[REG] Drop Off ID (manual): "); Serial.println(registeredDropOff);
        } else if (slot == '2') {
          strncpy(registeredPickup, newId.c_str(), sizeof(registeredPickup)-1);
          registeredPickup[sizeof(registeredPickup)-1] = '\0';
          pickupRegisterTime = millis();
          Serial.print("[REG] Pick Up ID (manual): "); Serial.println(registeredPickup);
        } else {
          Serial.println("[REG] Invalid slot. Use R1:<id> or R2:<id>");
        }
      } else {
        Serial.println("[REG] Format: R1:<tracking_id> or R2:<tracking_id>");
      }
    } else if (cmd == 'V') {
      Serial.println("[REG] === Registered IDs ===");
      Serial.print("  Drop Off : "); Serial.println(strlen(registeredDropOff) ? registeredDropOff : "(none)");
      Serial.print("  Pick Up  : "); Serial.println(strlen(registeredPickup)  ? registeredPickup  : "(none)");
      Serial.print("  WiFi     : "); Serial.println(WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString() : "Not connected");
      Serial.print("  Server   : "); Serial.println(socketIO.isConnected() ? "Connected" : "Disconnected");
    } else if (cmd == 'M') {
      Serial.println("\n[DIAG] === Full Hardware Monitor ===");
      // Reed Status: 0 = Magnet Near (Closed), 1 = Magnet Away (Open)
      int r1 = digitalRead(REED_TOP);
      int r2 = digitalRead(REED_PICKUP);
      int r3 = digitalRead(REED_RECEIVED);
      Serial.print("  Reed TOP      : "); Serial.println(r1 == 0 ? "CLOSED (Locked)" : "OPEN (Unlocked)");
      Serial.print("  Reed PICKUP   : "); Serial.println(r2 == 0 ? "CLOSED" : "OPEN");
      Serial.print("  Reed RECEIVED : "); Serial.println(r3 == 0 ? "CLOSED" : "OPEN");
      
      // Ultrasonic Sensors
      float d1 = getDistance(US_PLATFORM);
      float d2 = getDistance(US_PICKUP);
      float d3 = getDistance(US_DROPOFF);
      Serial.print("  US1 Platform  : "); Serial.println(d1 < 900 ? String(d1,1)+"cm" : "OUT_OF_RANGE");
      Serial.print("  US2 Pickup    : "); Serial.println(d2 < 900 ? String(d2,1)+"cm" : "OUT_OF_RANGE");
      Serial.print("  US3 DropOff   : "); Serial.println(d3 < 900 ? String(d3,1)+"cm" : "OUT_OF_RANGE");
      Serial.print("  Solenoid TOP  : "); Serial.println(lockTopOpen ? "UNLOCKED" : "LOCKED");
      Serial.println("[DIAG] Done.\n");
    } else if (cmd == 'W') {
      Serial.println("[DIAG] === Network Status ===");
      Serial.print("  WiFi SSID  : "); Serial.println(WiFi.SSID());
      Serial.print("  WiFi IP    : "); Serial.println(WiFi.localIP());
      Serial.print("  WiFi RSSI  : "); Serial.print(WiFi.RSSI()); Serial.println(" dBm");
      Serial.print("  Server     : ws://"); Serial.print(SERVER_HOST); Serial.print(":"); Serial.println(SERVER_PORT);
      Serial.print("  Socket.IO  : "); Serial.println(socketIO.isConnected() ? "Connected" : "Disconnected");
    } else if (cmd == 'N') {
      // N alone → forceNextStep (bypass current state)
      // N:<token> → simulate scanning that token (for registration or owner verify)
      if (input.length() > 2 && input.charAt(1) == ':') {
        String token = input.substring(2);
        token.trim();
        if (currentState == DEVICE_UNREGISTERED || currentState == SHOWING_REGISTRATION_QR) {
          // Simulate receiving a registration token (e.g. N:SPDB-REG-482913)
          strncpy(registrationToken, token.c_str(), sizeof(registrationToken)-1);
          registrationToken[sizeof(registrationToken)-1] = '\0';
          regTokenReceived  = true;
          Serial.print("[DEV] Simulated registrationToken: "); Serial.println(token);
        } else if (currentState == OWNER_VERIFYING) {
          // Simulate owner approve via token entry
          ownerApprovalValid    = true;
          ownerApprovalReceived = true;
          Serial.print("[DEV] Simulated ownerVerifyResult APPROVED for token: "); Serial.println(token);
        } else {
          Serial.println("[DEV] N:<token> not applicable in current state.");
        }
      } else {
        Serial.println("[MANUAL] Bypassing current step...");
        forceNextStep();
      }
    } else if (cmd == 'X') {
      isScannerTestActive = true;
      scannerTestStartTime = millis();
      Serial.println("[TEST] PASSIVE SCAN TEST ACTIVE: Waiting for data...");
      Serial.println("[HINT] Trigger the scanner manually (hand proximity or Arduino USB 'T').");
    } else if (cmd == 'T') {
      Serial.println("[MANUAL] Re-initializing TFT Display...");
      reinitTFT();
    } else if (cmd == 'C') {
      Serial.println("[MANUAL] Triggering WiFi Captive Portal...");
      triggerBuzzer(2);
      changeState(WAITING_FOR_WIFI_CONFIG);
    } else if (cmd == '1') {
      Serial.println("[TEST] Tilting to DROP OFF bin (0°) + Shake...");
      moveServoSmoothly(0);
      delay(500);
      shakeServo(0);
      moveServoSmoothly(0);
      Serial.println("[TEST] Done.");
    } else if (cmd == '2') {
      Serial.println("[TEST] Tilting to PICKUP bin (180°) + Shake...");
      moveServoSmoothly(180);
      delay(500);
      shakeServo(180);
      moveServoSmoothly(180);
      Serial.println("[TEST] Done.");
    }
  }
}

// (TFT reinit and update indicators moved to DisplayController3.ino)

void forceNextStep() {
  switch (currentState) {
    case SELECTING_PICKUP_TYPE:
      Serial.println("[FLOW] Bypass: Defaulting to OWNER mode → entering OWNER_VERIFYING.");
      isRiderMode = false;
      changeState(OWNER_VERIFYING);
      break;
    case OWNER_VERIFYING:
      // Simulate approved mobile app scan without needing the physical QR scanner
      Serial.println("[FLOW] Bypass: Owner verification APPROVED via serial shortcut.");
      ownerApprovalValid    = true;
      ownerApprovalReceived = true;
      // The state loop will pick up ownerApprovalReceived and proceed to OWNER_SELECTING_MODE
      break;
    case OWNER_SELECTING_MODE:
      Serial.println("[FLOW] Bypass: Defaulting to SINGLE mode.");
      isMultiMode = false; scannedCount = 0;
      changeState(OWNER_SCANNING);
      break;
    case OWNER_SCANNING:
      Serial.println("[FLOW] Bypass: Skipping owner scan.");
      changeState(UNLOCKING_ENTRY);
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

// (drawButtonLabel moved)

void printSerialMenu() {
  Serial.println();
  Serial.println("==========================================");
  Serial.println("     SMART PARCEL DROPBOX SYSTEM");
  Serial.println("==========================================");
  Serial.println("  [BLUE] Drop Off     [RED] Pick Up");
  Serial.println("------------------------------------------");
  Serial.println("  S=Reset  | U=Unlock All | D=US Diag | M=Monitor | N=Next | T=TFT Reset | C=WiFi | X=Scan Test");
  Serial.println("  1=Test DropOff (0°)  | 2=Test Pickup (180°)");
  Serial.println("  V=View IDs & Status   | W=Network Info");
  Serial.println("  R1:<id> = Register Drop Off ID (offline)");
  Serial.println("  R2:<id> = Register Pick Up ID  (offline)");
  Serial.println("  N:<token>  = Simulate QR scan (dev bypass)");
  Serial.println("     e.g.  N:SPDB-REG-482913  (registration)");
  Serial.println("           N:OWN-482913        (owner verify)");
  Serial.println("  IDs auto-registered via mobile app (online)");
  Serial.println("==========================================");
  Serial.println();
}

void changeState(SystemState newState) {
  currentState     = newState;
  stateStartTime   = millis();
  lastStateChangeTime = millis();
  stateInitialized = false;
  tft.fillScreen(COLOR_BG);
  
  if (newState == IDLE || newState == LOCKSCREEN) {
    moveServoSmoothly(90);
    showHomeScreen();
  }
}

// (moveServoSmoothly and triggerBuzzer moved to HardwareController.ino)

// (All displayMessage and drawScreen routines moved to DisplayController.ino)