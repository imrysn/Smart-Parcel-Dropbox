/**
 * Arduino UNO R3 Barcode Scanner
 * Reads data from MH-ET Live Scanner v3 and sends via Serial
 */

// Scanner connected to Serial pins (RX/TX)
// Or use SoftwareSerial if needed

String barcodeData = "";
bool scanComplete = false;

void setup() {
  // Initialize Serial for communication with backend
  Serial.begin(9600);
  
  Serial.println("Arduino Barcode Scanner Ready");
  Serial.println("Waiting for scans...");
}

void loop() {
  // Read data from scanner
  while (Serial.available() > 0) {
    char inChar = (char)Serial.read();
    
    if (inChar == '\n' || inChar == '\r') {
      // End of barcode
      if (barcodeData.length() > 0) {
        scanComplete = true;
      }
    } else {
      // Add character to barcode
      barcodeData += inChar;
    }
  }
  
  // Process complete barcode
  if (scanComplete) {
    // Send barcode to backend via Serial
    Serial.println(barcodeData);
    
    // Optional: Add visual/audio feedback
    // digitalWrite(LED_PIN, HIGH);
    // tone(BUZZER_PIN, 1000, 100);
    
    // Reset for next scan
    barcodeData = "";
    scanComplete = false;
    
    delay(100);  // Debounce
  }
}

/**
 * Alternative: If scanner uses SoftwareSerial
 */

/*
#include <SoftwareSerial.h>

// Scanner connected to pins 2 (RX) and 3 (TX)
SoftwareSerial scannerSerial(2, 3);

void setup() {
  Serial.begin(9600);        // Communication with backend
  scannerSerial.begin(9600); // Communication with scanner
  
  Serial.println("Scanner Ready");
}

void loop() {
  while (scannerSerial.available() > 0) {
    char inChar = (char)scannerSerial.read();
    
    if (inChar == '\n' || inChar == '\r') {
      if (barcodeData.length() > 0) {
        // Send to backend
        Serial.println(barcodeData);
        barcodeData = "";
      }
    } else {
      barcodeData += inChar;
    }
  }
}
*/
