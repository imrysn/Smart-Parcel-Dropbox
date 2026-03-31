// ============================================================
//  HardwareController.ino
//  Contains logic for Servos, Buzzers, Doors, Sensors, and Resets
// ============================================================

void moveServoSmoothly(int from, int to) {
  from = constrain(from, 0, 180);
  to   = constrain(to,   0, 180);

  platformServo.attach(SERVO_PIN, 500, 2500);

  int step = (from < to) ? 1 : -1;
  int current = from;
  unsigned long lastStep = millis();
  
  platformServo.write(current);
  delay(15);
  
  while (current != to) {
    if (millis() - lastStep >= 15) {
      current += step;
      platformServo.write(current);
      lastStep = millis();
      socketIO.loop();      
    }
  }
}

void shakeServo(int targetAngle) {
  Serial.println("[PHYS] Breaking static friction (shake)...");
  platformServo.attach(SERVO_PIN, 500, 2500);
  
  for (int i = 0; i < 3; i++) {
    int jitter = (targetAngle == 0) ? 15 : -15; // Jitter towards center
    platformServo.write(targetAngle + jitter);
    delay(150);
    platformServo.write(targetAngle);
    delay(150);
  }
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
  const int SAMPLES = 3;
  float readings[SAMPLES];
  int validCount = 0;

  for (int i = 0; i < SAMPLES; i++) {
    digitalWrite(pins[0], LOW);
    delayMicroseconds(5);
    digitalWrite(pins[0], HIGH);
    delayMicroseconds(15); 
    digitalWrite(pins[0], LOW);
    
    // Increased timeout for 320cm max range
    long dur = pulseIn(pins[1], HIGH, 25000); 

    if (dur > 100 && dur < 20000) { 
        readings[validCount++] = (dur * 0.0343) / 2.0;
    }
  }

  if (validCount == 0) return 999.0;

  // Simple sort for median
  for (int i = 0; i < validCount-1; i++) {
    for (int j = i+1; j < validCount; j++) {
      if (readings[i] > readings[j]) {
        float temp = readings[i]; readings[i] = readings[j]; readings[j] = temp;
      }
    }
  }
  return readings[validCount / 2];
}

void updateProcessingHUD(String status) {
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
