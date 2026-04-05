// ============================================================
//  NetworkController.ino (Part 1/2)
//  WiFi, Socket.IO setup, and Event Handlers
// ============================================================

void setupWiFi() {
  String ssid;
  String password;
  nvsPrefs.begin("smartbox", true);
  String s_ssid = nvsPrefs.getString("ssid", "");
  String s_pass = nvsPrefs.getString("password", "");
  strncpy(nvsWifiSSID, s_ssid.c_str(), sizeof(nvsWifiSSID)-1);
  strncpy(nvsWifiPassword, s_pass.c_str(), sizeof(nvsWifiPassword)-1);
  nvsPrefs.end();

  if (strlen(nvsWifiSSID) != 0) {
    ssid = String(nvsWifiSSID);
    password = String(nvsWifiPassword);
    Serial.println("[WiFi] Using custom credentials from NVS.");
  } else {
    ssid = String(WIFI_SSID);
    password = String(WIFI_PASSWORD);
    Serial.println("[WiFi] NVS credentials NOT found. Falling back to config.h.");
  }

  Serial.print("[WiFi] SSID: "); Serial.println(ssid);
  // Do NOT print password for security, but we know which source we used

  tft.fillScreen(COLOR_BG);
  
  // Clean spinning or concentric circle loader
  tft.fillCircle(160, 90, 6, COLOR_ACCENT);
  tft.drawCircle(160, 90, 18, COLOR_ACCENT);
  tft.drawCircle(160, 90, 30, COLOR_GREY);
  
  tft.setFont(&FreeSansBold12pt7b);
  tft.setTextColor(COLOR_TEXT);
  tft.setCursor(75, 145); tft.print("Getting Online");
  
  tft.setFont(&FreeSans9pt7b);
  tft.setTextColor(COLOR_GREY);
  tft.setCursor(110, 175); tft.print("Please wait...");
  tft.setFont();

  WiFi.begin(ssid.c_str(), password.c_str());

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    // esp_task_wdt_reset(); // Disabled to prevent spam after detaching main loop
    delay(500);
    Serial.print(".");
    attempts++;
    
    // Draw loading dots in a rounded pill
    tft.fillRoundRect(110, 190, 100, 20, 10, COLOR_CARD);
    tft.setCursor(118, 195); tft.setTextColor(COLOR_ACCENT); tft.setTextSize(1);
    for (int d = 0; d < (attempts % 4); d++) tft.print(". ");
  }

  tft.setTextSize(1); // Reset scale
  tft.setFont();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.print("[WiFi] Connected! IP: ");
    Serial.println(WiFi.localIP());

    tft.fillScreen(COLOR_BG);
    tft.fillCircle(160, 90, 25, COLOR_GREEN); // Big success circle
    
    tft.setFont(&FreeSansBold12pt7b);
    tft.setTextColor(COLOR_TEXT);
    tft.setCursor(100, 145); tft.print("Connected!");
    
    tft.setFont(&FreeSans9pt7b);
    tft.setTextColor(COLOR_GREY);
    tft.setCursor(95, 175); tft.print("System is ready");
    tft.setFont();
    delay(1500);
  } else {
    Serial.println();
    Serial.println("[WiFi] FAILED to connect. Running offline.");

    tft.fillScreen(COLOR_BG);
    tft.fillCircle(160, 90, 25, COLOR_RED);
    
    tft.setFont(&FreeSansBold12pt7b);
    tft.setTextColor(COLOR_TEXT);
    tft.setCursor(90, 145); tft.print("Offline Mode");
    
    tft.setFont(&FreeSans9pt7b);
    tft.setTextColor(COLOR_GREY);
    tft.setCursor(65, 175); tft.print("Some features unavailable");
    tft.setFont();
    delay(2000);
  }
}

void setupSocketIO() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WS] Skipping Socket.IO — no WiFi.");
    return;
  }

  Serial.print("[WS] Connecting to server: ");
  Serial.print(SERVER_HOST); Serial.print(":"); Serial.println(SERVER_PORT);

  socketIO.onEvent(socketIOEvent);
  socketIO.begin(SERVER_HOST, SERVER_PORT, SERVER_PATH);
  socketIO.setReconnectInterval(5000);

  Serial.println("[WS] Socket.IO initiated — connecting in background...");
}

void socketIOEvent(socketIOmessageType_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case sIOtype_CONNECT:
      Serial.println("[WS] Socket.IO connected.");
      socketIO.send(sIOtype_EVENT, "[\"join\",\"esp32_device\"]");
      
      if (offlineQueueCount > 0) {
        Serial.print("[OFFLINE] Processing queue of "); 
        Serial.print(offlineQueueCount); 
        Serial.println(" items...");
        
        for (int i = 0; i < offlineQueueCount; i++) {
           emitRegisterOwnerPickup(offlineQueue[i]);
           delay(100);
        }
        offlineQueueCount = 0;
      }
      break;

    case sIOtype_DISCONNECT:
      Serial.println("[WS] Socket.IO disconnected.");
      break;

    case sIOtype_EVENT: {
      String msg = String((char*)payload, length);
      if (DEBUG_WS) { Serial.print("[WS] Event: "); Serial.println(msg); }

      StaticJsonDocument<1024> doc;
      DeserializationError err = deserializeJson(doc, payload, length);
      if (err) {
        Serial.print("[WS] JSON parse error: "); Serial.println(err.c_str());
        break;
      }

      String eventName = doc[0].as<String>();

      if (eventName == "scanResult") {
        String data; serializeJson(doc[1], data);
        handleScanResult(data);
      } else if (eventName == "riderVerifyResult") {
        String data; serializeJson(doc[1], data);
        handleRiderVerifyResult(data);
      } else if (eventName == "registerTracking") {
        String data; serializeJson(doc[1], data);
        handleRegisterTracking(data);
      } else if (eventName == "controlDoor") {
        String data; serializeJson(doc[1], data);
        handleControlDoor(data);
      } else if (eventName == "ownerSessionToken") {
        strncpy(ownerSessionToken, doc[1]["token"] | "", sizeof(ownerSessionToken)-1);
        Serial.print("[WS] ownerSessionToken received: "); Serial.println(ownerSessionToken);
      } else if (eventName == "ownerVerifyResult") {
        ownerApprovalValid    = doc[1]["approved"].as<bool>();
        ownerApprovalReceived = true;
        Serial.print("[WS] ownerVerifyResult: "); Serial.println(ownerApprovalValid ? "APPROVED" : "DENIED");
      } else if (eventName == "getStatus") {
        emitDoorState();
      } else if (eventName == "registrationToken") {
        strncpy(registrationToken, doc[1]["token"] | "", sizeof(registrationToken)-1);
        regTokenReceived  = true;
      } else if (eventName == "deviceRegistered") {
        deviceJustRegistered = true;
      } else if (eventName == "deviceUnregistered") {
        Serial.println("[WS] deviceUnregistered event! Clearing registration flag.");
        nvsPrefs.begin("smartbox", false);
        nvsPrefs.putBool("registered", false);
        nvsPrefs.end();
        ESP.restart();
      } else if (eventName == "applyHardwareConfig") {
        String data; serializeJson(doc[1], data);
        handleApplyHardwareConfig(data);
      } else if (eventName == "requestWiFiScan") {
        handleRequestWiFiScan();
      }
    }
  }
}

// ============================================================
//  NetworkController (Part 2/2): Emitters & Handlers
//  (Consolidated from NetworkController2.ino)
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
      strncpy(offlineQueue[offlineQueueCount], trackingId.c_str(), 63);
      offlineQueue[offlineQueueCount][63] = '\0';
      offlineQueueCount++;
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
  bool parcelOnPlatform = (lastUsPlatformDist > 1.0 && lastUsPlatformDist < 18.0);
  bool parcelInDropOff  = (lastUsDropoffDist < 25.0);
  bool parcelInPickup   = (lastUsPickupDist < 25.0);

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
  strncpy(nvsWifiSSID, ssid.c_str(), sizeof(nvsWifiSSID)-1);
  strncpy(nvsWifiPassword, pass.c_str(), sizeof(nvsWifiPassword)-1);
  nvsPrefs.putString("ssid", ssid);
  nvsPrefs.putString("password", pass);
  nvsPrefs.putBool("registered", true); 
  nvsPrefs.end();

  displayMessage("WIFI SAVED", "Rebooting...");
  triggerBuzzer(2);
  
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

  // Wake up if in lockscreen
  if (currentState == LOCKSCREEN) {
    changeState(IDLE);
    delay(50);
  }

  if (mode == "drop_off") {
    strncpy(registeredDropOff, trackingId.c_str(), sizeof(registeredDropOff)-1);
    dropOffRegisterTime = millis();
    Serial.print("[REG] Drop Off ID registered via app: "); Serial.println(registeredDropOff);
    displayMessage("ID REGISTERED", ("Drop Off: " + trackingId.substring(0, 10)).c_str());
  } else if (mode == "pick_up") {
    strncpy(registeredPickup, trackingId.c_str(), sizeof(registeredPickup)-1);
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

