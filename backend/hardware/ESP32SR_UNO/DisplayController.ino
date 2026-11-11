// ============================================================
//  DisplayController.ino  – Cybernetic HUD / Sci-Fi UI
// ============================================================
#include "qrcode.h"
#include <Fonts/FreeSans9pt7b.h>
#include <Fonts/FreeSans12pt7b.h>
#include <Fonts/FreeSansBold12pt7b.h>

// ── Internal helper: draw camera-style corner brackets ─────
void _bracket(int cx, int cy, int arm, int dir, uint16_t c) {
  int t = 3; // thickness
  if (dir == 0) { tft.fillRect(cx,      cy, arm, t, c); tft.fillRect(cx, cy,      t, arm, c); } // TL
  if (dir == 1) { tft.fillRect(cx-arm+t,cy, arm, t, c); tft.fillRect(cx, cy,      t, arm, c); } // TR
  if (dir == 2) { tft.fillRect(cx,      cy, arm, t, c); tft.fillRect(cx, cy-arm+t,t, arm, c); } // BL
  if (dir == 3) { tft.fillRect(cx-arm+t,cy, arm, t, c); tft.fillRect(cx, cy-arm+t,t, arm, c); } // BR
}

void _horizontalOval(int x, int y, int w, int h, uint16_t color) {
  tft.fillRoundRect(x - w/2, y - h/2, w, h, h/2, color);
}

void _buttonIndicator(int x, int y, uint16_t color) {
  tft.fillRoundRect(x - 15, y - 6, 30, 12, 6, color);
}

// ── Internal helper: draw viewfinder brackets ──────────────
void _viewfinder(int x1, int y1, int x2, int y2, uint16_t c) {
  int arm = 20;
  _bracket(x1,    y1,    arm, 0, c); // TL
  _bracket(x2,    y1,    arm, 1, c); // TR
  _bracket(x1,    y2,    arm, 2, c); // BL
  _bracket(x2,    y2,    arm, 3, c); // BR
}

// ── Sci-Fi HUD Helpers ──────────────────────────────────────
void drawScanningAnimation(int scanY, uint16_t color) {
  // Glow effect (2-pixel thick)
  tft.fillRect(HUD_MARGIN + 5, scanY - 1, 320 - (HUD_MARGIN * 2) - 10, 3, color);
}

// ── Internal helper: Precise centering using getTextBounds ────
void _drawCenteredText(const char* s, int x, int y, uint16_t col, const GFXfont* f) {
  int16_t x1, y1;
  uint16_t w, h;
  tft.setFont(f);
  tft.setTextSize(1);
  tft.getTextBounds(s, 0, 0, &x1, &y1, &w, &h);
  // Center: Subtract bounding box center (x1+w/2, y1+h/2) from target (x,y)
  tft.setCursor(x - (x1 + w/2), y - (y1 + h/2));
  tft.setTextColor(col);
  tft.print(s);
}

int _boldText(const char* s, int x, int y, uint16_t col) {
  _drawCenteredText(s, x, y, col, &FreeSansBold12pt7b);
  return x; // Compatibility
}

int _smallText(const char* s, int x, int y, uint16_t col) {
  _drawCenteredText(s, x, y, col, &FreeSans9pt7b);
  return x; // Compatibility
}

// ── Internal helper: Vertical Oval Button with accent pill ────
void _verticalOvalButton(int x, int y, int w, int h, const char* label, uint16_t accentColor, int iconId) {
  // Main Vertical Oval (dark card)
  tft.fillRoundRect(x - w/2, y - h/2, w, h, w/2, COLOR_CARD);
  tft.drawRoundRect(x - w/2, y - h/2, w, h, w/2, COLOR_GREY);
  
  // Icon centered in upper half (offset from y center)
  int iy = y - 22;
  switch (iconId) {
    case 0: drawIconBox(x, iy, COLOR_TEXT); break;
    case 1: drawIconLock(x, iy, COLOR_TEXT, true); break;
    case 2: drawIconCheck(x, iy, COLOR_TEXT); break;
    case 3: drawIconX(x, iy - 2, COLOR_TEXT); break;
    case 4: // Plus Icon
      tft.fillRect(x - 8, iy - 1, 16, 2, COLOR_TEXT);
      tft.fillRect(x - 1, iy - 8, 2, 16, COLOR_TEXT);
      break;
  }
  
  // Text Label (Centered in lower half)
  _smallText(label, x, y + 20, COLOR_TEXT);
  
  // Smaller horizontal accent pill at the bottom
  tft.fillRoundRect(x - 22, y + 42, 44, 10, 5, accentColor);
}

// ── STATUS BAR ──────────────────────────────────────────────
void drawStatusBar() {
  tft.setFont();
  tft.setTextSize(1);
  // Dark terminal bar
  tft.fillRect(0, 0, 320, BAR_HEIGHT, COLOR_BG); 
  tft.drawFastHLine(0, BAR_HEIGHT-1, 320, COLOR_ACCENT); // Cyan separator line
  
  // Terminal Identifier
  tft.setTextColor(COLOR_ACCENT);
  tft.setCursor(HUD_MARGIN, 8);
  tft.print("SYS_CMD >> ACTIVE");
  
  lastIndicatorUpdate = 0;
  updateDynamicIndicators();
}

// ── SCANNER BACKGROUND ──────────────────────────────────────
void drawScannerBg() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Technical Markers
  tft.setTextColor(COLOR_GREY); tft.setFont();
  tft.setCursor(HUD_MARGIN+15, BAR_HEIGHT+10); tft.print("SCANNER_INIT...");
  tft.setCursor(HUD_MARGIN+15, BAR_HEIGHT+22); tft.print("MODE: LASER_READ");
  
  // Viewfinder: TL(25,35) – BR(295,195)
  _viewfinder(25, 35, 295, 195, COLOR_ACCENT);
  
  // Laser line (Neon Red)
  tft.fillRect(35, 115, 250, 2, COLOR_RED);
  
  // EXIT RED Technical Button
  _buttonIndicator(288, 222, COLOR_RED);
  tft.setFont();
}

// ── HOME SCREEN ─────────────────────────────────────────────
void showHomeScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Technical Marker: OS Name
  tft.setFont();
  tft.setTextColor(COLOR_GREY);
  tft.setCursor(HUD_MARGIN + 2, 228);
  tft.print("VER: 4.2.0-S3_ALPHA");

  // Vertical Oval Buttons (HUD Style) - cy=132
  _verticalOvalButton(80,  132, 100, 140, "DROP-OFF", COLOR_BLUE, 0); // Material Blue for entry
  _verticalOvalButton(240, 132, 100, 140, "PICK-UP",  COLOR_RED,  1);  // Material Red for security

  tft.setFont();
  tft.setTextSize(1);
  printSerialMenu();
}

// ── DEVICE UNREGISTERED ─────────────────────────────────────
void drawDeviceUnregisteredScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  // Setup Oval (200x76) - More Spacious
  _horizontalOval(160, 110, 200, 76, COLOR_CARD);
  tft.drawRoundRect(160-100, 110-38, 200, 76, 38, COLOR_GOLD);
  
  _boldText("SETUP", 160, 100, COLOR_GOLD);
  _smallText("required", 160, 125, COLOR_GREY);
  
  // BTN 1 indicator at bottom
  _buttonIndicator(160, 195, COLOR_BLUE);
  _smallText("Begin", 160, 215, COLOR_TEXT);
  tft.setFont();
}

// ── QR CODE HELPER ──────────────────────────────────────────
void drawQRCode(int x, int y, int moduleSize, const String& text) {
  QRCode qrcode;
  uint8_t qrcodeBytes[qrcode_getBufferSize(3)];
  qrcode_initText(&qrcode, qrcodeBytes, 3, ECC_MEDIUM, text.c_str());
  for (int row = 0; row < qrcode.size; row++)
    for (int col = 0; col < qrcode.size; col++) {
      uint16_t color = qrcode_getModule(&qrcode, col, row) ? COLOR_BG : COLOR_TEXT;
      tft.fillRect(x + col * moduleSize, y + row * moduleSize, moduleSize, moduleSize, color);
    }
}

// ── REGISTRATION QR SCREEN ─────────────────────────────────
void drawRegistrationQRScreen(const String& token, const String& pin) {
  tft.fillScreen(COLOR_TEXT); // White background
  // Hint at top
  _smallText("Scan QR or enter Code in app", 160, 30, COLOR_BG);
  
  // Custom QR draw with dark modules
  QRCode qrcode;
  uint8_t qrcodeBytes[qrcode_getBufferSize(3)];
  qrcode_initText(&qrcode, qrcodeBytes, 3, ECC_MEDIUM, token.c_str());
  int x = 110, y = 60, moduleSize = 4;
  for (int row = 0; row < qrcode.size; row++)
    for (int col = 0; col < qrcode.size; col++) {
      uint16_t color = qrcode_getModule(&qrcode, col, row) ? COLOR_BG : COLOR_TEXT;
      tft.fillRect(x + col * moduleSize, y + row * moduleSize, moduleSize, moduleSize, color);
    }

  // Large 6-digit PIN only
  _boldText(pin.c_str(), 160, 205, COLOR_BG);
  tft.setFont();
}

// ── OWNER VERIFYING QR SCREEN ──────────────────────────────
void drawOwnerVerifyingScreen(const String& token) {
  tft.fillScreen(COLOR_TEXT); // White background
  String pin = token.startsWith("OWN-") ? token.substring(4) : token;
  
  // Hint at top
  _smallText("Scan QR or enter Code in Owner App", 160, 30, COLOR_BG);
  
  // Custom QR draw with dark modules 
  QRCode qrcode;
  uint8_t qrcodeBytes[qrcode_getBufferSize(3)];
  qrcode_initText(&qrcode, qrcodeBytes, 3, ECC_MEDIUM, token.c_str());
  int x = 110, y = 60, moduleSize = 4;
  for (int row = 0; row < qrcode.size; row++)
    for (int col = 0; col < qrcode.size; col++) {
      uint16_t color = qrcode_getModule(&qrcode, col, row) ? COLOR_BG : COLOR_TEXT;
      tft.fillRect(x + col * moduleSize, y + row * moduleSize, moduleSize, moduleSize, color);
    }

  // Large 6-digit PIN only
  _boldText(pin.c_str(), 160, 205, COLOR_BG);

  // Added [BTN2] EXIT label for real-time cancel
  _buttonIndicator(240, 232, COLOR_RED);
  _smallText("EXIT", 240, 218, COLOR_BG);

  tft.setFont();
}

// ── DISPLAY MESSAGE (Terminal Alert Overlay) ────────────────
void displayMessage(const char* title, const char* msg) {
  bool isGood = strstr(title, "SUCCESS") || strstr(title, "VALID") ||
                strstr(title, "VERIFIED") || strstr(title, "REGISTERED") ||
                strstr(title, "UNLOCKED") || strstr(title, "Connected");
  bool isBad  = strstr(title, "ERROR") || strstr(title, "INVALID") ||
                strstr(title, "REJECTED") || strstr(title, "DENIED") ||
                strstr(title, "TIMEOUT") || strstr(title, "OFFLINE");
  uint16_t accentColor = isGood ? COLOR_GREEN : isBad ? COLOR_RED : COLOR_ACCENT;

  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  
  // Terminal Card (HUD Rect)
  int cw = 220, ch = 100;
  tft.drawRoundRect(160 - cw/2, 115 - ch/2, cw, ch, HUD_CORNER, accentColor);
  tft.fillRoundRect(160 - cw/2 + 2, 115 - ch/2 + 2, cw - 4, ch - 4, HUD_CORNER - 1, COLOR_CARD);

  if (isGood)     { drawIconCheck(160, 105, COLOR_GREEN); triggerCyberChirp(1); }
  else if (isBad) { drawIconX(160, 105, COLOR_RED);      triggerCyberChirp(2); }
  else            { drawIconBox(160, 105, COLOR_ACCENT); triggerCyberChirp(3); }

  _boldText(title, 160, 185, COLOR_TEXT);
  _smallText(msg,  160, 215, COLOR_GREY);
  tft.setFont();
}

// ── TIMEOUT SCREEN ──────────────────────────────────────────
void drawTimeoutScreen(const char* title, const char* subtitle) {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  // Alert oval (200x76)
  _horizontalOval(160, 105, 200, 76, COLOR_RED);
  drawIconX(160, 102, COLOR_TEXT);

  _boldText(title,    160, 180, COLOR_RED);
  _smallText(subtitle, 160, 202, COLOR_GREY);

  // RETRY and EXIT indicators
  _buttonIndicator(80,  232, COLOR_BLUE);
  _buttonIndicator(240, 232, COLOR_RED);
  _smallText("RETRY", 80,  218, COLOR_TEXT);
  _smallText("EXIT",  240, 218, COLOR_TEXT);
  tft.setFont();
}

// ── ICON HELPERS ────────────────────────────────────────────
void drawButtonLabel(int x, int y, uint16_t color, const char* label) {
  _buttonIndicator(x, y + 3, color);
}

void drawIconLock(int x, int y, uint16_t color, bool open) {
  if (open) {
    tft.drawCircle(x, y - 5, 10, color);
    tft.fillRect(x + 5, y - 5, 10, 10, COLOR_BG);
  } else {
    tft.drawCircle(x, y, 10, color);
  }
  tft.fillRoundRect(x - 12, y + 2, 24, 18, 3, color);
  tft.fillCircle(x, y + 11, 3, COLOR_BG);
}

void drawSmallPadlock(int x, int y, uint16_t color, bool open) {
  if (open) { tft.drawCircle(x, y - 3, 5, color); tft.fillRect(x + 3, y - 6, 4, 8, COLOR_CARD); }
  else       { tft.drawCircle(x, y - 2, 5, color); }
  tft.fillRoundRect(x - 6, y + 2, 12, 10, 2, color);
  tft.fillCircle(x, y + 6, 2, COLOR_BG);
}

void drawWiFiSignal(int x, int y, uint16_t color) {
  for (int i = 0; i < 4; i++)
    tft.fillRect(x + (i * 4), y + (12 - (i * 3)), 3, (i * 3) + 3, color);
}

void drawIconBox(int x, int y, uint16_t color) {
  tft.drawRect(x - 15, y - 10, 30, 25, color);
  tft.drawRect(x - 16, y - 11, 32, 27, color);
  tft.drawLine(x - 15, y - 10, x + 15, y + 15, color);
  tft.drawLine(x - 15, y + 15, x + 15, y - 10, color);
}

void drawIconCheck(int x, int y, uint16_t color) {
  tft.drawLine(x - 20, y,      x - 5,  y + 15, color);
  tft.drawLine(x - 21, y,      x - 6,  y + 15, color);
  tft.drawLine(x - 5,  y + 15, x + 25, y - 20, color);
  tft.drawLine(x - 6,  y + 15, x + 24, y - 20, color);
}

void drawIconX(int x, int y, uint16_t color) {
  tft.drawLine(x - 20, y - 20, x + 20, y + 20, color);
  tft.drawLine(x - 21, y - 20, x + 19, y + 20, color);
  tft.drawLine(x + 20, y - 20, x - 20, y + 20, color);
  tft.drawLine(x + 21, y - 20, x - 19, y + 20, color);
}

// ── LOCKSCREEN ANIMATIONS ────────────────────────────────────
void drawRobotEyeLockscreen(int x, int y, int offsetX, bool blink, RobotEmotion emotion) {
  // Center is x, but we shift by offsetX
  int lx = x - 45 + offsetX;
  int rx = x + 45 + offsetX;
  
  if (blink) {
    // Two horizontal rounded lines for eyes (blinking)
    tft.fillRoundRect(lx - 25, y - 5, 50, 8, 4, COLOR_ACCENT);
    tft.fillRoundRect(rx - 25, y - 5, 50, 8, 4, COLOR_ACCENT);
  } else {
    if (emotion == HAPPY) {
      // Archer/Happy eyes (semi-circles)
      tft.fillCircle(lx, y-5, 25, COLOR_ACCENT);
      tft.fillRect(lx - 25, y, 50, 25, COLOR_BG);
      tft.fillCircle(rx, y-5, 25, COLOR_ACCENT);
      tft.fillRect(rx - 25, y, 50, 25, COLOR_BG);
    } else if (emotion == WINK) {
      // Left eye blink, right eye neutral
      tft.fillRoundRect(lx - 25, y - 5, 50, 8, 4, COLOR_ACCENT);
      tft.fillRoundRect(rx - 25, y - 25, 50, 40, 20, COLOR_ACCENT);
    } else if (emotion == SQUINT) {
      tft.fillRoundRect(lx - 25, y - 12, 50, 24, 12, COLOR_ACCENT);
      tft.fillRoundRect(rx - 25, y - 12, 50, 24, 12, COLOR_ACCENT);
    } else {
      // NEUTRAL: Two rounded "pill" style eyes
      tft.fillRoundRect(lx - 25, y - 25, 50, 40, 20, COLOR_ACCENT);
      tft.fillRoundRect(rx - 25, y - 25, 50, 40, 20, COLOR_ACCENT);
    }
  }
  
  // Cute mouth
  if (emotion == HAPPY) {
     tft.fillCircle(x, y + 25, 15, COLOR_ACCENT);
     tft.fillRect(x - 15, y + 15, 30, 15, COLOR_BG);
  } else {
     tft.fillRoundRect(x - 15, y + 25, 30, 12, 6, COLOR_ACCENT);
  }
}

void drawLockscreenText(const char* line1, const char* line2) {
  _boldText(line1, 160, 195, COLOR_TEXT);
  _smallText(line2, 160, 218, COLOR_GREY);
}

// ============================================================
//  Consolidated Sub-menu & Auxiliary Display Logic
//  (From DisplayController2.ino & DisplayController3.ino)
// ============================================================

static void _twoOvalScreen(
  const char* contextLabel,
  uint16_t leftColor,  int leftIcon,  const char* leftLabel,
  uint16_t rightColor, int rightIcon, const char* rightLabel)
{
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  if (strlen(contextLabel) > 0) {
    _smallText(contextLabel, 160, 48, COLOR_GREY);
  }

  _verticalOvalButton(80,  138, 100, 140, leftLabel,  leftColor,  leftIcon);
  _verticalOvalButton(240, 138, 100, 140, rightLabel, rightColor, rightIcon);

  tft.setFont();
}

void drawPickupSelectScreen() {
  _twoOvalScreen("Select Mode", COLOR_BLUE, 1, "OWNER", COLOR_RED, 0, "RIDER");
}

void drawOwnerModeScreen() {
  _twoOvalScreen("Owner Pick Up", COLOR_BLUE, 0, "SINGLE", COLOR_RED, 0, "MULTI");
}

void drawAddMorePrompt() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  String countStr = "Parcel #" + String(scannedCount) + " registered";
  _smallText(countStr.c_str(), 160, 48, COLOR_GREEN);
  _verticalOvalButton(80,  138, 100, 140, "ADD MORE", COLOR_BLUE, 0);
  _verticalOvalButton(240, 138, 100, 140, "DONE",     COLOR_GREEN, 2);
  tft.setFont();
}

void drawRiderScanIdScreen() {
  drawScannerBg();
  _boldText("SCAN RIDER ID", 160, 75, COLOR_GREY);
}

void drawRiderScanParcelScreen() {
  drawScannerBg();
  String prompt = "Scan Parcel #" + String(scannedCount + 1);
  _boldText(prompt.c_str(), 160, 75, COLOR_GREY);
}

void drawRiderPickupMorePrompt() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  String countStr = "#" + String(scannedCount) + " marked done";
  _smallText(countStr.c_str(), 160, 48, COLOR_GREEN);
  _verticalOvalButton(80,  138, 100, 140, "MORE", COLOR_BLUE, 4);
  _verticalOvalButton(240, 138, 100, 140, "DONE", COLOR_GREEN, 2);
  tft.setFont();
}

void drawScanFailedPrompt() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  _horizontalOval(160, 105, 200, 76, COLOR_RED);
  drawIconX(160, 102, COLOR_TEXT);
  _boldText("SCAN FAILED", 160, 182, COLOR_TEXT);
  _smallText("3 attempts exceeded", 160, 205, COLOR_GREY);
  _buttonIndicator(80,  232, COLOR_BLUE);
  _buttonIndicator(240, 232, COLOR_RED);
  _smallText("RETRY", 80,  218, COLOR_TEXT);
  _smallText("EXIT",  240, 218, COLOR_TEXT);
  tft.setFont();
}

void drawSettingsMenu() {
  _twoOvalScreen("System Settings", COLOR_BLUE, 4, "REGISTER", COLOR_RED, 3, "BACK");
}

void reinitTFT() {
  digitalWrite(TFT_RST, LOW);
  delay(100);
  digitalWrite(TFT_RST, HIGH);
  delay(150);
  tft.begin();
  tft.setRotation(3);
  showHomeScreen();
}

void updateDynamicIndicators() {
  tft.setFont();
  tft.setTextSize(1);
  if (millis() - lastIndicatorUpdate < 1000) return;
  lastIndicatorUpdate = millis();

  bool wifiOK   = (WiFi.status() == WL_CONNECTED);
  bool socketOK = socketIO.isConnected();
  bool anyOpen  = (lockTopOpen || lockPickupOpen || lockReceivedOpen);

  tft.fillRoundRect(110, 6, 100, 18, 9, COLOR_CARD);
  uint16_t wifiColor = wifiOK ? COLOR_GREEN : COLOR_RED;
  drawWiFiSignal(118, 9, wifiColor);
  uint16_t doorColor = anyOpen ? COLOR_GOLD : COLOR_GREEN;
  drawSmallPadlock(160, 10, doorColor, anyOpen);
  tft.fillCircle(195, 14, 3, socketOK ? COLOR_GREEN : COLOR_RED);

  lastWifiState   = wifiOK;
  lastSocketState = socketOK;
  lastDoorState   = anyOpen;
}

void drawNoServerOptionsScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  _horizontalOval(160, 105, 200, 76, COLOR_RED);
  drawIconX(160, 102, COLOR_TEXT);
  _boldText("NO SERVER", 160, 182, COLOR_TEXT);
  _smallText("Device is offline", 160, 205, COLOR_GREY);
  _buttonIndicator(80,  232, COLOR_BLUE);
  _buttonIndicator(240, 232, COLOR_RED);
  _smallText("RETRY", 80,  218, COLOR_TEXT);
  _smallText("OTHER", 240, 218, COLOR_TEXT);
  tft.setFont();
}

void drawWiFiConfigQRScreen(const char* apSSID) {
  tft.fillScreen(COLOR_TEXT);
  tft.setFont();
  tft.setTextSize(1);
  tft.setTextColor(COLOR_GREY);
  tft.setCursor(45, 18);
  tft.print("Connect to: ");
  tft.setTextColor(COLOR_GOLD);
  tft.print(apSSID);
  String wifiQR = "WIFI:S:";
  wifiQR += apSSID;
  wifiQR += ";T:nopass;;";
  drawQRCode(73, 40, 6, wifiQR.c_str());
  _smallText("Scan to connect & setup WiFi", 160, 225, COLOR_BG);
  _buttonIndicator(300, 235, COLOR_RED);
  tft.setFont(); tft.setTextSize(1); tft.setTextColor(COLOR_BG);
  tft.setCursor(290, 222); tft.print("EXIT");
  tft.setFont();
}

