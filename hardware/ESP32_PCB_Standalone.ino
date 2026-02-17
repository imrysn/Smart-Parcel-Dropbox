/*
 * Smart Parcel Dropbox - FINAL PCB VERSION
 * ========================================
 * - Pins: MATCHED TO PCB (No changes)
 * - Logic: Non-blocking
 * - Fix 1: "Motion Detected" screen added before scanning
 * - Fix 2: Sunlight/Gitch filter added to PIR logic
 * 
 * NOTE: This is the STANDALONE version (no WiFi/IoT).
 * For production IoT version, use: ESP32_Smart_Dropbox_Production.ino
 */

#include <ESP32Servo.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
#include <SPI.h>

// ============ PIN DEFINITIONS (UNCHANGED) ============
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

// ============ COLORS ============
#define COLOR_BG          0x0014      // Deep dark blue
#define COLOR_PRIMARY     0x07FF      // Cyan
#define COLOR_SUCCESS     0x07E0      // Green
#define COLOR_WARNING     0xFD20      // Orange
#define COLOR_DANGER      0xF800      // Red
#define COLOR_INFO        0x54BF      // Light blue
#define COLOR_ACCENT      0xFFE0      // Yellow
#define COLOR_TEXT        0xFFFF      // White
#define COLOR_CARD_BG     0x1082      // Dark card background

// ============ SYSTEM STATES ============
enum SystemState {
  WAITING_FOR_MOTION,
  MOTION_ALERT,          // <--- NEW STATE: Shows "Welcome"
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

SystemState currentState = WAITING_FOR_MOTION;
bool stateInitialized = false; 

// ============ TIMING & CONFIGURATION ============
const unsigned long SCAN_DURATION = 5000;
const unsigned long UNLOCK_DURATION = 2000;
const unsigned long PARCEL_CHECK_INTERVAL = 200;
const unsigned long PIR_COOLDOWN = 5000;
const unsigned long MAX_SOLENOID_TIME = 5000; 
const unsigned long SCREEN_TIMEOUT = 60000;   // 1 minute

// Thresholds
const int PARCEL_DISTANCE_THRESHOLD = 15;

// Variables
unsigned long stateStartTime = 0;
unsigned long pirLastTriggerTime = 0;
unsigned long lastInteractionTime = 0; 
bool isScreenSaverActive = false;

// Sensor States
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

// ============ SETUP ============
void setup() {
  Serial.begin(115200);
  
  // 1. Initialize Screen
  tft.begin();
  tft.setRotation(3);
  tft.fillScreen(COLOR_BG);

  // 2. Initialize Sensors
  pinMode(PIR_PIN, INPUT);
  pinMode(TOP_REED_PIN, INPUT_PULLUP);
  pinMode(BOTTOM_REED_PIN, INPUT_PULLUP);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);

  // 3. Initialize Locks (Immediately Lock)
  pinMode(TOP_SOLENOID_PIN, OUTPUT);
  pinMode(BOTTOM_SOLENOID_PIN, OUTPUT);
  digitalWrite(TOP_SOLENOID_PIN, HIGH);
  digitalWrite(BOTTOM_SOLENOID_PIN, HIGH);

  // 4. Initialize Servo
  dropServo.attach(SERVO_PIN);
  dropServo.write(0);

  // 5. Auto-detect Reed Logic
  topReedClosedState = digitalRead(TOP_REED_PIN);
  bottomReedClosedState = digitalRead(BOTTOM_REED_PIN);

  Serial.println("✅ System Ready - Solar/Gitch Filtering Active");
  
  changeState(WAITING_FOR_MOTION);
}

// ============ MAIN LOOP ============
void loop() {
  unsigned long currentMillis = millis();

  // --- GLOBAL HANDLERS ---
  handleSerialCommands();
  handleServoMovement(currentMillis);
  handleSolenoidSafety(currentMillis);
  handleScreenSaver(currentMillis);

  // Screen Saver Logic
  if (isScreenSaverActive && currentState == WAITING_FOR_MOTION) {
    if (digitalRead(PIR_PIN) == HIGH) {
      wakeUpScreen();
    }
    return;
  }

  // --- STATE MACHINE ---
  switch (currentState) {
    case WAITING_FOR_MOTION:
      if (!stateInitialized) {
        showIdleScreen();
        stateInitialized = true;
      }
      
      // --- SUNLIGHT/GLITCH FILTER ---
      // 1. Check if PIR is HIGH
      if (digitalRead(PIR_PIN) == HIGH) {
        
        // 2. Wait 200ms (Short Blocking Delay is OK here for filtering)
        delay(200); 
        
        // 3. Check again. If STILL high, it's a real person, not a glitch.
        if (digitalRead(PIR_PIN) == HIGH) {
           
           // 4. Check cooldown
           if (currentMillis - pirLastTriggerTime > PIR_COOLDOWN) {
              wakeUpScreen(); 
              pirLastTriggerTime = currentMillis;
              changeState(MOTION_ALERT); // Go to Alert first
           }
        }
      }
      break;

    case MOTION_ALERT:
      if (!stateInitialized) {
        // Show the Welcome screen you wanted
        showStatusCard("Hello!", "Motion Detected", COLOR_WARNING);
        stateInitialized = true;
      }

      // Display this for 2 seconds before scanning
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
        unsigned long elapsed = currentMillis - stateStartTime;
        int progress = map(elapsed, 0, SCAN_DURATION, 0, 100);
        if (progress > 100) progress = 100;
        
        updateScanningBar(progress);
        
        if (elapsed >= SCAN_DURATION) {
          showParcelMatched();
          delay(1000); 
          changeState(UNLOCKING_TOP_DOOR);
        }
      }
      break;

    case UNLOCKING_TOP_DOOR:
      if (!stateInitialized) {
        digitalWrite(TOP_SOLENOID_PIN, LOW); // Unlock
        showStatusCard("Top Door", "Unlocking...", COLOR_WARNING);
        stateInitialized = true;
      }
      
      if (currentMillis - stateStartTime >= UNLOCK_DURATION) {
        changeState(WAITING_TOP_DOOR_OPEN);
      }
      break;

    case WAITING_TOP_DOOR_OPEN:
      if (!stateInitialized) {
        showStatusCard("Top Door", "PLEASE OPEN", COLOR_SUCCESS);
        digitalWrite(TOP_SOLENOID_PIN, HIGH); 
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
        
        if (dist > 0 && dist < PARCEL_DISTANCE_THRESHOLD) {
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
      
      if (currentServoAngle == 0 && targetServoAngle == 0 && (currentMillis - stateStartTime > 3000)) {
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
        digitalWrite(BOTTOM_SOLENOID_PIN, LOW);
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

// ============ HELPER FUNCTIONS ============

void changeState(SystemState newState) {
  currentState = newState;
  stateStartTime = millis();
  stateInitialized = false;
  wakeUpScreen();
  
  // Reset UI helpers
  lastProgress = -1;
  lastDistance = -1.0;
}

void handleSerialCommands() {
  if (Serial.available() > 0) {
    char cmd = Serial.read();
    wakeUpScreen();
    
    if (cmd == 'S' || cmd == 's') forceReset();
    
    if (currentState == DELIVERY_COMPLETE_MENU) {
      if (cmd == 'R' || cmd == 'r') changeState(SYSTEM_RESET);
      if (cmd == 'U' || cmd == 'u') changeState(UNLOCKING_BOTTOM_DOOR);
    }
  }
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

void handleScreenSaver(unsigned long currentMillis) {
  if (currentState == WAITING_FOR_MOTION) {
    if (!isScreenSaverActive && (currentMillis - lastInteractionTime > SCREEN_TIMEOUT)) {
      tft.fillScreen(COLOR_BG);
      isScreenSaverActive = true;
    }
  }
}

void wakeUpScreen() {
  lastInteractionTime = millis();
  if (isScreenSaverActive) {
    isScreenSaverActive = false;
    stateInitialized = false; 
  }
}

void forceReset() {
  digitalWrite(TOP_SOLENOID_PIN, HIGH);
  digitalWrite(BOTTOM_SOLENOID_PIN, HIGH);
  targetServoAngle = 0;
  changeState(WAITING_FOR_MOTION);
}

float getSmoothedDistance() {
  float total = 0;
  int count = 0;
  for (int i=0; i<3; i++) {
    digitalWrite(TRIG_PIN, LOW); delayMicroseconds(2);
    digitalWrite(TRIG_PIN, HIGH); delayMicroseconds(10);
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
  tft.drawRoundRect(20, 40, 280, 160, 15, COLOR_PRIMARY);
  tft.setTextColor(COLOR_TEXT);
  tft.setTextSize(3);
  tft.setCursor(60, 100);
  tft.println("READY FOR");
  tft.setCursor(70, 140);
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
  tft.setTextColor(COLOR_ACCENT);
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
  tft.setTextColor(COLOR_ACCENT);
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
