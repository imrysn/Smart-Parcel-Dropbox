/**
 * ESP32-S3 Door Control System
 * Controls two doors (parcel entrance and user retrieval)
 * Communicates with backend via HTTP
 */

#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>

// WiFi credentials
const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";

// GPIO Pins for door control (relays)
const int PARCEL_DOOR_PIN = 17;  // GPIO17 for parcel door relay
const int USER_DOOR_PIN = 27;    // GPIO27 for user door relay

// GPIO Pin for parcel sensor (optional)
const int PARCEL_SENSOR_PIN = 22;  // GPIO22 for IR/ultrasonic sensor

// Door states
bool parcelDoorOpen = false;
bool userDoorOpen = false;

// Web server on port 80
WebServer server(80);

void setup() {
  Serial.begin(115200);
  
  // Initialize GPIO pins
  pinMode(PARCEL_DOOR_PIN, OUTPUT);
  pinMode(USER_DOOR_PIN, OUTPUT);
  pinMode(PARCEL_SENSOR_PIN, INPUT);
  
  // Ensure doors are closed initially
  digitalWrite(PARCEL_DOOR_PIN, LOW);
  digitalWrite(USER_DOOR_PIN, LOW);
  
  // Connect to WiFi
  Serial.println("Connecting to WiFi...");
  WiFi.begin(ssid, password);
  
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  
  Serial.println("");
  Serial.println("WiFi connected!");
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());
  
  // Setup HTTP endpoints
  server.on("/door", HTTP_POST, handleDoorControl);
  server.on("/status", HTTP_GET, handleGetStatus);
  server.on("/ping", HTTP_GET, handlePing);
  
  // Enable CORS
  server.enableCORS(true);
  
  // Start server
  server.begin();
  Serial.println("HTTP server started");
}

void loop() {
  server.handleClient();
}

/**
 * POST /door
 * Control a specific door
 * Body: {"type": "parcel", "action": "open"}
 */
void handleDoorControl() {
  if (server.hasArg("plain")) {
    String body = server.arg("plain");
    
    StaticJsonDocument<200> doc;
    DeserializationError error = deserializeJson(doc, body);
    
    if (error) {
      server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
      return;
    }
    
    String doorType = doc["type"];
    String action = doc["action"];
    
    Serial.printf("Door Control: %s door %s\n", doorType.c_str(), action.c_str());
    
    if (doorType == "parcel") {
      if (action == "open") {
        digitalWrite(PARCEL_DOOR_PIN, HIGH);
        parcelDoorOpen = true;
        Serial.println("✅ Parcel door OPENED");
      } else if (action == "close") {
        digitalWrite(PARCEL_DOOR_PIN, LOW);
        parcelDoorOpen = false;
        Serial.println("✅ Parcel door CLOSED");
      }
    } else if (doorType == "user") {
      if (action == "open") {
        digitalWrite(USER_DOOR_PIN, HIGH);
        userDoorOpen = true;
        Serial.println("✅ User door OPENED");
      } else if (action == "close") {
        digitalWrite(USER_DOOR_PIN, LOW);
        userDoorOpen = false;
        Serial.println("✅ User door CLOSED");
      }
    }
    
    // Send response
    StaticJsonDocument<200> response;
    response["success"] = true;
    response["parcelDoorOpen"] = parcelDoorOpen;
    response["userDoorOpen"] = userDoorOpen;
    
    String responseStr;
    serializeJson(response, responseStr);
    server.send(200, "application/json", responseStr);
  } else {
    server.send(400, "application/json", "{\"error\":\"No body\"}");
  }
}

/**
 * GET /status
 * Get current door states
 */
void handleGetStatus() {
  bool parcelDetected = digitalRead(PARCEL_SENSOR_PIN) == HIGH;
  
  StaticJsonDocument<200> doc;
  doc["parcelDoorOpen"] = parcelDoorOpen;
  doc["userDoorOpen"] = userDoorOpen;
  doc["parcelDetected"] = parcelDetected;
  
  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

/**
 * GET /ping
 * Health check
 */
void handlePing() {
  server.send(200, "text/plain", "pong");
}
