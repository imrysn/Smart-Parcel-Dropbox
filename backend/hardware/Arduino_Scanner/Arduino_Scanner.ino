#include <SoftwareSerial.h>

// Scanner connected to Pins 2 and 3
SoftwareSerial scannerSerial(2, 3); // RX, TX

const int trigPin = 9;
const int echoPin = 10;

// Configuration Constants
const int detectDistanceCm = 10;    
const int stableTimeMs = 800;      
const int safetyExitCm = 40;       

// State Variables
unsigned long detectionStartTime = 0;
bool isTracking = false;
bool autoScanEnabled = true; // Toggle to bypass proximity sensor

void setup() {
  // We use Hardware Serial (Pins 0/1) to talk to the ESP32 and USB Monitor
  Serial.begin(9600); 
  scannerSerial.begin(9600);
  
  pinMode(trigPin, OUTPUT); 
  pinMode(echoPin, INPUT);
}

void loop() {
  // --- SCANNER TEST & TOGGLES VIA SERIAL ---
  if (Serial.available()) {
    char cmd = Serial.read();
    if (cmd == 'T' || cmd == 't') {
      Serial.println("[TEST] Manual trigger received. Starting scan...");
      executeScanningSession();
    } else if (cmd == 'A' || cmd == 'a') {
      autoScanEnabled = !autoScanEnabled;
      Serial.print("[AUTO] Auto-Scan set to: ");
      Serial.println(autoScanEnabled ? "ON (Listening to US sensor)" : "OFF (Wait for Serial 'T')");
    }
  }

  // --- AUTOMATIC PROXIMITY TRIGGER ---
  if (autoScanEnabled) {
    int currentDistance = checkDistance();

    if (currentDistance > 1 && currentDistance <= detectDistanceCm) {
      if (!isTracking) {
        detectionStartTime = millis();
        isTracking = true;
      } else {
        if (millis() - detectionStartTime >= stableTimeMs) {
          executeScanningSession();
          isTracking = false; 
        }
      }
    } else {
      isTracking = false;
    }
  }
  
  delay(50); 
}

void executeScanningSession() {
  bool scanned = false;
  unsigned long sessionStart = millis();
  unsigned long lastTriggerTime = 0;

  while (!scanned && (millis() - sessionStart < 5000)) {
    // Non-blocking trigger every 500ms
    if (millis() - lastTriggerTime >= 500) {
      scannerSerial.print("~T.\r"); 
      lastTriggerTime = millis();
    }
    
    // Continuous Polling: Prevent SoftwareSerial (64-byte buffer) from overflowing.
    if (scannerSerial.available()) {
      String barcode = "";
      while (scannerSerial.available()) {
        char c = scannerSerial.read();
        if (c != '\n' && c != '\r') barcode += c;
        delay(2);
      }
      
      delay(30);
      while (scannerSerial.available()) {
        char c = scannerSerial.read();
        if (c != '\n' && c != '\r') barcode += c;
      }

      if (barcode.startsWith("T")) { barcode.remove(0, 1); }
      barcode = cleanString(barcode);

      if (barcode.length() > 3) {
        Serial.println(barcode); 
        scanned = true; 
        delay(3000); // Prevent double-scans
      }
    }
    
    // Safety exit check (using filtered distance)
    if (checkDistance() > safetyExitCm) break;
  }
}

String cleanString(String str) {
  String cleaned = "";
  for (int i = 0; i < str.length(); i++) {
    if (str[i] >= 32 && str[i] <= 126) { 
      cleaned += str[i];
    }
  }
  return cleaned;
}

int checkDistance() {
  long total = 0;
  int validSamples = 0;

  for (int i = 0; i < 5; i++) {
    digitalWrite(trigPin, LOW); 
    delayMicroseconds(2);
    digitalWrite(trigPin, HIGH); 
    delayMicroseconds(10);
    digitalWrite(trigPin, LOW);
    
    long duration = pulseIn(echoPin, HIGH, 25000); // 25ms timeout
    long dist = (long)(duration * 0.034 / 2.0);
    
    if (dist > 1 && dist < 400) { 
      total += dist;
      validSamples++;
    }
    delay(10); 
  }

  if (validSamples < 3) return 999; 
  return (int)(total / validSamples);
}