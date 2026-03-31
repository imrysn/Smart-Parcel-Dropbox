// ============================================================
//  NetworkController2.ino (Part 2/2)
//  Socket.io Emitters and Receivers
// ============================================================

void emitVerifyScan(const String& trackingId, const String& mode) {
  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("verifyScan");
  JsonObject data = arr.createNestedObject();
  data["trackingId"] = trackingId;
  data["mode"]       = mode;

  char output[256];
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output);
  if (DEBUG_WS) { Serial.print("[WS] Emitted verifyScan: "); Serial.println(output); }
}

void emitVerifyRider(const String& riderId) {
  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("verifyRider");
  JsonObject data = arr.createNestedObject();
  data["riderId"] = riderId;

  char output[256];
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output);
  if (DEBUG_WS) { Serial.print("[WS] Emitted verifyRider: "); Serial.println(output); }
}

void emitRequestOwnerSession() {
  StaticJsonDocument<128> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("requestOwnerSession");
  arr.createNestedObject();

  char output[128];
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output);
  Serial.println("[WS] Emitted requestOwnerSession");
}

void emitRegisterOwnerPickup(const String& trackingId) {
  if (!socketIO.isConnected()) {
    if (offlineQueueCount < MAX_OFFLINE_QUEUE) {
      offlineQueue[offlineQueueCount++] = trackingId;
      Serial.print("[OFFLINE] Queued owner pickup: "); Serial.println(trackingId);
    } else {
      Serial.println("[OFFLINE] ERROR: Queue full. Cannot queue more pickups.");
    }
    return;
  }

  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("registerOwnerPickup");
  JsonObject data = arr.createNestedObject();
  data["trackingId"] = trackingId;

  char output[256];
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output);
  if (DEBUG_WS) { Serial.print("[WS] Emitted registerOwnerPickup: "); Serial.println(output); }
}

void emitStatusUpdate(const String& trackingId, const String& status, const String& mode) {
  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("statusUpdate");
  JsonObject data = arr.createNestedObject();
  data["trackingId"] = trackingId;
  data["status"]     = status;
  data["mode"]       = mode;

  char output[256];
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output);
  if (DEBUG_WS) { Serial.print("[WS] Emitted statusUpdate: "); Serial.println(output); }
}

void emitDoorState() {
  float platformDist = getDistance(US_PLATFORM);
  bool parcelOnPlatform = (platformDist > 1.0 && platformDist < 18.0);
  bool parcelInDropOff  = (getDistance(US_DROPOFF) < 25.0);
  bool parcelInPickup   = (getDistance(US_PICKUP)  < 25.0);

  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("doorStateUpdate");
  JsonObject data = arr.createNestedObject();
  data["parcelDoorOpen"]    = lockTopOpen;       
  data["pickupDoorOpen"]    = lockPickupOpen;    
  data["receivedDoorOpen"]  = lockReceivedOpen;  
  data["parcelDetected"]    = parcelOnPlatform;  
  data["parcelInDropOff"]   = parcelInDropOff;   
  data["parcelInPickup"]    = parcelInPickup;    
  data["systemState"]       = (int)currentState; 

  char output[256];
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output);
  if (DEBUG_WS) { Serial.print("[WS] Emitted doorStateUpdate: "); Serial.println(output); }
}

void handleRequestWiFiScan() {
  Serial.println("[WS] WiFi Scan request received.");
  int n = WiFi.scanNetworks();
  Serial.print("[WS] Scan complete. Found "); Serial.print(n); Serial.println(" networks.");
  emitWifiScanResult(n);
}

void emitWifiScanResult(int n) {
  StaticJsonDocument<2048> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("wifiScanResult");
  JsonObject data = arr.createNestedObject();
  JsonArray networks = data.createNestedArray("networks");

  // Limit to top 15 networks to avoid hitting memory/packet limits
  int count = min(n, 15);
  for (int i = 0; i < count; i++) {
    JsonObject net = networks.createNestedObject();
    net["ssid"]   = WiFi.SSID(i);
    net["rssi"]   = WiFi.RSSI(i);
    net["secure"] = (WiFi.encryptionType(i) != WIFI_OFF);
  }

  char output[2048];
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output);
  if (DEBUG_WS) { Serial.print("[WS] Emitted wifiScanResult: "); Serial.println(output); }
}

void handleApplyHardwareConfig(const String& payload) {
  StaticJsonDocument<512> doc;
  deserializeJson(doc, payload);

  String ssid = doc["ssid"].as<String>();
  String pass = doc["password"].as<String>();

  if (ssid == "") {
    Serial.println("[WS] Error: Received empty SSID.");
    return;
  }

  Serial.print("[WS] Applying new WiFi config. SSID: "); Serial.println(ssid);
  
  nvsPrefs.begin("smartbox", false);
  nvsPrefs.putString("ssid", ssid);
  nvsPrefs.putString("password", pass);
  nvsPrefs.putBool("registered", true); // Device is already registered if we are here
  nvsPrefs.end();

  displayMessage("WIFI SAVED", "Rebooting...");
  triggerBuzzer(2);
  // Notify backend before we reboot
  StaticJsonDocument<128> ack;
  JsonArray ackArr = ack.to<JsonArray>();
  ackArr.add("hardwareConfigApplied");
  JsonObject ackData = ackArr.createNestedObject();
  ackData["deviceId"] = WiFi.macAddress();
  char ackOutput[128];
  serializeJson(ack, ackOutput);
  socketIO.send(sIOtype_EVENT, ackOutput);
  
  delay(1000);
  ESP.restart();
}

void handleScanResult(const String& payload) {
  StaticJsonDocument<256> doc;
  deserializeJson(doc, payload);

  bool valid = doc["valid"].as<bool>();
  Serial.print("[WS] scanResult → valid: "); Serial.println(valid ? "YES" : "NO");

  scanResultValid    = valid;
  scanResultReceived = true;
}

void handleRiderVerifyResult(const String& payload) {
  StaticJsonDocument<256> doc;
  deserializeJson(doc, payload);

  bool valid = doc["valid"].as<bool>();
  Serial.print("[WS] riderVerifyResult → valid: "); Serial.println(valid ? "YES" : "NO");

  riderVerifyValid    = valid;
  riderVerifyReceived = true;
}

void handleRegisterTracking(const String& payload) {
  StaticJsonDocument<256> doc;
  deserializeJson(doc, payload);

  String trackingId = doc["trackingId"].as<String>();
  String mode       = doc["mode"].as<String>();  

  if (mode == "drop_off") {
    registeredDropOff = trackingId;
    dropOffRegisterTime = millis();
    Serial.print("[REG] Drop Off ID registered via app: "); Serial.println(registeredDropOff);
    displayMessage("ID REGISTERED", ("Drop Off: " + trackingId.substring(0, 10)).c_str());
  } else if (mode == "pick_up") {
    registeredPickup = trackingId;
    pickupRegisterTime = millis();
    Serial.print("[REG] Pick Up ID registered via app: "); Serial.println(registeredPickup);
    displayMessage("ID REGISTERED", ("Pick Up: " + trackingId.substring(0, 10)).c_str());
  } else {
    Serial.print("[REG] Unknown mode: "); Serial.println(mode);
    return;
  }

  triggerBuzzer(1);
  delay(1500);
  if (currentState == IDLE) showHomeScreen();
}
