/*
 * Smart Parcel Dropbox - MULTI-USER PRODUCTION VERSION
 * ====================================================
 * Backend: smart-parcel-dropbox.onrender.com (Socket.io v4.8.1)
 * Protocol: Socket.io over WebSockets
 * Architecture: Device listens to GLOBAL doorStateUpdate events
 * Scanner: COMMENTED OUT (Defective MH-ET)
 * 
 * MULTI-USER DESIGN:
 * - NO user-specific rooms (removed USER_ID)
 * - ESP32 listens to global 'doorStateUpdate' broadcasts
 * - Any authorized user can control the device
 * - Backend handles authorization via MongoDB
 * 
 * INSTALL THESE LIBRARIES IN ARDUINO IDE:
 * 1. "Socket.io client" by tzapu (v2.3.7+)
 * 2. "ArduinoJson" by Benoit Blanchon (v7+)
 * 3. "ESP32Servo" by Kevin Harrington
 * 4. "Adafruit GFX Library"
 * 5. "Adafruit ILI9341"
 */

#include <WiFi.h>
#include <SocketIoClient.h>  // tzapu's library - PROPER Socket.io client
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
#include <SPI.h>

// ============ WIFI & SERVER CONFIG ============
const char* WIFI_SSID = "iPhone";
const char* WIFI_PASSWORD = "Perez@54321";

// IMPORTANT: Render.com URL without https:// or wss://
const char* SERVER_HOST = "smart-parcel-dropbox.onrender.com";
const int SERVER_PORT = 443;  // SSL port
const char* SERVER_PATH = "/socket.io/?EIO=4&transport=websocket";

// DEVICE_ID: Unique identifier for this physical dropbox unit
// Change this if you have multiple dropboxes (e.g., "DROPBOX_002")
const char* DEVICE_ID = "DROPBOX_001";

// ============ PIN DEFINITIONS (PCB MATCHED) ============
#define TFT_CS    10
#define TFT_DC    21
#define TFT_RST   20
#define PIR_PIN             4
#define TOP_SOLENOID_PIN    5
#define TOP_REED_PIN        6
#define BOTTOM_SOLENOID_PIN 7
#define BOTTOM_REED_PIN     8
#define ECHO_PIN            13
#define SERVO_PIN           14
#define TRIG_PIN            15

// ============ OBJECTS ============
Servo dropServo;
Adafruit_ILI9341 tft = Adafruit_ILI9341(TFT_CS, TFT_DC, TFT_RST);
SocketIoClient webSocket;

// ============ COLORS ============
#define COLOR_BG          0x0014
#define COLOR_PRIMARY     0x07FF
#define COLOR_SUCCESS     0x07E0
#define COLOR_WARNING     0xFD20
#define COLOR_DANGER      0xF800
#define COLOR_TEXT        0xFFFF
#define COLOR_CARD_BG     0x1082
#define COLOR_INFO        0x54BF

// ============ SYSTEM STATES ============
enum SystemState {
  WIFI_CONNECTING,
  SERVER_CONNECTING,
  WAITING_FOR_MOTION,
  MOTION_ALERT,
  SCANNING_PARCEL,
  UNLOCKING_TOP_DOOR,
  WAITING_TOP_DOOR_OPEN,
  WAITING_FOR_PARCEL,
  WAITING_TOP_DOOR_CLOSE,
  DROPPING_PARCEL,
  DELIVERY_COMPLETE_MENU,
  UNLOCKING_BOTTOM_DOOR,
  WAITING_BOTTOM_DOOR_OPEN,
  WAITING_BOTTOM_DOOR_CLOSE,
  SYSTEM_RESET
};

SystemState currentState = WIFI_CONNECTING;
bool stateInitialized = false;

// ============ TIMING & VARS ============
const unsigned long SCAN_DURATION = 5000;
const unsigned long UNLOCK_DURATION = 2000;
const unsigned long PARCEL_CHECK_INTERVAL = 200;
const unsigned long PIR_COOLDOWN = 5000;
const unsigned long MAX_SOLENOID_TIME = 5000;
const unsigned long SENSOR_UPDATE_INTERVAL = 3000;
const int PARCEL_THRESHOLD = 15;

unsigned long stateStartTime = 0;
unsigned long pirLastTriggerTime = 0;
unsigned long lastSensorUpdate = 0;
unsigned long lastConnectionAttempt = 0;

bool isConnectedToServer = false;
bool topReedClosedState = LOW;
bool bottomReedClosedState = LOW;

// Servo Logic
int currentServoAngle = 0;
int targetServoAngle = 0;
unsigned long lastServoMoveTime = 0;
int servoStepDelay = 15;

// UI Helpers
int lastProgress = -1;
float lastDistance = -1.0;

// ============ FUNCTION PROTOTYPES ============
void changeState(SystemState newState);
void sendStatusToServer();
void sendSensorDataToServer();
float getSmoothedDistance();
void onSocketEvent(socketIOmessageType_t type, uint8_t * payload, size_t length);

// ============ SETUP ============
void setup() {
  Serial.begin(115200);
  
  // 1. Initialize Screen
  tft.begin();
  tft.setRotation(3);
  tft.fillScreen(COLOR_BG);
  showStatusCard("System", "Booting...", COLOR_INFO);
  delay(1000);

  // 2. Initialize Hardware
  pinMode(PIR_PIN, INPUT);
  pinMode(TOP_REED_PIN, INPUT_PULLUP);
  pinMode(BOTTOM_REED_PIN, INPUT_PULLUP);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(TOP_SOLENOID_PIN, OUTPUT);
  pinMode(BOTTOM_SOLENOID_PIN, OUTPUT);
  
  // Lock both doors immediately
  digitalWrite(TOP_SOLENOID_PIN, HIGH);
  digitalWrite(BOTTOM_SOLENOID_PIN, HIGH);

  dropServo.attach(SERVO_PIN);
  dropServo.write(0);

  // Auto-detect Reed Logic
  topReedClosedState = digitalRead(TOP_REED_PIN);
  bottomReedClosedState = digitalRead(BOTTOM_REED_PIN);

  Serial.println("✅ Hardware Initialized");
  Serial.println("Device ID: " + String(DEVICE_ID));
  
  // 3. Connect to WiFi
  changeState(WIFI_CONNECTING);
}

// ============ MAIN LOOP ============
void loop() {
  unsigned long currentMillis = millis();
  
  // Always handle WebSocket events
  webSocket.loop();
  
  // Global handlers
  handleServoMovement(currentMillis);
  handleSolenoidSafety(currentMillis);
  handleSerialCommands();

  // Periodic sensor updates when connected
  if (isConnectedToServer && (currentMillis - lastSensorUpdate > SENSOR_UPDATE_INTERVAL)) {
    sendSensorDataToServer();
    lastSensorUpdate = currentMillis;
  }

  // --- STATE MACHINE ---
  switch (currentState) {
    case WIFI_CONNECTING:
      if (!stateInitialized) {
        showStatusCard("WiFi", "Connecting...", COLOR_WARNING);
        WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
        stateInitialized = true;
      }
      
      if (WiFi.status() == WL_CONNECTED) {
        Serial.print("WiFi Connected! IP: ");
        Serial.println(WiFi.localIP());
        changeState(SERVER_CONNECTING);
      } else if (currentMillis - stateStartTime > 20000) {
        // Timeout after 20 seconds
        showStatusCard("WiFi", "FAILED!", COLOR_DANGER);
        delay(3000);
        ESP.restart();
      }
      break;

    case SERVER_CONNECTING:
      if (!stateInitialized) {
        showStatusCard("Server", "Connecting...", COLOR_WARNING);
        
        // Configure Socket.io client
        webSocket.beginSSL(SERVER_HOST, SERVER_PORT, SERVER_PATH);
        webSocket.onEvent(onSocketEvent);
        
        stateInitialized = true;
      }
      
      // Wait for connection callback (handled in onSocketEvent)
      if (currentMillis - stateStartTime > 15000) {
        // Timeout - retry
        showStatusCard("Server", "Retrying...", COLOR_WARNING);
        webSocket.disconnect();
        delay(2000);
        stateInitialized = false;
        stateStartTime = currentMillis;
      }
      break;

    case WAITING_FOR_MOTION:
      if (!stateInitialized) {
        showIdleScreen();
        stateInitialized = true;
      }
      
      // Sunlight/Glitch Filter
      if (digitalRead(PIR_PIN) == HIGH) {
        delay(200);
        if (digitalRead(PIR_PIN) == HIGH) {
          if (currentMillis - pirLastTriggerTime > PIR_COOLDOWN) {
            pirLastTriggerTime = currentMillis;
            changeState(MOTION_ALERT);
          }
        }
      }
      break;

    case MOTION_ALERT:
      if (!stateInitialized) {
        showStatusCard("Hello!", "Motion Detected", COLOR_WARNING);
        stateInitialized = true;
      }
      if (currentMillis - stateStartTime > 2000) {
        changeState(SCANNING_PARCEL);
      }
      break;

    case SCANNING_PARCEL:
      if (!stateInitialized) {
        showScanningBase();
        stateInitialized = true;
      }
      {
        int progress = map(currentMillis - stateStartTime, 0, SCAN_DURATION, 0, 100);
        updateScanningBar(min(progress, 100));
        
        if (currentMillis - stateStartTime >= SCAN_DURATION) {
          showParcelMatched();
          delay(1000);
          changeState(UNLOCKING_TOP_DOOR);
        }
      }
      break;

    case UNLOCKING_TOP_DOOR:
      if (!stateInitialized) {
        digitalWrite(TOP_SOLENOID_PIN, LOW); // UNLOCK
        showStatusCard("Top Door", "Unlocking...", COLOR_WARNING);
        sendStatusToServer(); // Notify backend
        stateInitialized = true;
      }
      if (currentMillis - stateStartTime >= UNLOCK_DURATION) {
        changeState(WAITING_TOP_DOOR_OPEN);
      }
      break;

    case WAITING_TOP_DOOR_OPEN:
      if (!stateInitialized) {
        showStatusCard("Top Door", "PLEASE OPEN", COLOR_SUCCESS);
        digitalWrite(TOP_SOLENOID_PIN, HIGH); // Re-lock mechanism
        stateInitialized = true;
      }
      if (digitalRead(TOP_REED_PIN) != topReedClosedState) {
        changeState(WAITING_FOR_PARCEL);
      }
      break;

    case WAITING_FOR_PARCEL:
      if (!stateInitialized) {
        showDistanceBase();
        stateInitialized = true;
      }

      if (currentMillis % PARCEL_CHECK_INTERVAL == 0) {
        float dist = getSmoothedDistance();
        updateDistanceValue(dist);
        
        if (dist > 0 && dist < PARCEL_THRESHOLD) {
          showStatusCard("Parcel", "DETECTED!", COLOR_SUCCESS);
          delay(1000);
          changeState(WAITING_TOP_DOOR_CLOSE);
        }
      }
      break;

    case WAITING_TOP_DOOR_CLOSE:
      if (!stateInitialized) {
        showInstruction("Please close the door");
        stateInitialized = true;
      }
      if (digitalRead(TOP_REED_PIN) == topReedClosedState) {
        changeState(DROPPING_PARCEL);
      }
      break;

    case DROPPING_PARCEL:
      if (!stateInitialized) {
        showDropAnimation();
        targetServoAngle = 90;
        stateInitialized = true;
      }

      if (currentServoAngle == 90 && (currentMillis - lastServoMoveTime > 1000)) {
        targetServoAngle = 0;
      }
      
      if (currentServoAngle == 0 && targetServoAngle == 0 && 
          (currentMillis - stateStartTime > 3000)) {
        sendStatusToServer(); // Notify delivery complete
        changeState(DELIVERY_COMPLETE_MENU);
      }
      break;

    case DELIVERY_COMPLETE_MENU:
      if (!stateInitialized) {
        showDeliveryComplete();
        stateInitialized = true;
      }
      break;

    case UNLOCKING_BOTTOM_DOOR:
      if (!stateInitialized) {
        digitalWrite(BOTTOM_SOLENOID_PIN, LOW); // UNLOCK
        showStatusCard("Retrieval", "Unlocking...", COLOR_WARNING);
        stateInitialized = true;
      }
      if (currentMillis - stateStartTime >= UNLOCK_DURATION) {
        changeState(WAITING_BOTTOM_DOOR_OPEN);
      }
      break;

    case WAITING_BOTTOM_DOOR_OPEN:
      if (!stateInitialized) {
        showStatusCard("Retrieval", "OPEN DOOR", COLOR_SUCCESS);
        digitalWrite(BOTTOM_SOLENOID_PIN, HIGH);
        stateInitialized = true;
      }
      if (digitalRead(BOTTOM_REED_PIN) != bottomReedClosedState) {
        changeState(WAITING_BOTTOM_DOOR_CLOSE);
      }
      break;

    case WAITING_BOTTOM_DOOR_CLOSE:
      if (!stateInitialized) {
        showInstruction("Close after retrieving");
        stateInitialized = true;
      }
      if (digitalRead(BOTTOM_REED_PIN) == bottomReedClosedState) {
        changeState(SYSTEM_RESET);
      }
      break;

    case SYSTEM_RESET:
      showStatusCard("System", "Resetting...", COLOR_INFO);
      delay(1000);
      changeState(WAITING_FOR_MOTION);
      break;
  }
}

// ============ SOCKET.IO EVENT HANDLER ============
void onSocketEvent(socketIOmessageType_t type, uint8_t * payload, size_t length) {
  switch(type) {
    case sIOtype_DISCONNECT:
      Serial.println("[Socket.io] Disconnected!");
      isConnectedToServer = false;
      showStatusCard("Server", "DISCONNECTED", COLOR_DANGER);
      delay(2000);
      // Try to reconnect
      changeState(SERVER_CONNECTING);
      break;
      
    case sIOtype_CONNECT:
      Serial.println("[Socket.io] Connected!");
      Serial.println("[Socket.io] Listening for global doorStateUpdate events");
      isConnectedToServer = true;
      
      // NO ROOM JOINING - We listen to global broadcasts
      // Backend emits: io.emit('doorStateUpdate', data)
      // ESP32 receives it automatically
      
      // Transition to normal operation
      if (currentState == SERVER_CONNECTING) {
        changeState(WAITING_FOR_MOTION);
      }
      break;
      
    case sIOtype_EVENT:
      {
        String text = (char*)payload;
        Serial.println("[Socket.io Event] " + text);
        
        // Parse Socket.io event
        DynamicJsonDocument doc(1024);
        DeserializationError error = deserializeJson(doc, text);
        
        if (!error) {
          const char* eventName = doc[0];
          
          // Handle doorStateUpdate event from ANY user
          if (String(eventName) == "doorStateUpdate") {
            JsonObject data = doc[1];
            const char* command = data["command"];
            const char* userId = data["userId"];  // For logging only
            
            Serial.print("Command from user ");
            Serial.print(userId);
            Serial.print(": ");
            Serial.println(command);
            
            if (String(command) == "open") {
              Serial.println("✅ OPEN command accepted");
              
              if (currentState == WAITING_FOR_MOTION) {
                // Skip to unlocking if in idle state
                changeState(SCANNING_PARCEL);
              } else if (currentState == DELIVERY_COMPLETE_MENU) {
                // Open bottom door for retrieval
                changeState(UNLOCKING_BOTTOM_DOOR);
              } else {
                Serial.println("⚠️ Ignored - device not in valid state");
              }
            }
          }
        }
      }
      break;
      
    case sIOtype_ACK:
      Serial.println("[Socket.io] ACK received");
      break;
      
    case sIOtype_ERROR:
      Serial.println("[Socket.io] ERROR!");
      break;
      
    case sIOtype_BINARY_EVENT:
    case sIOtype_BINARY_ACK:
      // Not used in this project
      break;
  }
}

// ============ HELPER FUNCTIONS ============
void changeState(SystemState newState) {
  currentState = newState;
  stateStartTime = millis();
  stateInitialized = false;
  lastProgress = -1;
  lastDistance = -1.0;
}

void sendStatusToServer() {
  if (!isConnectedToServer) return;
  
  DynamicJsonDocument doc(256);
  doc["deviceId"] = DEVICE_ID;
  doc["state"] = (int)currentState;
  doc["topDoorOpen"] = (digitalRead(TOP_REED_PIN) != topReedClosedState);
  doc["bottomDoorOpen"] = (digitalRead(BOTTOM_REED_PIN) != bottomReedClosedState);
  doc["parcelDetected"] = (getSmoothedDistance() < PARCEL_THRESHOLD);
  doc["timestamp"] = millis();
  
  String output;
  serializeJson(doc, output);
  
  // Emit with Socket.io format
  String message = "[\"deviceUpdate\"," + output + "]";
  webSocket.emit("deviceUpdate", message.c_str());
}

void sendSensorDataToServer() {
  if (!isConnectedToServer) return;
  
  float distance = getSmoothedDistance();
  
  DynamicJsonDocument doc(256);
  doc["deviceId"] = DEVICE_ID;
  doc["parcelDetected"] = (distance > 0 && distance < PARCEL_THRESHOLD);
  doc["distance"] = distance;
  doc["motionDetected"] = (digitalRead(PIR_PIN) == HIGH);
  doc["topDoorOpen"] = (digitalRead(TOP_REED_PIN) != topReedClosedState);
  doc["bottomDoorOpen"] = (digitalRead(BOTTOM_REED_PIN) != bottomReedClosedState);
  
  String output;
  serializeJson(doc, output);
  
  String message = "[\"sensorData\"," + output + "]";
  webSocket.emit("sensorData", message.c_str());
}

void handleServoMovement(unsigned long currentMillis) {
  if (currentServoAngle != targetServoAngle) {
    if (currentMillis - lastServoMoveTime >= servoStepDelay) {
      if (currentServoAngle < targetServoAngle) currentServoAngle++;
      else currentServoAngle--;
      
      dropServo.write(currentServoAngle);
      lastServoMoveTime = currentMillis;
    }
  }
}

void handleSolenoidSafety(unsigned long currentMillis) {
  if (currentState == UNLOCKING_TOP_DOOR || currentState == UNLOCKING_BOTTOM_DOOR) {
    if (currentMillis - stateStartTime > MAX_SOLENOID_TIME) {
      digitalWrite(TOP_SOLENOID_PIN, HIGH);
      digitalWrite(BOTTOM_SOLENOID_PIN, HIGH);
    }
  }
}

void handleSerialCommands() {
  if (Serial.available() > 0) {
    char cmd = Serial.read();
    
    if (cmd == 'S' || cmd == 's') {
      digitalWrite(TOP_SOLENOID_PIN, HIGH);
      digitalWrite(BOTTOM_SOLENOID_PIN, HIGH);
      targetServoAngle = 0;
      changeState(WAITING_FOR_MOTION);
    }
    
    if (currentState == DELIVERY_COMPLETE_MENU) {
      if (cmd == 'R' || cmd == 'r') changeState(SYSTEM_RESET);
      if (cmd == 'U' || cmd == 'u') changeState(UNLOCKING_BOTTOM_DOOR);
    }
  }
}

float getSmoothedDistance() {
  float total = 0;
  int count = 0;
  
  for (int i = 0; i < 3; i++) {
    digitalWrite(TRIG_PIN, LOW);
    delayMicroseconds(2);
    digitalWrite(TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(TRIG_PIN, LOW);
    
    long dur = pulseIn(ECHO_PIN, HIGH, 25000);
    if (dur > 0) {
      total += dur;
      count++;
    }
    delay(5);
  }
  
  if (count == 0) return -1;
  return (total / count) * 0.034 / 2;
}

// ============ UI FUNCTIONS ============
void showIdleScreen() {
  tft.fillScreen(COLOR_BG);
  
  // Show WiFi status
  tft.setTextColor(COLOR_SUCCESS);
  tft.setTextSize(1);
  tft.setCursor(10, 10);
  tft.print("WiFi: ");
  tft.print(WiFi.localIP());
  
  tft.drawRoundRect(20, 60, 280, 140, 15, COLOR_PRIMARY);
  tft.setTextColor(COLOR_TEXT);
  tft.setTextSize(3);
  tft.setCursor(60, 110);
  tft.println("READY FOR");
  tft.setCursor(70, 150);
  tft.println("DELIVERY");
}

void showScanningBase() {
  tft.fillScreen(COLOR_BG);
  tft.setTextColor(COLOR_PRIMARY);
  tft.setTextSize(3);
  tft.setCursor(50, 50);
  tft.println("Scanning...");
  tft.drawRoundRect(30, 110, 260, 40, 20, COLOR_PRIMARY);
  tft.fillRoundRect(30, 110, 260, 40, 20, COLOR_CARD_BG);
}

void updateScanningBar(int progress) {
  if (progress == lastProgress) return;
  lastProgress = progress;

  int barW = 260;
  int fillW = (barW - 8) * progress / 100;
  if (fillW > 0) {
    tft.fillRoundRect(34, 114, fillW, 32, 16, COLOR_SUCCESS);
  }
  
  tft.setTextSize(2);
  tft.setTextColor(COLOR_TEXT, COLOR_BG);
  tft.setCursor(120, 160);
  tft.print(progress);
  tft.println("%");
}

void showParcelMatched() {
  tft.fillScreen(COLOR_SUCCESS);
  tft.setTextColor(COLOR_TEXT);
  tft.setTextSize(3);
  tft.setCursor(70, 110);
  tft.println("VERIFIED!");
}

void showStatusCard(const char* title, const char* message, uint16_t color) {
  tft.fillScreen(COLOR_BG);
  tft.fillRoundRect(30, 60, 260, 120, 15, COLOR_CARD_BG);
  tft.drawRoundRect(30, 60, 260, 120, 15, color);
  
  tft.setTextColor(color);
  tft.setTextSize(2);
  tft.setCursor(50, 80);
  tft.println(title);
  
  tft.setTextColor(COLOR_TEXT);
  tft.setTextSize(3);
  int len = strlen(message);
  int x = 160 - (len * 9);
  tft.setCursor(x, 120);
  tft.println(message);
}

void showInstruction(const char* text) {
  tft.fillRect(0, 200, 320, 40, COLOR_BG);
  tft.setTextColor(COLOR_PRIMARY);
  tft.setTextSize(2);
  tft.setCursor(20, 200);
  tft.println(text);
}

void showDistanceBase() {
  tft.fillScreen(COLOR_BG);
  tft.setTextColor(COLOR_PRIMARY);
  tft.setTextSize(2);
  tft.setCursor(60, 60);
  tft.println("Checking Bay...");
  tft.setTextColor(COLOR_TEXT);
  tft.setTextSize(4);
  tft.setCursor(180, 120);
  tft.println("cm");
}

void updateDistanceValue(float distance) {
  if (abs(distance - lastDistance) < 0.5) return;
  lastDistance = distance;
  
  tft.fillRect(40, 110, 130, 50, COLOR_BG);
  tft.setTextColor(COLOR_TEXT);
  tft.setTextSize(4);
  tft.setCursor(50, 120);
  if (distance < 0) tft.print("--");
  else tft.print(distance, 1);
}

void showDropAnimation() {
  tft.fillScreen(COLOR_BG);
  tft.setTextColor(COLOR_PRIMARY);
  tft.setTextSize(3);
  tft.setCursor(60, 110);
  tft.println("DROPPING...");
}

void showDeliveryComplete() {
  tft.fillScreen(COLOR_BG);
  tft.fillRoundRect(30, 40, 260, 160, 15, COLOR_CARD_BG);
  tft.setTextColor(COLOR_SUCCESS);
  tft.setTextSize(3);
  tft.setCursor(70, 70);
  tft.println("DELIVERED");
  tft.setTextColor(COLOR_TEXT);
  tft.setTextSize(2);
  tft.setCursor(50, 130);
  tft.println("[R] to Reset");
  tft.setCursor(50, 160);
  tft.println("[U] to Retrieve");
}
