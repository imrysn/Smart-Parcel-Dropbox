// ============================================================
//  HardwareController.ino
//  Contains logic for Servos, Buzzers, Doors, Sensors, and Resets
// ============================================================

void moveServoSmoothly(int to) {
  targetServoPos = constrain(to, 0, 180);
  if (!platformServo.attached()) {
    platformServo.attach(SERVO_PIN, 500, 2500);
  }
}

void processServo() {
  if (currentServoPos == targetServoPos) return;
  
  if (millis() - lastServoMoveTime >= 15) {
    int step = (currentServoPos < targetServoPos) ? 1 : -1;
    currentServoPos += step;
    platformServo.write(currentServoPos);
    lastServoMoveTime = millis();
  }
}

void shakeServo(int targetAngle) {
  // We'll keep this as a special sequence but use the non-blocking target logic
  moveServoSmoothly(targetAngle + 15);
  // Real non-blocking shake would need a mini state machine, 
  // let's simplify and just move to targeted angle for now to maintain stability
  targetServoPos = targetAngle; 
}

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

float getDistance(const int pins[]) {
  // Non-blocking trigger and wait logic
  // Trigger
  digitalWrite(pins[0], LOW);
  delayMicroseconds(2);
  digitalWrite(pins[0], HIGH);
  delayMicroseconds(10);
  digitalWrite(pins[0], LOW);
  
  // We use a shorter timeout for performance
  long dur = pulseIn(pins[1], HIGH, 20000); 
  if (dur == 0) return 999.0;
  return (dur * 0.0343) / 2.0;
}

void processSensors() {
  // Update one sensor per call to avoid blocking the loop too much
  static int sensorIndex = 0;
  if (sensorIndex == 0) {
    lastUsPlatformDist = getDistance(US_PLATFORM);
    lastUsPlatformTime = millis();
  } else if (sensorIndex == 1) {
    lastUsPickupDist = getDistance(US_PICKUP);
    lastUsPickupTime = millis();
  } else {
    lastUsDropoffDist = getDistance(US_DROPOFF);
    lastUsDropoffTime = millis();
  }
  sensorIndex = (sensorIndex + 1) % 3;
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

  char displayMsg[32];
  snprintf(displayMsg, sizeof(displayMsg), "%s door %s", type.c_str(), isOpen ? "opened" : "closed");
  
  displayMessage(isOpen ? "UNLOCKED" : "LOCKED", displayMsg);
  triggerBuzzer(isOpen ? 2 : 1);

  emitDoorState();
}
