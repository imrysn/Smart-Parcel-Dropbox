// ============================================================
//  DisplayController.ino  – Smartwatch / WearOS Style UI
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
  // Slimmer, cleaner bar with margin (24px height)
  tft.fillRect(0, 0, 320, 26, COLOR_BG); 
  
  // Dynamic Island pill shifted down for top margin (y=6, h=18)
  tft.fillRoundRect(110, 6, 100, 18, 9, COLOR_CARD);
  
  lastIndicatorUpdate = 0;
  updateDynamicIndicators();
}

// ── SCANNER BACKGROUND (shared by drop-off + rider IDscreens) ─
void drawScannerBg() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  // Viewfinder: TL(25,35) – BR(295,195)
  _viewfinder(25, 35, 295, 195, COLOR_TEXT);
  // Red laser line at vertical center of viewfinder
  tft.fillRect(35, 115, 250, 2, COLOR_RED);
  // EXIT red indicator
  _buttonIndicator(288, 222, COLOR_RED);
  tft.setFont();
}

// ── HOME SCREEN ─────────────────────────────────────────────
void showHomeScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Vertical Oval Buttons shifted down for balance (cy=132)
  _verticalOvalButton(80,  132, 100, 140, "DROP OFF", COLOR_BLUE, 0);
  _verticalOvalButton(240, 132, 100, 140, "PICK UP",  COLOR_RED,  1);

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
  tft.setFont();
}

// ── DISPLAY MESSAGE (status modal) ──────────────────────────
void displayMessage(const char* title, const char* msg) {
  bool isGood = strstr(title, "SUCCESS") || strstr(title, "VALID") ||
                strstr(title, "VERIFIED") || strstr(title, "REGISTERED") ||
                strstr(title, "UNLOCKED") || strstr(title, "Connected");
  bool isBad  = strstr(title, "ERROR") || strstr(title, "INVALID") ||
                strstr(title, "REJECTED") || strstr(title, "DENIED") ||
                strstr(title, "TIMEOUT") || strstr(title, "OFFLINE");
  uint16_t accentColor = isGood ? COLOR_GREEN : isBad ? COLOR_RED : COLOR_BLUE;

  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  
  // Focal status oval (200x76)
  _horizontalOval(160, 105, 200, 76, accentColor);
  
  if (isGood)      drawIconCheck(160, 102, COLOR_TEXT);
  else if (isBad)  drawIconX(160, 102, COLOR_TEXT);
  else             drawIconBox(160, 102, COLOR_TEXT);

  _boldText(title, 160, 182, COLOR_TEXT);
  _smallText(msg,  160, 208, COLOR_GREY);
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
