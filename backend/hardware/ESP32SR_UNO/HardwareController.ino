// ============================================================
//  HardwareController.ino
//  Contains logic for Buzzers, Doors, Sensors, and Resets
// ============================================================

void triggerCyberChirp(int pattern) {
  switch (pattern) {
    case 1: // Success / Unlock (High-pitched tri-tone)
      for(int i=0; i<3; i++) { digitalWrite(BUZZER_PIN, HIGH); delay(40); digitalWrite(BUZZER_PIN, LOW); delay(30); }
      break;
    case 2: // Error / Denied (Double-low buzz)
      digitalWrite(BUZZER_PIN, HIGH); delay(200); digitalWrite(BUZZER_PIN, LOW); delay(50);
      digitalWrite(BUZZER_PIN, HIGH); delay(200); digitalWrite(BUZZER_PIN, LOW);
      break;
    case 3: // Neutral / Scan (Short pip)
      digitalWrite(BUZZER_PIN, HIGH); delay(20); digitalWrite(BUZZER_PIN, LOW);
      break;
    default:
      digitalWrite(BUZZER_PIN, HIGH); delay(100); digitalWrite(BUZZER_PIN, LOW);
      break;
  }
}

void triggerBuzzer(int beeps) {
  triggerCyberChirp(beeps == 1 ? 3 : beeps == 2 ? 1 : 2);
}

int readReedDebounced(int pin) {
  int first = digitalRead(pin);
  // Multi-sample check spaced 4ms apart to reject ground bounce & back-EMF spikes
  for (int i = 0; i < 3; i++) {
    delay(4);
    if (digitalRead(pin) != first) {
      delay(4);
      return digitalRead(pin);
    }
  }
  return first;
}

static float _getDistanceRaw(const int pins[]) {
  digitalWrite(pins[0], LOW);
  delayMicroseconds(2);
  digitalWrite(pins[0], HIGH);
  delayMicroseconds(10);
  digitalWrite(pins[0], LOW);
  
  long dur = pulseIn(pins[1], HIGH, 20000); 
  if (dur == 0) return 999.0;
  return (dur * 0.0343) / 2.0;
}

float getDistance(const int pins[]) {
  float a = _getDistanceRaw(pins);
  // If an object is detected, verify with 2 additional samples to eliminate phantom ground spikes
  if (a < 900.0) {
    delayMicroseconds(400);
    float b = _getDistanceRaw(pins);
    delayMicroseconds(400);
    float c = _getDistanceRaw(pins);
    
    // Return median reading
    if ((a <= b && b <= c) || (c <= b && b <= a)) return b;
    if ((b <= a && a <= c) || (c <= a && a <= b)) return a;
    return c;
  }
  return a;
}

// Timers for remote in-app door unlocks (auto-relock thermal protection)
static unsigned long remoteTopOpenTime      = 0;
static unsigned long remotePickupOpenTime   = 0;
static unsigned long remoteReceivedOpenTime = 0;

// ============================================================
//  Pickup Lock (GPIO 38) Hi-Z Control for 5V Active-LOW Solo Relay
//  Because the relay module VCC is powered by 5V, ESP32 3.3V HIGH
//  leaves (5V - 3.3V) = 1.7V which keeps the optocoupler ON.
//  In Hi-Z (INPUT) mode, the pin is electronically disconnected,
//  identical to unplugging the jumper wire, completely de-energizing the relay.
// ============================================================
void setPickupLock(bool unlock) {
  if (unlock) {
    pinMode(LOCK_PICKUP, OUTPUT);
    digitalWrite(LOCK_PICKUP, LOW);  // Drive LOW (GND) -> Optocoupler ON -> Energized (Unlocked)
  } else {
    pinMode(LOCK_PICKUP, INPUT);     // Hi-Z / Floating -> Pin Disconnected -> De-energized (Locked)
  }
  lockPickupOpen = unlock;
}

void processSensors() {
  // Rate-limit polling to once every 120ms to prevent CPU starvation and loop jitter
  static unsigned long lastSensorPoll = 0;
  if (millis() - lastSensorPoll < 120) return;
  lastSensorPoll = millis();

  // Platform and Pickup sensors physically removed (GPIO 15, 4 and GPIO 7, 16 free)
  lastUsPlatformDist = 999.0;
  lastUsPickupDist   = 999.0;

  // Poll only the active Drop-Off ultrasonic sensor
  lastUsDropoffDist = getDistance(US_DROPOFF);
  lastUsDropoffTime = millis();

  // Thermal Auto-Relock Safety for Remote App Unlocks (15 seconds max energized time)
  // Re-locking after 15s de-energizes the solenoid coil while slam latches allow the door
  // to be safely closed at any time.
  unsigned long now = millis();
  if (lockTopOpen && remoteTopOpenTime > 0 && (now - remoteTopOpenTime >= 15000)) {
    digitalWrite(LOCK_TOP, HIGH);
    lockTopOpen = false;
    remoteTopOpenTime = 0;
    Serial.println("[DOOR] Auto-Relock: Top door solenoid safely de-energized.");
    emitDoorState();
  }
  if (lockPickupOpen && remotePickupOpenTime > 0 && (now - remotePickupOpenTime >= 15000)) {
    setPickupLock(false);
    remotePickupOpenTime = 0;
    Serial.println("[DOOR] Auto-Relock: Pickup door solenoid safely de-energized.");
    emitDoorState();
  }
  if (lockReceivedOpen && remoteReceivedOpenTime > 0 && (now - remoteReceivedOpenTime >= 15000)) {
    digitalWrite(LOCK_RECEIVED, HIGH);
    lockReceivedOpen = false;
    remoteReceivedOpenTime = 0;
    Serial.println("[DOOR] Auto-Relock: Received door solenoid safely de-energized.");
    emitDoorState();
  }
}

void updateProcessingHUD(const char* status) {
  // Phase 4: In Progress
  displayMessage("PROCESSING", status);
}

// ============================================================
//  HANDLE: controlDoor from server (app-triggered manual control)
// ============================================================
void handleControlDoor(const String& payload) {
  StaticJsonDocument<256> doc;
  deserializeJson(doc, payload);

  String type   = doc["type"].as<String>();    // "top", "pickup", "received"
  String action = doc["action"].as<String>();  // "open", "close"

  Serial.print("[DOOR] Manual control: "); Serial.print(type);
  Serial.print(" → "); Serial.println(action);

  // Wake up if in lockscreen
  if (currentState == LOCKSCREEN) {
    changeState(IDLE);
    delay(50); // Give screen time to clear
  }

  bool isOpen = (action == "open");

  if (type == "top") {
    digitalWrite(LOCK_TOP, isOpen ? LOW : HIGH);
    lockTopOpen = isOpen;
    remoteTopOpenTime = isOpen ? millis() : 0;
  } else if (type == "pickup") {
    setPickupLock(isOpen);
    remotePickupOpenTime = isOpen ? millis() : 0;
  } else if (type == "received") {
    digitalWrite(LOCK_RECEIVED, isOpen ? LOW : HIGH);
    lockReceivedOpen = isOpen;
    remoteReceivedOpenTime = isOpen ? millis() : 0;
  } else {
    Serial.println("[DOOR] Unknown door type. Use: top, pickup, received");
    return;
  }

  char displayMsg[32];
  snprintf(displayMsg, sizeof(displayMsg), "%s door %s", type.c_str(), isOpen ? "opened" : "closed");
  
  displayMessage(isOpen ? "UNLOCKED" : "LOCKED", displayMsg);
  triggerBuzzer(isOpen ? 2 : 1);

  emitDoorState();
}
