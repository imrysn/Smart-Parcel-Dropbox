// ============================================================
//  HardwareController.ino
//  Contains logic for Servos, Buzzers, Doors, Sensors, and Resets
// ============================================================

void moveServoSmoothly(int from, int to) {
  from = constrain(from, 0, 180);
  to   = constrain(to,   0, 180);

  platformServo.attach(SERVO_PIN, 1000, 2000);

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

void triggerBuzzer(int beeps) {
  for (int i = 0; i < beeps; i++) {
    digitalWrite(BUZZER_PIN, HIGH); delay(100);
    digitalWrite(BUZZER_PIN, LOW);  delay(100);
  }
}

float getDistance(const int pins[]) {
  digitalWrite(pins[0], LOW);
  delayMicroseconds(2);
  digitalWrite(pins[0], HIGH);
  delayMicroseconds(10);
  digitalWrite(pins[0], LOW);
  long dur = pulseIn(pins[1], HIGH, 30000); // 30ms timeout

  if (dur == 0) return 999.0;
  return (dur * 0.034) / 2.0;
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
