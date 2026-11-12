/*
 * SMART PARCEL DROPBOX - ESP32-S3 Main Controller
 * 
 * Reed Status: 0 = Magnet Near (Closed), 1 = Magnet Away (Open)
 * Solenoids:   Active LOW (LOW = Unlock)
 * 
 * Network: Connects to WiFi and communicates with backend via Socket.IO
 * 
 * Required Libraries (Arduino Library Manager):
 *   - Adafruit GFX        (by Adafruit)
 *   - Adafruit ILI9341    (by Adafruit)
 *   - arduinoWebSockets   (by Markus Sattler) — provides SocketIOclient
 *   - ArduinoJson         (by Benoit Blanchon, v6.x)
 */

#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
#include <SPI.h>
#include "qrcode.h"       // Local copy — avoids ESP32 core qrcode symbol conflict
#define DEBUG_WS      false // Toggle for verbose Socket.IO logs
#define DEBUG_SERIAL  true

#include <WiFi.h>
#include <WiFiClientSecure.h> // Required for WSS
#include <SocketIOclient.h>
#include <ArduinoJson.h>
#include <esp_task_wdt.h> // ESP32 Task Watchdog Timer
#include <esp_timer.h>
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
#include "BleController.h"

// ============================================================
//  FORWARD DECLARATIONS
// ============================================================
void setupWiFi();
void setupSocketIO();
void socketIOEvent(socketIOmessageType_t type, uint8_t* payload, size_t length);
void emitVerifyScan(const String& trackingId, const String& mode);
void emitVerifyRider(const String& riderId);
void emitStatusUpdate(const String& trackingId, const String& status, const String& mode);
void emitDoorState();
void sendDeviceHeartbeat(bool immediate);
void handleRegisterTracking(const String& payload);
void handleScanResult(const String& payload);
void handleRiderVerifyResult(const String& payload);
void handleControlDoor(const String& payload);
float getDistance(const int pins[]);
void emitRequestDeviceRegistration();
void drawRegistrationQRScreen(const String& token, const String& pin);
void drawSettingsMenu();
void drawNoServerOptionsScreen();
void checkFactoryReset();
void checkSerialCommands();
void forceNextStep();
void printSerialMenu();
void showHomeScreen();
void drawStatusBar();
void drawQRCode(int x, int y, int moduleSize, const String& text);
void drawScannerBg();
void drawScanFailedPrompt();
void drawIconLock(int x, int y, uint16_t color, bool open);
void drawIconBox(int x, int y, uint16_t color);
void drawIconCheck(int x, int y, uint16_t color);
void drawIconX(int x, int y, uint16_t color);
void drawWiFiSignal(int x, int y, uint16_t color);
void reinitTFT();

// --- Non-blocking Hardware Hooks ---
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

// ============================================================
//  SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000);

  Serial.println("\n--- [SYSTEM STARTUP] ---");

  // --- SAFE HARDWARE INIT ---
  // Ensure solenoids and buzzer don't float and trigger during microcontroller boot
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW); // Assumes HIGH = beep

  pinMode(LOCK_TOP,      OUTPUT); digitalWrite(LOCK_TOP,      HIGH); // HIGH = Locked (Active-LOW relay)
  setPickupLock(false);                                              // Hi-Z Mode = Locked (for 5V solo relay on 3.3V GPIO38)
  pinMode(LOCK_RECEIVED, OUTPUT); digitalWrite(LOCK_RECEIVED, HIGH); // HIGH = Locked (Active-LOW relay)

  // Inputs
  pinMode(BTN_RECEIVE,   INPUT_PULLUP);
  pinMode(BTN_PICKUP,    INPUT_PULLUP);
  pinMode(REED_TOP,      INPUT_PULLUP);
  pinMode(REED_PICKUP,   INPUT_PULLUP);
  pinMode(REED_RECEIVED, INPUT_PULLUP);

  // Watchdog initialization will be moved to the end of setup() to prevent reboots during WiFi sync

  // Active Ultrasonic Sensor: US_DROPOFF
  // (GPIO 15, 4 for Platform and GPIO 7, 16 for Pickup are available free pins)
  pinMode(US_DROPOFF[0],  OUTPUT);
  pinMode(US_DROPOFF[1],  INPUT_PULLDOWN);
  digitalWrite(US_DROPOFF[0],  LOW);
  delay(50); // Give the sensor and pull-down time to stabilize
  float initDrop = getDistance(US_DROPOFF);
  if (initDrop < 900.0) {
    dropoffBaselineDist = initDrop;
    Serial.print("[BOOT] DropOff bin baseline: "); Serial.print(dropoffBaselineDist, 1); Serial.println(" cm");
  }

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
  tft.begin(TFT_SPI_FREQ); // Noise-damped SPI clock for ground noise immunity
  tft.setRotation(3);
  tft.fillScreen(COLOR_BG);

  // Network — load credentials from NVS first
  loadWifiCredentials();
  nvsPrefs.begin("smartbox", false);
  deviceRegistered = nvsPrefs.getBool("registered", false);
  nvsPrefs.end();

  Serial.print("[NVS] Registered: "); Serial.println(deviceRegistered ? "YES" : "NO");
  Serial.print("[NVS] SSID: "); Serial.println(strlen(nvsWifiSSID) ? nvsWifiSSID : "(none)");

  if (strlen(nvsWifiSSID) > 0 || strlen(WIFI_SSID) > 0) {
    setupWiFi();
    setupSocketIO();
  } else {
    Serial.println("[BOOT] No saved SSID or config.h WiFi credentials. Connect via app registration.");
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
  const bool localBle = currentState == WAITING_FOR_WIFI_CONFIG || currentState == WAITING_FOR_BLE_UNLOCK;
  if (!localBle) {
    socketIO.loop();
    sendDeviceHeartbeat(false);
  }
  // esp_task_wdt_reset(); // Disabled to prevent "task not found" spam after detaching main loop
  processSensors();
  
  if (!localBle) checkSerialCommands();

  // Continuous Ultrasonic Live Stream (toggled via 'D' command)
  static unsigned long lastUsStreamTime = 0;
  if (isUsDiagContinuousActive && (millis() - lastUsStreamTime >= 250)) {
    lastUsStreamTime = millis();
    float d3 = getDistance(US_DROPOFF);
    Serial.print("[US LIVE] DropOff: ");
    if (d3 < 900.0) {
      Serial.print(d3, 1);
      Serial.print(" cm");
      if (dropoffBaselineDist < 900.0) {
        Serial.print(" (Base: ");
        Serial.print(dropoffBaselineDist, 1);
        Serial.print("cm)");
      }
      Serial.print("\t");
    } else {
      Serial.print("OUT_OF_RANGE\t");
    }
    Serial.println("| Platform & Pickup: DISABLED (Hardware Removed)");
  }

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
  } else if (!cooldownActive && currentState != WAITING_FOR_SCAN) {
    // Regular Drainage: Clear buffer when NOT in a scan-expectant state
    while (Serial2.available() > 0) Serial2.read();
    serial2Buffer[0] = '\0'; 
  }

  // Inter-character noise filter: if partial data in serial2Buffer sits for > 300ms without \n or \r, clear noise
  static unsigned long lastSerial2ByteTime = 0;
  if (serial2Buffer[0] != '\0' && millis() - lastSerial2ByteTime > 300) {
    serial2Buffer[0] = '\0';
  }
  // Skip status-bar repaints while QR verification screens, WiFi setup, or lockscreen are up
  if (currentState != SHOWING_REGISTRATION_QR && !localBle && currentState != LOCKSCREEN) {
    updateDynamicIndicators();
  }

  // Avoid interrupting a BLE Wi-Fi connection attempt.
  unsigned long currentMillisMillis = millis();
  if (!localBle && currentState != DEVICE_UNREGISTERED &&
      WiFi.status() != WL_CONNECTED && (currentMillisMillis - previousMillisWiFi >= intervalWiFi)) {
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
          triggerBuzzer(1);
          if (WiFi.status() != WL_CONNECTED) {
            changeState(WAITING_FOR_WIFI_CONFIG);
            break;
          }
          Serial.println("[SETUP] BTN1 pressed. Requesting registration token from server...");
          // Ensure network is connected before requesting registration
          if (!cloudDeviceAuthenticated()) {
            Serial.println("[SETUP] Not connected. Attempting WiFi/Socket setup...");
            displayMessage("CONNECTING", "Please wait...");
            setupSocketIO();
            
            // Wait for connection (up to 30s) - Cloud SSL takes ~25s
            Serial.println("[WS] Waiting for cloud handshake...");
            unsigned long startWait = millis();
            while (!cloudDeviceAuthenticated() && millis() - startWait < 30000) {
              socketIO.loop();
              if ((millis() - startWait) % 1000 < 100) {
                Serial.print(".");
              }
              delay(50);
            }
            Serial.println();
          }

          if (cloudDeviceAuthenticated()) {
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

    case WAITING_FOR_WIFI_CONFIG:
    case WAITING_FOR_BLE_UNLOCK: {
      static bool cancelArmed;
      static bool cancelPressed;
      if (!stateInitialized) {
        const bool wifi = currentState == WAITING_FOR_WIFI_CONFIG;
        if (!startLocalBle(wifi ? LocalBleMode::wifi : LocalBleMode::unlock)) {
          changeState(deviceRegistered ? IDLE : DEVICE_UNREGISTERED);
          displayMessage("BLUETOOTH UNAVAILABLE", wifi ? "Try setup again" : "Connect to server first");
          break;
        }
        cancelArmed = false;
        cancelPressed = false;
        stateInitialized = true;
      }
      const bool redPressed = digitalRead(BTN_PICKUP) == LOW;
      if (redPressed && cancelArmed) cancelPressed = true;
      if (!pollLocalBle() || (cancelPressed && !redPressed)) {
        stopLocalBle();
        changeState(deviceRegistered ? IDLE : DEVICE_UNREGISTERED);
      } else if (!redPressed) {
        cancelArmed = true;
      }
      break;
    }

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
        deviceJustRegistered = false; // Reset one-time flag immediately
        nvsPrefs.begin("smartbox", false);
        nvsPrefs.putBool("registered", true);
        nvsPrefs.end();
        deviceRegistered = true;
        displayMessage("REGISTERED!", "Device Paired");
        triggerCyberChirp(1);
        delay(1500);

        // If WiFi is already online and connected, transition to operational home screen
        if (WiFi.status() == WL_CONNECTED && socketIO.isConnected()) {
          showHomeScreen();
          changeState(IDLE);
        } else {
          displayMessage("REGISTERED!", "Connect WiFi in app");
        }
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
            // Lock in baseline distance of DropOff bin
            if (lastUsDropoffDist < 900.0) {
              dropoffBaselineDist = lastUsDropoffDist;
              Serial.print("[FLOW] DropOff bin baseline locked: ");
              Serial.print(dropoffBaselineDist, 1);
              Serial.println(" cm");
            }
            triggerCyberChirp(3);
            changeState(WAITING_FOR_SCAN);
          }
        }
      }

      // Periodically calibrate DropOff bin baseline when idle
      static unsigned long lastBaselineTrack = 0;
      if (millis() - lastBaselineTrack > 4000) {
        lastBaselineTrack = millis();
        if (lastUsDropoffDist < 900.0 && (dropoffBaselineDist >= 900.0 || abs(lastUsDropoffDist - dropoffBaselineDist) < 3.0)) {
          dropoffBaselineDist = lastUsDropoffDist;
        }
      }
      
      // Right button is a simple click for PICK UP
      if (digitalRead(BTN_PICKUP) == LOW) {
        delay(50);
        if (digitalRead(BTN_PICKUP) == LOW) {
          Serial.println("[DEBUG] BTN_PICKUP (Pin 2) is LOW (Pressed)");
          Serial.println("[FLOW] User selected: PICK UP → entering WAITING_FOR_SCAN.");
          isReceivingMode = false;
          isRiderMode     = false;
          triggerCyberChirp(3);
          changeState(WAITING_FOR_SCAN);
        }
      }

      // Added: 30s Inactivity Timeout to Lockscreen
      if (millis() - stateStartTime > IDLE_TIMEOUT_MS) {
        changeState(LOCKSCREEN);
      }
      break;

    // ── PICKUP DOOR OPEN (unlock pickup compartment, wait open+close) ──────
    case PICKUP_DOOR_OPEN:
      if (!stateInitialized) {
        setPickupLock(true);              // Unlock pickup compartment (Hi-Z/GND mode)
        emitDoorState();
        displayMessage("UNLOCKED", "Collect & Close Door");
        doorWasOpened     = false;
        stateInitialized  = true;
        actionDelayActive = false;
        scannedCount      = 0;
        triggerBuzzer(2);
        Serial.println("[FLOW] Pickup compartment UNLOCKED.");
      }
      if (readReedDebounced(REED_PICKUP) == 1 && !doorWasOpened) {
        Serial.println("[FLOW] Pickup compartment door OPENED. Retrieving parcel(s)...");
        doorWasOpened = true;
        triggerBuzzer(1);
      }
      if (doorWasOpened && readReedDebounced(REED_PICKUP) == 0 && !actionDelayActive) {
        setPickupLock(false);             // Re-lock (Hi-Z mode)
        emitDoorState();
        Serial.println("[FLOW] Pickup compartment door CLOSED → Locked. Pickup complete!");
        triggerBuzzer(1);
        triggerCyberChirp(1);
        displayMessage("SUCCESS", "Pickup Complete");

        // If a tracking ID was scanned for this pickup, notify server it was retrieved
        if (strlen(currentTrackingId) > 0) {
          emitStatusUpdate(String(currentTrackingId), "retrieved", "pick_up");
          currentTrackingId[0] = '\0';
        }
        // Clear offline registered pickup ID if present
        if (strlen(registeredPickup) > 0) {
          emitStatusUpdate(String(registeredPickup), "retrieved", "pick_up");
          registeredPickup[0] = '\0';
        }

        actionDelayStart  = millis();
        actionDelayActive = true;
      }

      if (actionDelayActive && (millis() - actionDelayStart >= 2500)) {
        actionDelayActive = false;
        changeState(RESETTING);
      }

      // Safety timeout: 30 seconds to prevent solenoid overheating if abandoned
      if (!actionDelayActive && (millis() - stateStartTime > 30000)) {
        setPickupLock(false);             // Ensure locked (Hi-Z mode)
        lockPickupOpen = false;
        emitDoorState();
        Serial.println("[FLOW] WARNING: Pickup door timed out (30s). Re-locking for thermal safety.");
        displayMessage("TIMEOUT", "Door Re-locked");
        triggerBuzzer(3);
        changeState(RESETTING);
      }
      break;

    // ── WAITING FOR SCAN ──────────────────────────────────
    case WAITING_FOR_SCAN:
      if (!stateInitialized) {
        tft.fillScreen(COLOR_BG);
        drawStatusBar();
        drawScannerBg();
        tft.setCursor(65, 185); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
        tft.print(isReceivingMode ? "Mode: DROP OFF" : "Mode: PICK UP");
        tft.setCursor(35, 210); tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
        tft.print(isReceivingMode ? "Scan Parcel Barcode" : "Scan Pass, Code or Rider ID");
        Serial.print("[FLOW] Waiting for scan data on Serial2 in mode: ");
        Serial.println(isReceivingMode ? "DROP OFF" : "PICK UP");
        while (Serial2.available()) Serial2.read(); // Flush hardware buffer
        serial2Buffer[0] = '\0';  // Clear software accumulator
        scanResultReceived = false;
        scanResultValid    = false;
        actionDelayActive  = false;
        stateInitialized   = true;
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
            // Discard Arduino Uno debug messages (e.g. "[TEST] ...")
            if (strchr(serial2Buffer, '[') != NULL || strchr(serial2Buffer, ']') != NULL) {
              serial2Buffer[0] = '\0';
              break;
            }
            String scanned = String(serial2Buffer);
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
              // BUG-04 Fix: Clear manual offline ID once consumed
              if (isReceivingMode) registeredDropOff[0] = '\0';
              else registeredPickup[0] = '\0';

              consecutiveScanFails = 0; 
              pendingNextState  = isReceivingMode ? UNLOCKING_ENTRY : PICKUP_DOOR_OPEN;
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
          lastSerial2ByteTime = millis();
          int len = strlen(serial2Buffer);
          if (len < sizeof(serial2Buffer) - 1) {
            serial2Buffer[len] = c;
            serial2Buffer[len+1] = '\0';
          }
        }
      } // end while Serial2.available()

      // Non-blocking delay: 1s pause → UNLOCKING_ENTRY/PICKUP_DOOR_OPEN (success), 2s → retry (fail/offline)
      if (actionDelayActive) {
        unsigned long pauseMs = (pendingNextState == UNLOCKING_ENTRY || pendingNextState == PICKUP_DOOR_OPEN) ? 1000 : 2000;
        if (millis() - actionDelayStart >= pauseMs) {
          actionDelayActive = false;
          if (pendingNextState == WAITING_FOR_SCAN) {
            // Redraw scanner UI before looping back
            tft.fillScreen(COLOR_BG);
            drawStatusBar();
            drawScannerBg();
            tft.setCursor(65, 185); tft.setTextSize(2); tft.setTextColor(COLOR_TEXT);
            tft.print(isReceivingMode ? "Mode: DROP OFF" : "Mode: PICK UP");
            tft.setCursor(35, 210); tft.setTextSize(1); tft.setTextColor(COLOR_GREY);
            tft.print(isReceivingMode ? "Scan Parcel Barcode" : "Scan Pass, Code or Rider ID");
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
        scanResultReceived = false;
        if (scanResultValid) {
          scanResultValid = false;
          Serial.print("[FLOW] Server APPROVED ID: "); Serial.println(currentTrackingId);
          displayMessage("VALID ID", "Authorized Access");
          triggerBuzzer(2);
          consecutiveScanFails = 0; // Reset fails on success
          // Non-blocking 1s display pause before unlocking
          pendingNextState  = isReceivingMode ? UNLOCKING_ENTRY : PICKUP_DOOR_OPEN;
          actionDelayStart  = millis();
          actionDelayActive = true;
        } else {
          Serial.print("[FLOW] Server REJECTED ID: "); Serial.println(currentTrackingId);
          displayMessage("REJECTED", "RETRY SCAN");
          triggerBuzzer(3);
          currentTrackingId[0]  = '\0';
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
      // Non-blocking pause: 1s (success → UNLOCK) or 2s (fail/timeout → WAITING_FOR_SCAN)
      if (actionDelayActive) {
        unsigned long pauseMs = (pendingNextState == UNLOCKING_ENTRY || pendingNextState == PICKUP_DOOR_OPEN) ? 1000 : 2000;
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
          displayMessage("UNLOCKED", "Drop In & Close");
          doorWasOpened   = false;
          stateInitialized = true;
          triggerBuzzer(2);
          Serial.println("[FLOW] Lock: UNLOCKED. Waiting for Top Door Reed (1=Open).");
        }

        if (readReedDebounced(REED_TOP) == 1) {
          if (!doorWasOpened) {
            Serial.println("[FLOW] Reed: Top Door OPEN. Deposit parcel inside.");
            triggerBuzzer(1);
            doorWasOpened = true;
          }
        }

        // Wait for door to physically close (reed=0) before engaging solenoid and confirming drop
        if (doorWasOpened && readReedDebounced(REED_TOP) == 0) {
          digitalWrite(LOCK_TOP, HIGH);  // LOCK
          lockTopOpen = false;
          emitDoorState();              // 🔔 notify app: door is now locked
          Serial.println("[FLOW] Door closed → Lock ENGAGED. Verifying drop in bin...");
          triggerBuzzer(1);
          changeState(CONFIRMING_DROP);
        } else if (!doorWasOpened && (millis() - stateStartTime > 15000)) {
          // Timeout if door was NEVER opened within 15 seconds
          digitalWrite(LOCK_TOP, HIGH);  // LOCK
          lockTopOpen = false;
          emitDoorState();
          Serial.println("[FLOW] WARNING: Door unlock timed out (15s). Door was never opened. Lock ENGAGED. Resetting.");
          displayMessage("TIMEOUT", "Door Not Opened");
          triggerBuzzer(3);
          changeState(RESETTING);
        } else if (doorWasOpened && (millis() - stateStartTime > 35000)) {
          // Thermal safety timeout if door was opened but held open / abandoned for > 35s
          digitalWrite(LOCK_TOP, HIGH);  // LOCK (slam latch allows it to snap shut when eventually pushed)
          lockTopOpen = false;
          emitDoorState();
          Serial.println("[FLOW] WARNING: Door left open timed out (35s). Lock ENGAGED. Resetting.");
          displayMessage("TIMEOUT", "Door Left Open");
          triggerBuzzer(3);
          changeState(RESETTING);
        }
      }
      break;

    // ── CONFIRMING DROP ───────────────────────────────────
    case CONFIRMING_DROP:
      {
        static bool dropConfirmed = false;
        static bool dropFailed = false;
        static unsigned long confirmStartTime = 0;
        static unsigned long confirmResultTime = 0;
        static unsigned long lastSampleTime = 0;
        static int consecutiveHits = 0;

        if (!stateInitialized) {
          dropConfirmed     = false;
          dropFailed        = false;
          confirmStartTime  = millis();
          confirmResultTime = 0;
          lastSampleTime    = 0;
          consecutiveHits   = 0;
          stateInitialized  = true;
          displayMessage("VERIFYING", "Checking Bin...");
          Serial.println("\n[FLOW] === STRICT DROP VERIFICATION (US ONLY) ===");
          Serial.print("[FLOW] DropOff Bin Baseline: ");
          if (dropoffBaselineDist < 900.0) {
            Serial.print(dropoffBaselineDist, 1); Serial.println(" cm");
          } else {
            Serial.println("OUT_OF_RANGE (Will detect parcel < 30.0 cm)");
          }
        }

        // Sampling loop: rate-limited to 120ms to allow clean ultrasonic echo reflections
        if (!dropConfirmed && !dropFailed) {
          if (millis() - lastSampleTime >= 120) {
            lastSampleTime = millis();
            float currentDist = getDistance(US_DROPOFF);
            bool detected = false;
            float delta = 0.0;

            if (currentDist > 1.0 && currentDist < 900.0) {
              if (dropoffBaselineDist < 900.0) {
                delta = dropoffBaselineDist - currentDist;
                // Distance must decrease by at least 4.0 cm to confirm parcel presence
                if (delta >= 4.0) {
                  detected = true;
                }
              } else if (currentDist < 30.0) {
                detected = true;
                delta = 30.0 - currentDist;
              }
            }

            Serial.print("[US CONFIRM] Current: ");
            if (currentDist < 900.0) {
              Serial.print(currentDist, 1); Serial.print(" cm");
            } else {
              Serial.print("OUT_OF_RANGE");
            }
            Serial.print(" | Delta: "); Serial.print(delta, 1);
            Serial.print(" cm | Hits: "); Serial.print(consecutiveHits);
            Serial.println(detected ? " [PASS]" : " [WAIT]");

            if (detected) {
              consecutiveHits++;
              // Require 2 consecutive positive samples to guarantee stable parcel placement
              if (consecutiveHits >= 2) {
                dropConfirmed = true;
                confirmResultTime = millis();

                // Update baseline so subsequent parcels stack properly
                dropoffBaselineDist = currentDist;

                Serial.print("[FLOW] Parcel STRICTLY CONFIRMED in DropOff bin! Distance: ");
                Serial.print(currentDist, 1);
                Serial.print(" cm (Delta: -");
                Serial.print(delta, 1);
                Serial.println(" cm)");

                displayMessage("SUCCESS", "Stored Safely");
                triggerBuzzer(2);

                String newStatus = isReceivingMode ? "delivered" : "awaiting_pickup";
                String modeStr   = isReceivingMode ? "drop_off"  : "pick_up";
                if (strlen(currentTrackingId) > 0) {
                  emitStatusUpdate(String(currentTrackingId), newStatus, modeStr);
                }
              }
            } else {
              consecutiveHits = 0;
            }
          }

          // Strict 6-second timeout: If US sensor never detects a parcel, mark as FAILED
          if (!dropConfirmed && (millis() - confirmStartTime > 6000)) {
            dropFailed = true;
            confirmResultTime = millis();

            Serial.println("[FLOW] ERROR: Drop verification FAILED! No parcel detected by US sensor.");
            Serial.println("[FLOW] Parcel NOT marked as delivered. Returning to safe idle state.");

            displayMessage("DROP FAILED", "No Parcel Detected");
            triggerCyberChirp(2); // Double-low buzz
          }
        }

        // Dwell 2.5s on Result screen (SUCCESS or DROP FAILED) before resetting
        if ((dropConfirmed || dropFailed) && (millis() - confirmResultTime >= 2500)) {
          changeState(RESETTING);
        }
      }
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
    case SETTINGS_MENU: {
      static bool buttonsReleased;
      static bool offline;
      if (!stateInitialized) {
        drawSettingsMenu();
        offline = !cloudDeviceAuthenticated();
        buttonsReleased = false;
        stateInitialized = true;
      }
      if (!buttonsReleased) {
        buttonsReleased = digitalRead(BTN_RECEIVE) == HIGH && digitalRead(BTN_PICKUP) == HIGH;
        break;
      }
      if (offline) {
        if (digitalRead(BTN_RECEIVE) == LOW) changeState(WAITING_FOR_WIFI_CONFIG);
        else if (digitalRead(BTN_PICKUP) == LOW) changeState(WAITING_FOR_BLE_UNLOCK);
        else if (millis() - stateStartTime >= IDLE_TIMEOUT_MS) changeState(IDLE);
        break;
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
    }

    // ── RESETTING ─────────────────────────────────────────
    case RESETTING: {
       if (!stateInitialized) {
         Serial.println("[FLOW] Resetting platform and locks.");
         triggerBuzzer(1);
         digitalWrite(LOCK_TOP,      HIGH);
         delay(30);
         setPickupLock(false);
         delay(30);
         digitalWrite(LOCK_RECEIVED, HIGH);
         lockTopOpen = false; lockReceivedOpen = false;
         emitDoorState(); 
         
         // Servo removed 
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
  static unsigned long holdStart = 0;
  static bool          holding   = false;
  if (currentState == DEVICE_UNREGISTERED || currentState == SHOWING_REGISTRATION_QR ||
      currentState == WAITING_FOR_WIFI_CONFIG || currentState == WAITING_FOR_BLE_UNLOCK ||
      currentState == SETUP_NO_SERVER || currentState == SETTINGS_MENU) {
    holding = false;
    return;
  }
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

    if (cmd != 'D') {
      isUsDiagContinuousActive = false; // Auto-stop stream when executing another command
    }

    if (cmd == 'S') {
      changeState(RESETTING);
    } else if (cmd == 'U') {
      digitalWrite(LOCK_TOP, LOW);
      delay(150); // Stagger inrush current
      setPickupLock(true);
      delay(150);
      digitalWrite(LOCK_RECEIVED, LOW);
      lockTopOpen = true; lockReceivedOpen = true;
      emitDoorState();
      Serial.println("[MANUAL] Override: All Solenoids UNLOCKED (auto-relocking in 10s)...");
      delay(10000);
      digitalWrite(LOCK_TOP, HIGH);
      delay(30);
      setPickupLock(false);
      delay(30);
      digitalWrite(LOCK_RECEIVED, HIGH);
      lockTopOpen = false; lockReceivedOpen = false;
      emitDoorState();
      Serial.println("[MANUAL] Override: All Solenoids RE-LOCKED.");
    } else if (cmd == 'D') {
      isUsDiagContinuousActive = !isUsDiagContinuousActive;
      if (isUsDiagContinuousActive) {
        Serial.println("\n[DIAG] === Continuous Ultrasonic Live Stream: STARTED ===");
        Serial.println("[HINT] Updating every 250ms. Press 'D' + Enter again to STOP.\n");
      } else {
        Serial.println("\n[DIAG] === Continuous Ultrasonic Live Stream: STOPPED ===\n");
      }
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
      int r1 = readReedDebounced(REED_TOP);
      int r2 = readReedDebounced(REED_PICKUP);
      int r3 = readReedDebounced(REED_RECEIVED);
      Serial.print("  Reed TOP      : "); Serial.println(r1 == 0 ? "CLOSED (Locked)" : "OPEN (Unlocked)");
      Serial.print("  Reed PICKUP   : "); Serial.println(r2 == 0 ? "CLOSED" : "OPEN");
      Serial.print("  Reed RECEIVED : "); Serial.println(r3 == 0 ? "CLOSED" : "OPEN");
      
      // Ultrasonic Sensors (DropOff active; Platform & Pickup removed)
      float d3 = getDistance(US_DROPOFF);
      Serial.println("  US1 Platform  : DISABLED (Removed - GPIO 15, 4 Free)");
      Serial.println("  US2 Pickup    : DISABLED (Removed - GPIO 7, 16 Free)");
      Serial.print("  US3 DropOff   : "); 
      if (d3 < 900.0) {
        Serial.print(d3, 1); Serial.print("cm");
        if (dropoffBaselineDist < 900.0) {
          Serial.print(" (Baseline: "); Serial.print(dropoffBaselineDist, 1); Serial.print("cm)");
        }
        Serial.println();
      } else {
        Serial.println("OUT_OF_RANGE");
      }
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
      Serial.println("[MANUAL] Opening Bluetooth Wi-Fi setup...");
      triggerBuzzer(2);
      changeState(WAITING_FOR_WIFI_CONFIG);
    }
  }
}

// (TFT reinit and update indicators moved to DisplayController3.ino)

void forceNextStep() {
  switch (currentState) {
    case PICKUP_DOOR_OPEN:
      Serial.println("[FLOW] Bypass: Completing pickup.");
      setPickupLock(false);
      emitDoorState();
      changeState(RESETTING);
      break;
    case WAITING_FOR_SCAN:
      Serial.println("[FLOW] Bypass: Bypassing Scan.");
      changeState(isReceivingMode ? UNLOCKING_ENTRY : PICKUP_DOOR_OPEN);
      break;
    case UNLOCKING_ENTRY:
      Serial.println("[FLOW] Bypass: Bypassing Top Door Cycle.");
      digitalWrite(LOCK_TOP, HIGH);
      lockTopOpen = false;
      emitDoorState();
      changeState(CONFIRMING_DROP);
      break;
    case CONFIRMING_DROP:
      Serial.println("[FLOW] Bypass: Bypassing Drop Confirmation.");
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
  Serial.println("  S=Reset  | U=Unlock All | D=US Live Stream (Toggle) | M=Monitor | N=Next | X=Scan Test");
  Serial.println("  T=TFT Reset | C=WiFi Setup | V=View IDs & Status | W=Network Info");
  Serial.println("  R1:<id> = Register Drop Off ID (offline)");
  Serial.println("  R2:<id> = Register Pick Up ID  (offline)");
  Serial.println("  N:<token>  = Simulate QR scan (dev bypass)");
  Serial.println("     e.g.  N:SPDB-REG-482913  (registration)");
  Serial.println("  IDs auto-registered via mobile app (online)");
  Serial.println("==========================================");
  Serial.println();
}

void changeState(SystemState newState) {
  currentState        = newState;
  stateStartTime      = millis();
  lastStateChangeTime = millis();
  stateInitialized    = false;
  actionDelayActive   = false;
  pendingNextState    = IDLE;
  tft.fillScreen(COLOR_BG);
  
  if (newState == IDLE) {
    scanResultReceived   = false;
    scanResultValid      = false;
    currentTrackingId[0] = '\0';
    serial2Buffer[0]     = '\0';
    doorWasOpened        = false;
    showHomeScreen();
  }
}

// (moveServoSmoothly and triggerBuzzer moved to HardwareController.ino)

// (All displayMessage and drawScreen routines moved to DisplayController.ino)
