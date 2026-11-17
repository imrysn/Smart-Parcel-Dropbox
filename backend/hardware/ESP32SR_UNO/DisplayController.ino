// ============================================================
//  DisplayController.ino  – Cybernetic HUD / Sci-Fi UI
// ============================================================
#include "qrcode.h"
#include "AppIcons.h"
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
  if (!s || s[0] == '\0') return;
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

// ── STATUS BAR (Tesla Sleek Centered Telemetry) ─────────────
void drawStatusBar() {
  tft.fillRect(0, 0, 320, BAR_HEIGHT, COLOR_BG);
  tft.drawFastHLine(0, BAR_HEIGHT - 1, 320, 0x18E3); // Sleek subtle divider line

  bool wifiOK   = (WiFi.status() == WL_CONNECTED);
  bool socketOK = socketIO.isConnected();
  bool anyOpen  = (lockTopOpen || lockPickupOpen || lockReceivedOpen);

  // 1. Wi-Fi Signal Bars (Centered left at x=130..142)
  uint16_t wifiColor = wifiOK ? COLOR_GREEN : COLOR_RED;
  for (int i = 0; i < 4; i++) {
    int barH = 4 + (i * 3);
    tft.fillRect(130 + (i * 4), 20 - barH, 2, barH, wifiColor);
  }

  // 2. Cloud Backend Icon (Centered at x=152, y=8) - Crisp Bitmap Icon
  uint16_t cloudColor = (!wifiOK) ? COLOR_RED : (socketOK ? COLOR_GREEN : COLOR_RED);
  tft.drawBitmap(152, 8, icon_cloud_16x12, 16, 12, cloudColor);

  // 3. Padlock Status (Centered right at x=178, y=8) - Crisp Bitmap Icon
  uint16_t doorColor = anyOpen ? COLOR_GOLD : 0x64748b;
  if (anyOpen) {
    tft.drawBitmap(178, 8, icon_lock_mini_open_10x12, 10, 12, doorColor);
  } else {
    tft.drawBitmap(178, 8, icon_lock_mini_closed_10x12, 10, 12, doorColor);
  }

  lastIndicatorUpdate = millis();
  lastWifiState       = wifiOK;
  lastSocketState     = socketOK;
  lastDoorState       = anyOpen;
}

// ── SCANNER BACKGROUND (Tesla Sleek Static, Flicker-Free) ────
void drawScannerBg() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Headline
  _smallText("Please scan the Parcel's QR below.", 160, 42, COLOR_TEXT);

  // Borderless QR code visual centered at (160, 92)
  const int qx = 134, qy = 66, qs = 52;
  tft.fillRoundRect(qx, qy, qs, qs, 4, COLOR_TEXT);

  // 3 Finder patterns
  // TL
  tft.fillRect(qx + 4, qy + 4, 12, 12, COLOR_BG);
  tft.fillRect(qx + 6, qy + 6, 8, 8, COLOR_TEXT);
  tft.fillRect(qx + 8, qy + 8, 4, 4, COLOR_BG);
  // TR
  tft.fillRect(qx + 36, qy + 4, 12, 12, COLOR_BG);
  tft.fillRect(qx + 38, qy + 6, 8, 8, COLOR_TEXT);
  tft.fillRect(qx + 40, qy + 8, 4, 4, COLOR_BG);
  // BL
  tft.fillRect(qx + 4, qy + 36, 12, 12, COLOR_BG);
  tft.fillRect(qx + 6, qy + 38, 8, 8, COLOR_TEXT);
  tft.fillRect(qx + 8, qy + 40, 4, 4, COLOR_BG);

  // Center & random modules
  tft.fillRect(qx + 20, qy + 8, 12, 3, COLOR_BG);
  tft.fillRect(qx + 8, qy + 20, 3, 12, COLOR_BG);
  tft.fillRect(qx + 22, qy + 18, 8, 8, COLOR_BG);
  tft.fillRect(qx + 20, qy + 32, 14, 4, COLOR_BG);
  tft.fillRect(qx + 36, qy + 22, 4, 10, COLOR_BG);
  tft.fillRect(qx + 36, qy + 36, 10, 4, COLOR_BG);

  // Static bold downward chevron pointing to physical scanner window below bezel (zero animation = flicker-free!)
  int cx = 160, cy = 142;
  for (int w = 0; w < 3; w++) {
    tft.drawLine(cx - 14, cy - 6 + w, cx, cy + 6 + w, COLOR_ACCENT);
    tft.drawLine(cx, cy + 6 + w, cx + 14, cy - 6 + w, COLOR_ACCENT);
  }

  // Footer: Press BTN 2 (Red dot) to exit.
  _smallText("Press", 136, 218, COLOR_GREY);
  tft.fillCircle(158, 218, 4, COLOR_RED); // BTN 2 Red Dot
  _smallText("to exit.", 184, 218, COLOR_GREY);

  tft.setFont();
}

// ── HOME SCREEN (Tesla Sleek Dual Vertical Cards) ───────────
void showHomeScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Left Card: DROP-OFF (Cyan Accent)
  tft.fillRoundRect(20, 36, 134, 188, 16, COLOR_CARD);
  tft.drawRoundRect(20, 36, 134, 188, 16, COLOR_ACCENT);

  // Drop-Off Icon: Crisp 32x32 Parcel Box Bitmap (Centered at 87, 80)
  tft.drawBitmap(71, 64, icon_parcel_32x32, 32, 32, COLOR_ACCENT);

  // Downward chevron
  tft.drawLine(81, 106, 87, 112, COLOR_ACCENT);
  tft.drawLine(87, 112, 93, 106, COLOR_ACCENT);
  tft.drawLine(81, 107, 87, 113, COLOR_ACCENT);
  tft.drawLine(87, 113, 93, 107, COLOR_ACCENT);

  // Text
  _boldText("DROP-OFF", 87, 142, COLOR_ACCENT);
  _smallText("Touch / BTN 1", 87, 172, COLOR_TEXT);

  // BTN 1 Blue Dot Indicator
  tft.fillCircle(87, 202, 5, COLOR_ACCENT); // BTN 1 Blue Dot

  // Right Card: PICK-UP (Crimson Accent)
  tft.fillRoundRect(166, 36, 134, 188, 16, COLOR_CARD);
  tft.drawRoundRect(166, 36, 134, 188, 16, COLOR_RED);

  // Pick-Up Icon: Crisp 32x32 Padlock Bitmap (Centered at 233, 80)
  tft.drawBitmap(217, 64, icon_lock_closed_32x32, 32, 32, COLOR_RED);

  // Text
  _boldText("PICK-UP", 233, 142, COLOR_RED);
  _smallText("Touch / BTN 2", 233, 172, COLOR_TEXT);

  // BTN 2 Red Dot Indicator
  tft.fillCircle(233, 202, 5, COLOR_RED); // BTN 2 Red Dot

  tft.setFont();
  printSerialMenu();
}

// ── REMOTE MOBILE APP CONTROLS (UNLOCKED / LOCKED) ──────────
void drawUnlockedScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Crisp Open Padlock Bitmap (Centered at 160, 92)
  tft.drawBitmap(144, 76, icon_lock_open_32x32, 32, 32, COLOR_GOLD);

  // Bold headline ONLY (pure & clean, no card box, no subtitle)
  _boldText("UNLOCKED", 160, 145, COLOR_TEXT);
  tft.setFont();
}

void drawLockedScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Crisp Closed Padlock Bitmap (Centered at 160, 92)
  tft.drawBitmap(144, 76, icon_lock_closed_32x32, 32, 32, COLOR_GREEN);

  // Bold headline ONLY
  _boldText("LOCKED", 160, 145, COLOR_TEXT);
  tft.setFont();
}

// ── PHYSICAL ACTION / INSTRUCTION SCREENS ───────────────────
void drawPlaceDropScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Crisp 32x32 Parcel box bitmap (Centered at 160, 76)
  tft.drawBitmap(144, 60, icon_parcel_32x32, 32, 32, COLOR_ACCENT);

  // Downward drop chevron
  for (int w = 0; w < 3; w++) {
    tft.drawLine(148, 104 + w, 160, 114 + w, COLOR_ACCENT);
    tft.drawLine(160, 114 + w, 172, 104 + w, COLOR_ACCENT);
  }

  // Bin opening frame
  tft.drawFastVLine(124, 126, 10, COLOR_GREY);
  tft.drawFastHLine(124, 136, 72, COLOR_GREY);
  tft.drawFastVLine(196, 126, 10, COLOR_GREY);

  // Bold headline ONLY
  _boldText("Place & Drop the parcel inside", 160, 170, COLOR_TEXT);
  tft.setFont();
}

void drawPleaseCloseDoorScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Dropbox lid closure guide graphic
  tft.drawRoundRect(134, 100, 52, 26, 4, COLOR_CARD);

  // Angled open lid in gold
  for (int w = 0; w < 3; w++) {
    tft.drawLine(134, 100 + w, 176, 72 + w, COLOR_GOLD);
  }

  // Push-down guide arrow
  for (int w = 0; w < 2; w++) {
    tft.drawFastVLine(174 + w, 78, 16, COLOR_GOLD);
    tft.drawLine(169, 89 + w, 174, 94 + w, COLOR_GOLD);
    tft.drawLine(174, 94 + w, 179, 89 + w, COLOR_GOLD);
  }

  // Bold headline ONLY
  _boldText("Please close the door", 160, 160, COLOR_TEXT);
  tft.setFont();
}

// ── UNIFIED MODAL CARD TEMPLATE (230x108) ───────────────────
void displayModalCard(uint16_t borderColor, bool isCheck, const char* title, const char* subtitle) {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // 230x108 Card
  const int cw = 230, ch = 108;
  const int cx = 160 - cw/2, cy = 54;
  tft.fillRoundRect(cx + 2, cy + 2, cw - 4, ch - 4, 14, COLOR_CARD);
  tft.drawRoundRect(cx, cy, cw, ch, 16, borderColor);

  // Circular Badge
  tft.fillCircle(160, 84, 18, borderColor);
  if (isCheck) {
    drawIconCheck(160, 84, COLOR_TEXT);
  } else {
    drawIconX(160, 84, COLOR_TEXT);
  }

  // Headline
  _boldText(title, 160, 122, borderColor);

  // Subtitle
  if (subtitle && strlen(subtitle) > 0) {
    _smallText(subtitle, 160, 142, COLOR_GREY);
  }
  tft.setFont();
}

void drawParcelDeliveredScreen() {
  displayModalCard(COLOR_GREEN, true, "Parcel Delivered", "Detected by Ultrasonic Sensor");
}

void drawThankYouScreen() {
  displayModalCard(COLOR_ACCENT, true, "Thank you.", "Transaction Logged");
}

// ── DISPLAY MESSAGE (Terminal Alert Overlay Router) ─────────
void displayMessage(const char* title, const char* msg) {
  if (strcmp(title, "UNLOCKED") == 0) {
    drawUnlockedScreen();
    triggerCyberChirp(1);
    return;
  }
  if (strcmp(title, "LOCKED") == 0) {
    drawLockedScreen();
    triggerCyberChirp(1);
    return;
  }
  if (strstr(title, "DELIVERED") || strstr(title, "Parcel Delivered")) {
    drawParcelDeliveredScreen();
    triggerCyberChirp(1);
    return;
  }
  if (strstr(title, "THANK") || strstr(title, "Thank you")) {
    drawThankYouScreen();
    triggerCyberChirp(1);
    return;
  }

  bool isGood = strstr(title, "SUCCESS") || strstr(title, "VALID") ||
                strstr(title, "VERIFIED") || strstr(title, "REGISTERED") ||
                strstr(title, "Connected") || strstr(title, "Paired");
  bool isBad  = strstr(title, "ERROR") || strstr(title, "INVALID") ||
                strstr(title, "REJECTED") || strstr(title, "DENIED") ||
                strstr(title, "TIMEOUT") || strstr(title, "OFFLINE") ||
                strstr(title, "FAILED") || strstr(title, "NO PARCEL");
  uint16_t accentColor = isGood ? COLOR_GREEN : isBad ? COLOR_RED : COLOR_ACCENT;

  displayModalCard(accentColor, isGood, title, msg);
  if (isGood)     triggerCyberChirp(1);
  else if (isBad) triggerCyberChirp(2);
  else            triggerCyberChirp(3);
}

// ── GEAR ICON & SETUP WORKFLOW SCREENS ──────────────────────
void drawIconGear(int cx, int cy, uint16_t color, uint16_t bgColor) {
  // Crisp 32x32 Mechanical Gear Bitmap Icon
  tft.drawBitmap(cx - 16, cy - 16, icon_gear_32x32, 32, 32, color);
}

void drawDeviceUnregisteredScreen() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Precision 32x32 Mechanical Gear Bitmap Icon (Centered at 160, 76)
  drawIconGear(160, 76, COLOR_GOLD, COLOR_BG);

  // Headline & Subtitle
  _boldText("SETUP REQUIRED", 160, 120, COLOR_GOLD);
  _smallText("Pair this box with Mobile App", 160, 142, COLOR_GREY);

  // Sleek Begin Setup Button
  // Glowing Begin Setup Button
  tft.fillRoundRect(95, 168, 130, 28, 14, COLOR_ACCENT);
  _smallText("Begin Setup", 160, 182, COLOR_BG);
  _smallText("Press BTN 1", 144, 214, COLOR_GREY);
  tft.fillCircle(174, 214, 4, COLOR_ACCENT); // BTN 1 Blue Dot
  _smallText("to start", 202, 214, COLOR_GREY);
  tft.setFont();
}

// ── QR CODE HELPER ──────────────────────────────────────────
void drawQRCode(int x, int y, int moduleSize, const String& text) {
  QRCode qrcode;
  uint8_t qrcodeBytes[256]; // Static fixed buffer safe for up to Version 6 (no VLA compiler issues)
  // Try compact Version 3 first, then fallback to Version 4 if text is longer
  int8_t res = qrcode_initText(&qrcode, qrcodeBytes, 3, ECC_LOW, text.c_str());
  if (res < 0) {
    res = qrcode_initText(&qrcode, qrcodeBytes, 4, ECC_LOW, text.c_str());
  }
  if (res < 0) {
    Serial.println("[QR] ERROR: Payload exceeds QR buffer size!");
    return;
  }
  for (int row = 0; row < qrcode.size; row++)
    for (int col = 0; col < qrcode.size; col++) {
      uint16_t color = qrcode_getModule(&qrcode, col, row) ? COLOR_BG : COLOR_TEXT;
      tft.fillRect(x + col * moduleSize, y + row * moduleSize, moduleSize, moduleSize, color);
    }
}

void drawBleWifiSetupScreen(const String& qrPayload) {
  tft.fillScreen(COLOR_TEXT); // High-contrast White Background

  _boldText("Bluetooth Wi-Fi Setup", 160, 22, COLOR_BG);
  _smallText("Scan in Parcel App to configure Wi-Fi", 160, 39, COLOR_GREY);

  // Large QR code (moduleSize 3 -> 87x87 at x=116, y=54) — unobstructed for camera scanning
  drawQRCode(116, 54, 3, qrPayload);

  // Status / Expiry Pill with crisp Bluetooth bitmap icon
  tft.fillRoundRect(85, 156, 150, 24, 12, 0xE71C);
  tft.drawRoundRect(85, 156, 150, 24, 12, 0xCE79);
  tft.drawBitmap(95, 158, icon_bluetooth_16x20, 16, 20, COLOR_BLUE);
  _smallText("BLE ACTIVE", 168, 168, COLOR_BLUE);

  // Cancel Footer: Press BTN 2 (Red dot) to cancel
  _smallText("Press", 136, 212, COLOR_GREY);
  tft.fillCircle(158, 212, 4, COLOR_RED); // BTN 2 Red Dot
  _smallText("to cancel", 188, 212, COLOR_GREY);
  tft.setFont();
}

void drawRegistrationQRScreen(const String& token, const String& pin) {
  tft.fillScreen(COLOR_TEXT); // High-contrast White Background

  _boldText("Scan QR with Parcel App", 160, 22, COLOR_BG);
  _smallText("Or enter the 6-digit Code below", 160, 38, COLOR_GREY);

  // Large QR code (moduleSize 3 -> 87x87 at x=116, y=54)
  drawQRCode(116, 54, 3, token);

  // Large 6-digit PIN
  String pinStr = "CODE: " + pin;
  _boldText(pinStr.c_str(), 160, 168, COLOR_BG);

  // Expiry & cancel pill with BTN 2 Red Dot
  tft.fillRoundRect(45, 192, 230, 24, 12, 0xF7BE);
  tft.drawRoundRect(45, 192, 230, 24, 12, 0xCE79);
  _smallText("Expires in 60s  |  BTN 2", 138, 204, 0x475569);
  tft.fillCircle(195, 204, 3, COLOR_RED); // BTN 2 Red Dot
  _smallText("Cancel", 222, 204, 0x475569);
  tft.setFont();
}

// ── TIMEOUT SCREEN ──────────────────────────────────────────
void drawTimeoutScreen(const char* title, const char* subtitle) {
  displayModalCard(COLOR_RED, false, title, subtitle);
}

// ── ICON HELPERS (High-Resolution Bitmaps) ───────────────────
void drawButtonLabel(int x, int y, uint16_t color, const char* label) {
  _buttonIndicator(x, y + 3, color);
}

void drawIconLock(int x, int y, uint16_t color, bool open) {
  if (open) {
    tft.drawBitmap(x - 16, y - 16, icon_lock_open_32x32, 32, 32, color);
  } else {
    tft.drawBitmap(x - 16, y - 16, icon_lock_closed_32x32, 32, 32, color);
  }
}

void drawSmallPadlock(int x, int y, uint16_t color, bool open) {
  if (open) {
    tft.drawBitmap(x - 5, y - 6, icon_lock_mini_open_10x12, 10, 12, color);
  } else {
    tft.drawBitmap(x - 5, y - 6, icon_lock_mini_closed_10x12, 10, 12, color);
  }
}

void drawWiFiSignal(int x, int y, uint16_t color) {
  for (int i = 0; i < 4; i++)
    tft.fillRect(x + (i * 4), y + (12 - (i * 3)), 3, (i * 3) + 3, color);
}

void drawIconBox(int x, int y, uint16_t color) {
  tft.drawBitmap(x - 16, y - 16, icon_parcel_32x32, 32, 32, color);
}

void drawIconCheck(int x, int y, uint16_t color) {
  tft.drawBitmap(x - 12, y - 12, icon_check_24x24, 24, 24, color);
}

void drawIconX(int x, int y, uint16_t color) {
  tft.drawBitmap(x - 12, y - 12, icon_cross_24x24, 24, 24, color);
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

// (Unused owner and legacy rider multi-scan screens removed)

void drawScanFailedPrompt() {
  displayModalCard(COLOR_RED, false, "SCAN FAILED", "3 attempts exceeded");
  _buttonIndicator(80,  222, COLOR_ACCENT);
  _buttonIndicator(240, 222, COLOR_RED);
  _smallText("RETRY", 80,  206, COLOR_TEXT);
  _smallText("EXIT",  240, 206, COLOR_TEXT);
  tft.setFont();
}

void drawSettingsMenu() {
  if (cloudDeviceAuthenticated()) {
    _twoOvalScreen("System Settings", COLOR_BLUE, 4, "REGISTER", COLOR_RED, 3, "BACK");
  } else {
    _twoOvalScreen("Offline Settings", COLOR_BLUE, 4, "WI-FI SETUP", COLOR_RED, 3, "BLE UNLOCK");
  }
}

void reinitTFT() {
  digitalWrite(TFT_RST, LOW);
  delay(100);
  digitalWrite(TFT_RST, HIGH);
  delay(150);
  tft.begin(TFT_SPI_FREQ);
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

  // Redraw only if a telemetry status actually changes to prevent unnecessary SPI traffic & tearing
  if (wifiOK == lastWifiState && socketOK == lastSocketState && anyOpen == lastDoorState) {
    return;
  }

  // Clear just the telemetry icon cluster (x=126..196, y=4..21)
  tft.fillRect(126, 4, 70, 18, COLOR_BG);

  // 1. Wi-Fi Signal Bars (Centered left at x=130..142)
  uint16_t wifiColor = wifiOK ? COLOR_GREEN : COLOR_RED;
  for (int i = 0; i < 4; i++) {
    int barH = 4 + (i * 3);
    tft.fillRect(130 + (i * 4), 20 - barH, 2, barH, wifiColor);
  }

  // 2. Cloud Backend Icon (Centered at x=152, y=8) - Crisp Bitmap Icon
  uint16_t cloudColor = (!wifiOK) ? COLOR_RED : (socketOK ? COLOR_GREEN : COLOR_RED);
  tft.drawBitmap(152, 8, icon_cloud_16x12, 16, 12, cloudColor);

  // 3. Padlock Status (Centered right at x=178, y=8) - Crisp Bitmap Icon
  uint16_t doorColor = anyOpen ? COLOR_GOLD : 0x64748b;
  if (anyOpen) {
    tft.drawBitmap(178, 8, icon_lock_mini_open_10x12, 10, 12, doorColor);
  } else {
    tft.drawBitmap(178, 8, icon_lock_mini_closed_10x12, 10, 12, doorColor);
  }

  lastWifiState   = wifiOK;
  lastSocketState = socketOK;
  lastDoorState   = anyOpen;
}

void drawNoServerOptionsScreen() {
  displayModalCard(COLOR_RED, false, "NO SERVER", "Device is offline");
  _buttonIndicator(80,  222, COLOR_ACCENT);
  _buttonIndicator(240, 222, COLOR_RED);
  _smallText("RETRY", 80,  206, COLOR_TEXT);
  _smallText("BLE SETUP", 240, 206, COLOR_TEXT);
  tft.setFont();
}

