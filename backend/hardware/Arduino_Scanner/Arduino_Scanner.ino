#include <SoftwareSerial.h>

// Scanner connected to Pins 2 and 3
SoftwareSerial scannerSerial(2, 3); // RX, TX

const int trigPin = 9;
const int echoPin = 10;

// Configuration Constants
const int detectDistanceCm = 20;    
const int stableTimeMs = 800;      
const int safetyExitCm = 75;       

// State Variables
unsigned long detectionStartTime = 0;
bool isTracking = false;

void setup() {
  // We use Hardware Serial (Pins 0/1) to talk to the ESP32
  Serial.begin(9600); 
  scannerSerial.begin(9600);
  
  pinMode(trigPin, OUTPUT); 
  pinMode(echoPin, INPUT);
  
  // This will show up on the Uno's monitor AND the ESP32's Serial2
  Serial.println("UNO_READY"); 
}

void loop() {
  int currentDistance = checkDistance();

  if (currentDistance > 0 && currentDistance <= detectDistanceCm) {
    if (!isTracking) {
      detectionStartTime = millis();
      isTracking = true;
    } else {
      if (millis() - detectionStartTime >= stableTimeMs) {
        // Parcel is stable, trigger the scanner
        executeScanningSession();
        isTracking = false; 
      }
    }
  } else {
    isTracking = false;
  }
  delay(50); 
}

void executeScanningSession() {
  bool scanned = false;
  unsigned long sessionStart = millis();

  while (!scanned && (millis() - sessionStart < 5000)) {
    scannerSerial.print("~T."); // Trigger the physical scanner
    delay(500); 
    
    if (scannerSerial.available()) {
      String barcode = "";
      while (scannerSerial.available()) {
        char c = scannerSerial.read();
        if (c != '\n' && c != '\r') {
          barcode += c;
        }
        delay(5); 
      }

      // Sanitize
      if (barcode.startsWith("T")) { barcode.remove(0, 1); }
      barcode = cleanString(barcode);

      if (barcode.length() > 3) {
        // SEND DATA TO ESP32-S3
        // Serial.println sends the string + \n, which the ESP32 is looking for
        Serial.println(barcode); 
        
        scanned = true; 
        delay(3000); // Prevent double-scans
      }
    }
    
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
  digitalWrite(trigPin, LOW); 
  delayMicroseconds(2);
  digitalWrite(trigPin, HIGH); 
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);
  long duration = pulseIn(echoPin, HIGH, 30000);
  int dist = duration * 0.034 / 2;
  return (dist == 0) ? 999 : dist;
}