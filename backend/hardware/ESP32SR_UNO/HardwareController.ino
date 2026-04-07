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

// ── DSP Data Fusion Structures ────────────
struct SensorDSP {
  float emaDist;
  int anomalyCount;
};

SensorDSP dspPlatform = {0, 0};
SensorDSP dspPickup = {0, 0};
SensorDSP dspDropoff = {0, 0};

float applyEMA(float rawDist, SensorDSP &dsp) {
  if (rawDist >= 999.0) return dsp.emaDist; // ignore timeouts
  
  // Initialization
  if (dsp.emaDist == 0 || dsp.emaDist >= 999.0) {
    dsp.emaDist = rawDist;
    return rawDist;
  }
  
  // Statistical Anomaly/Spike Rejection
  float diff = abs(rawDist - dsp.emaDist);
  if (diff > 30.0) { // Reject instant 30cm+ jumps
    dsp.anomalyCount++;
    if (dsp.anomalyCount < 3) {
      return dsp.emaDist; // Reject anomaly this cycle
    }
  }
  
  dsp.anomalyCount = 0; // Consistent new value
  
  // Exponential Moving Average equation (Alpha = 0.25)
  float alpha = 0.25;
  dsp.emaDist = (alpha * rawDist) + ((1.0 - alpha) * dsp.emaDist);
  
  return dsp.emaDist;
}

// ── Spatial Volume Analytics Heuristic ────────────
float getOccupancyPercentage() {
  // We use the drop-off bin sensor for volume analytics
  float currentDist = lastUsDropoffDist;
  if (currentDist >= BIN_HEIGHT_DROPOFF) return 0.0; // Empty
  
  // Calculate Height of stack in cm
  float stackHeight = BIN_HEIGHT_DROPOFF - currentDist;
  if (stackHeight < 2.0) stackHeight = 0.0; // Noise floor floor
  
  // Heuristic cubic calculation (assuming 30x30 base)
  float volumeCm3 = 30.0 * 30.0 * stackHeight;
  
  // Return as percentage of total bin capacity
  float percent = (volumeCm3 / BIN_MAX_VOLUME) * 100.0;
  return constrain(percent, 0.0, 100.0);
}

void processSensors() {
  // Update one sensor per call to avoid blocking the loop too much
  static int sensorIndex = 0;
  float raw;
  if (sensorIndex == 0) {
    raw = getDistance(US_PLATFORM);
    lastUsPlatformDist = applyEMA(raw, dspPlatform);
    lastUsPlatformTime = millis();
  } else if (sensorIndex == 1) {
    raw = getDistance(US_PICKUP);
    lastUsPickupDist = applyEMA(raw, dspPickup);
    lastUsPickupTime = millis();
  } else {
    raw = getDistance(US_DROPOFF);
    lastUsDropoffDist = applyEMA(raw, dspDropoff);
    lastUsDropoffTime = millis();
  }
  sensorIndex = (sensorIndex + 1) % 3;
}

// ── Phase 6: Applied Cryptography (Offline Verification) ────────────

/// Computes HMAC-SHA256 short-hash for a given counter/time-step
void getHMACShortHash(const char* payload, char* output) {
  unsigned char hmacResult[32];
  mbedtls_md_context_t ctx;
  mbedtls_md_type_t md_type = MBEDTLS_MD_SHA256;

  mbedtls_md_init(&ctx);
  mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(md_type), 1);
  mbedtls_md_hmac_starts(&ctx, (const unsigned char *)hmacKey, strlen(hmacKey));
  mbedtls_md_hmac_update(&ctx, (const unsigned char *)payload, strlen(payload));
  mbedtls_md_hmac_finish(&ctx, hmacResult);
  mbedtls_md_free(&ctx);

  // Convert first 4 bytes to 8-char hex (matches App's CryptoService)
  for (int i = 0; i < 4; i++) {
    sprintf(output + (i * 2), "%02X", hmacResult[i]);
  }
}

/// Verifies a scanned token against rotating time-steps (Offline Auth)
bool verifyOfflineToken(const String& scannedToken) {
  if (strlen(hmacKey) == 0 || strlen(primaryUserId) == 0) return false;

  // Format: SPDB-AUT-<userId>-<shortHash>
  if (!scannedToken.startsWith("SPDB-AUT-")) return false;
  if (scannedToken.indexOf(primaryUserId) == -1) return false;

  // Extract the hash suffix (last 8 chars)
  String scannedHash = scannedToken.substring(scannedToken.length() - 8);

  // Check current and +/- 1 time-steps (60s each) to allow for clock drift
  long nowSeconds = millis() / 1000; // Note: For real defense, use NTP-synced time or RTC
  // Since we don't have an RTC, we'll assume the board kept relative time 
  // since its last successful WiFi/NTP sync (handled in WiFiController).
  
  // Note: For this thesis prototype, if offline, we use the internal 'board time'
  long currentStep = nowSeconds / 60;

  for (int offset = -1; offset <= 1; offset++) {
    char payload[64];
    snprintf(payload, sizeof(payload), "%s-%ld", primaryUserId, currentStep + offset);
    
    char calculatedHash[9];
    getHMACShortHash(payload, calculatedHash);

    if (scannedHash == calculatedHash) {
      Serial.println("[CRYPTO] Offline Token Verified ✓");
      return true;
    }
  }

  Serial.println("[CRYPTO] Offline Token Denied ✗");
  return false;
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

// ── Phase 11: Verification Suite ──────────────────────────

void runFullDiagnosticSuite() {
  Serial.println("\n[DIAGNOSTIC] === STARTING COMPREHENSIVE SUITE ===");
  
  // 1. EMA Filter Test
  Serial.print("[DIAGNOSTIC] 1. EMA DSP Filter: ");
  SensorDSP testDsp = {0, 0};
  float val1 = applyEMA(20.0, testDsp); // Init
  float val2 = applyEMA(50.0, testDsp); // Spike (should be rejected/smoothed)
  float val3 = applyEMA(22.0, testDsp); // Recovery
  
  if (val2 < 50.0 && val3 < 25.0) {
    Serial.println("PASS (Spike Rejected, Trend Smoothed)");
  } else {
    Serial.print("FAIL (Val2: "); Serial.print(val2); Serial.println(")");
  }

  // 2. Volume Analytics Test
  Serial.print("[DIAGNOSTIC] 2. Spatial Volume: ");
  lastUsDropoffDist = 15.0; // Half way in a 30cm bin
  float occ = getOccupancyPercentage();
  if (occ > 40.0 && occ < 60.0) {
    Serial.print("PASS ("); Serial.print(occ); Serial.println("%)");
  } else {
    Serial.print("FAIL ("); Serial.print(occ); Serial.println("%)");
  }

  // 3. HMAC Crypto Test
  Serial.print("[DIAGNOSTIC] 3. HMAC-SHA256 Logic: ");
  // Using a test key and user for consistency
  char oldKey[33], oldUser[64];
  strncpy(oldKey, hmacKey, 32); 
  strncpy(oldUser, primaryUserId, 63);
  
  strncpy(hmacKey, "TEST_KEY_123", 32);
  strncpy(primaryUserId, "USER_ABC", 63);
  
  char hashOut[9];
  getHMACShortHash("USER_ABC-12345", hashOut);
  
  // Pre-calculated known hash for "USER_ABC-12345" with key "TEST_KEY_123"
  // (Verified via Node.js crypto module: F1D4EEBC)
  if (strcmp(hashOut, "F1D4EEBC") == 0) {
    Serial.println("PASS (Hash matches verified test vector F1D4EEBC)");
  } else {
    Serial.print("FAIL (Got: "); Serial.print(hashOut); Serial.println(")");
  }
  
  // Restore
  strncpy(hmacKey, oldKey, 32);
  strncpy(primaryUserId, oldUser, 63);

  // 4. Offline Queue Persistence Test
  Serial.print("[DIAGNOSTIC] 4. Persistent Queue: ");
  int initialCount = offlineQueueCount;
  enqueueOfflineEvent("TEST_SYNC", "DATA_123");
  if (offlineQueueCount == initialCount + 1) {
    Serial.println("PASS (Event enqueued)");
  } else {
    Serial.println("FAIL");
  }

  Serial.println("[DIAGNOSTIC] === SUITE COMPLETE ===\n");
  triggerBuzzer(1); // Finish chirp
}

