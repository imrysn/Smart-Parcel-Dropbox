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

#include <mbedtls/md.h>
static bool deviceAuthenticated = false;

void setupSocketIO() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WS] Skipping Socket.IO — no WiFi.");
    return;
  }
  if (strlen(SPD_DEVICE_KEY) < 32) {
    Serial.println("[WS] Set a device credential before enabling server access.");
    return;
  }

  Serial.print("[WS] Connecting to server: ");
  Serial.print(SERVER_HOST); Serial.print(":"); Serial.println(SERVER_PORT);

  socketIO.onEvent(socketIOEvent);
  socketIO.beginSSL(SERVER_HOST, SERVER_PORT, SERVER_PATH);
  socketIO.setReconnectInterval(5000);

  Serial.println("[WS] Socket.IO initiated — connecting in background...");
}

void authenticateDevice(const String& nonce) {
  if (nonce.length() != 48) return;
  String deviceId = WiFi.macAddress();
  deviceId.toUpperCase();
  const String message = deviceId + ":" + nonce;
  unsigned char digest[32];
  const mbedtls_md_info_t* sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (!sha256 || mbedtls_md_hmac(sha256,
      reinterpret_cast<const unsigned char*>(SPD_DEVICE_KEY), strlen(SPD_DEVICE_KEY),
      reinterpret_cast<const unsigned char*>(message.c_str()), message.length(), digest) != 0) return;
  char proof[65];
  for (int i = 0; i < 32; i++) snprintf(proof + i * 2, 3, "%02x", digest[i]);
  StaticJsonDocument<256> reply;
  JsonArray arr = reply.to<JsonArray>();
  arr.add("authenticateDevice");
  JsonObject data = arr.createNestedObject();
  data["deviceId"] = deviceId;
  data["proof"] = proof;
  String output;
  serializeJson(reply, output);
  socketIO.send(sIOtype_EVENT, output);
}

void emitDoorCommandResult(const String& requestId, bool ok) {
  if (requestId.isEmpty()) return;
  StaticJsonDocument<384> reply;
  JsonArray arr = reply.to<JsonArray>();
  arr.add("doorCommandResult");
  JsonObject result = arr.createNestedObject();
  result["requestId"] = requestId;
  result["ok"] = ok;
  JsonObject state = result.createNestedObject("doorState");
  state["parcelDoorOpen"] = lockTopOpen;
  state["pickupDoorOpen"] = lockPickupOpen;
  state["receivedDoorOpen"] = lockReceivedOpen;
  String output;
  serializeJson(reply, output);
  socketIO.send(sIOtype_EVENT, output);
}

void sendDeviceHeartbeat(bool immediate) {
  static uint64_t lastHeartbeatMs = 0;
  if (!deviceAuthenticated || WiFi.status() != WL_CONNECTED) return;

  const uint64_t uptimeMs = esp_timer_get_time() / 1000;
  if (!immediate && uptimeMs - lastHeartbeatMs < 30000) return;
  lastHeartbeatMs = uptimeMs;

  StaticJsonDocument<256> doc;
  JsonArray message = doc.to<JsonArray>();
  message.add("deviceHeartbeat");
  JsonObject data = message.createNestedObject();
  data["firmwareVersion"] = SPD_FIRMWARE_VERSION;
  data["wifiRssi"] = WiFi.RSSI();
  data["uptimeSeconds"] = static_cast<uint32_t>(uptimeMs / 1000);

  String output;
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output);
}

void socketIOEvent(socketIOmessageType_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case sIOtype_CONNECT:
      deviceAuthenticated = false;
      Serial.println("[WS] Socket.IO connected; waiting for device authentication.");
      break;

    case sIOtype_DISCONNECT:
      deviceAuthenticated = false;
      Serial.println("[WS] Socket.IO disconnected.");
      break;

    case sIOtype_EVENT: {
      StaticJsonDocument<1024> doc;
      DeserializationError err = deserializeJson(doc, payload, length);
      if (err) {
        Serial.print("[WS] JSON parse error: "); Serial.println(err.c_str());
        break;
      }

      String eventName = doc[0].as<String>();
      if (DEBUG_WS) { Serial.print("[WS] Event: "); Serial.println(eventName); }
      if (!deviceAuthenticated && eventName != "deviceChallenge" && eventName != "deviceAuthenticated") break;

      if (eventName == "deviceChallenge") {
        authenticateDevice(doc[1]["nonce"].as<String>());
      } else if (eventName == "deviceAuthenticated") {
        deviceAuthenticated = true;
        Serial.println("[WS] Device authenticated.");
        emitDoorState();
        sendDeviceHeartbeat(true);
      } else if (eventName == "scanResult") {
        String data; serializeJson(doc[1], data);
        handleScanResult(data);
      } else if (eventName == "riderVerifyResult") {
        String data; serializeJson(doc[1], data);
        handleRiderVerifyResult(data);
      } else if (eventName == "registerTracking") {
        String data; serializeJson(doc[1], data);
        handleRegisterTracking(data);
      } else if (eventName == "controlDoor") {
        const String requestId = doc[1]["requestId"].as<String>();
        const String action = doc[1]["action"].as<String>();
        const String door = doc[1]["type"].as<String>();
        const bool valid = !requestId.isEmpty() && (action == "open" || action == "close") &&
          (door == "top" || door == "pickup" || door == "received");
        if (!valid) {
          emitDoorCommandResult(requestId, false);
          break;
        }
        String data; serializeJson(doc[1], data);
        handleControlDoor(data);
        emitDoorCommandResult(requestId, true);
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

// (Unused owner emitters removed; owner control managed by mobile app)

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
  bool parcelInDropOff  = (dropoffBaselineDist < 900.0 && lastUsDropoffDist < 900.0) 
                          ? ((dropoffBaselineDist - lastUsDropoffDist) >= 4.0) 
                          : (lastUsDropoffDist < 30.0);
  bool parcelInPickup   = false; // Pickup US removed - tracked logically via server status

  StaticJsonDocument<256> doc;
  JsonArray arr = doc.to<JsonArray>();
  arr.add("doorStateUpdate");
  JsonObject data = arr.createNestedObject();
  data["parcelDoorOpen"]    = lockTopOpen;       
  data["pickupDoorOpen"]    = lockPickupOpen;    
  data["receivedDoorOpen"]  = lockReceivedOpen;  
  data["parcelDetected"]    = parcelInDropOff;  
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
  DynamicJsonDocument doc(2048);
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

  String output;
  serializeJson(doc, output);
  socketIO.send(sIOtype_EVENT, output.c_str());
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
  String mode = doc["mode"].as<String>();
  Serial.print("[WS] scanResult → valid: "); Serial.print(valid ? "YES" : "NO");
  Serial.print(" | mode: "); Serial.println(mode);

  if (valid) {
    // true = drop_off (into Bin A), false = pick_up / pickup (into Bin B)
    isReceivingMode = (mode == "drop_off");
  }

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
  } else if (mode == "pick_up" || mode == "pickup") {
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

