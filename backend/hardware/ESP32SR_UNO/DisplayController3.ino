// ============================================================
//  DisplayController3.ino  – Dot Status Bar Updater
// ============================================================

void reinitTFT() {
  digitalWrite(TFT_RST, LOW);
  delay(100);
  digitalWrite(TFT_RST, HIGH);
  delay(150);
  tft.begin();
  tft.setRotation(3);
  showHomeScreen();
}

// Three status dots in the top-right corner of the 22px slim status bar.
// Replaces color-coded text/icons with minimal colored circles.
//   Dot 1 (x=271): WiFi     – green=connected, red=disconnected
//   Dot 2 (x=285): Security – green=all locked, gold=a door is open
//   Dot 3 (x=299): Server   – green=socket connected, red=offline
void updateDynamicIndicators() {
  tft.setFont(); // Safety
  tft.setTextSize(1);
  if (millis() - lastIndicatorUpdate < 1000) return;
  lastIndicatorUpdate = millis();

  bool wifiOK   = (WiFi.status() == WL_CONNECTED);
  bool socketOK = socketIO.isConnected();
  bool anyOpen  = (lockTopOpen || lockPickupOpen || lockReceivedOpen);

  // Clear dot region inside the "Dynamic Island" pill
  // Pill is at x=110, y=6, w=100, h=18
  tft.fillRoundRect(110, 6, 100, 18, 9, COLOR_CARD);

  // Icons centered inside the island pill
  // Icon 1: WiFi (x=120)
  uint16_t wifiColor = wifiOK ? COLOR_GREEN : COLOR_RED;
  drawWiFiSignal(118, 9, wifiColor);
  
  // Icon 2: Security (x=160)
  uint16_t doorColor = anyOpen ? COLOR_GOLD : COLOR_GREEN;
  drawSmallPadlock(160, 10, doorColor, anyOpen);
  
  // Icon 3: Server (x=195)
  tft.fillCircle(195, 14, 3, socketOK ? COLOR_GREEN : COLOR_RED);

  lastWifiState   = wifiOK;
  lastSocketState = socketOK;
  lastDoorState   = anyOpen;
}

void drawNoServerOptionsScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  
  // Focal status oval (200x76)
  _horizontalOval(160, 105, 200, 76, COLOR_RED);
  drawIconX(160, 102, COLOR_TEXT);

  _boldText("NO SERVER", 160, 182, COLOR_TEXT);
  _smallText("Device is offline", 160, 205, COLOR_GREY);

  // RETRY (blue) and OTHER (red) indicators
  _buttonIndicator(80,  232, COLOR_BLUE);
  _buttonIndicator(240, 232, COLOR_RED);
  _smallText("RETRY", 80,  218, COLOR_TEXT);
  _smallText("OTHER", 240, 218, COLOR_TEXT);
  tft.setFont();
}

void drawWiFiConfigQRScreen(const char* apSSID) {
  tft.fillScreen(COLOR_TEXT); // White Background
  // drawStatusBar(); // Hidden for full-screen setup feel
  
  // 1. Instructions at the top
  tft.setFont();
  tft.setTextSize(1);
  tft.setTextColor(COLOR_GREY);
  tft.setCursor(45, 18);
  tft.print("Connect to: ");
  tft.setTextColor(COLOR_GOLD);
  tft.print(apSSID);

  // 2. WiFi Auto-Connect QR Code (WIFI:S:<SSID>;T:nopass;;)
  // This allows the phone to connect automatically without manual selection
  String wifiQR = "WIFI:S:";
  wifiQR += apSSID;
  wifiQR += ";T:nopass;;";
  
  // Center X: (320 - 174) / 2 = 73.
  drawQRCode(73, 40, 6, wifiQR.c_str());
  
  // 3. Hint below QR
  _smallText("Scan to connect & setup WiFi", 160, 225, COLOR_BG);
  
  // 4. Manual Exit/Reboot indicator
  _buttonIndicator(300, 235, COLOR_RED);
  tft.setFont(); tft.setTextSize(1); tft.setTextColor(COLOR_BG);
  tft.setCursor(290, 222); tft.print("EXIT");
  
  tft.setFont();
}
