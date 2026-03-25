// ============================================================
//  NetworkController.ino (Part 1/2)
//  WiFi, Socket.IO setup, and Event Handlers
// ============================================================

void setupWiFi() {
  String ssid;
  String password;
  nvsPrefs.begin("smartbox", true);
  String nvsSSID = nvsPrefs.getString("ssid", "");
  String nvsPASS = nvsPrefs.getString("password", "");
  nvsPrefs.end();

  if (nvsSSID != "") {
    ssid = nvsSSID;
    password = nvsPASS;
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
    esp_task_wdt_reset();
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
        ownerSessionToken = doc[1]["token"].as<String>();
        Serial.print("[WS] ownerSessionToken received: "); Serial.println(ownerSessionToken);
      } else if (eventName == "ownerVerifyResult") {
        ownerApprovalValid    = doc[1]["approved"].as<bool>();
        ownerApprovalReceived = true;
        Serial.print("[WS] ownerVerifyResult: "); Serial.println(ownerApprovalValid ? "APPROVED" : "DENIED");
      } else if (eventName == "getStatus") {
        emitDoorState();
      } else if (eventName == "registrationToken") {
        registrationToken = doc[1]["token"].as<String>();
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
      }
      break;
    }
    case sIOtype_ERROR:
      Serial.println("[WS] Socket.IO error.");
      break;
    default:
      break;
  }
}
