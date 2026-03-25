// ============================================================
//  DisplayController2.ino  – Smartwatch Sub-menu screens
// ============================================================

static void _twoOvalScreen(
  const char* contextLabel,
  uint16_t leftColor,  int leftIcon,  const char* leftLabel,
  uint16_t rightColor, int rightIcon, const char* rightLabel)
{
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Context label (small, centered, below status bar)
  if (strlen(contextLabel) > 0) {
    _smallText(contextLabel, 160, 48, COLOR_GREY);
  }

  // Vertical Oval Buttons (shifted down for balance cy=138)
  _verticalOvalButton(80,  138, 100, 140, leftLabel,  leftColor,  leftIcon);
  _verticalOvalButton(240, 138, 100, 140, rightLabel, rightColor, rightIcon);

  tft.setFont();
}

// ── Pickup Type Select ─────────────────────────────────────
void drawPickupSelectScreen() {
  // OWNER (blue, lock) | RIDER (red, box)
  _twoOvalScreen("Select Mode",
    COLOR_BLUE, 1, "OWNER",
    COLOR_RED,  0, "RIDER");
}

// ── Owner Mode (single vs multi) ──────────────────────────
void drawOwnerModeScreen() {
  _twoOvalScreen("Owner Pick Up",
    COLOR_BLUE,   0, "SINGLE",
    COLOR_PURPLE, 0, "MULTI");
}

// ── Add More Prompt ────────────────────────────────────────
void drawAddMorePrompt() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Count badge in center-top
  String countStr = "Parcel #" + String(scannedCount) + " registered";
  _smallText(countStr.c_str(), 160, 48, COLOR_GREEN);

  // ADD MORE (blue, box icon) | DONE (green, check icon)
  _verticalOvalButton(80,  138, 100, 140, "ADD MORE", COLOR_BLUE, 0);
  _verticalOvalButton(240, 138, 100, 140, "DONE",     COLOR_GREEN, 2);

  tft.setFont();
}

// ── Rider: Scan ID screen ─────────────────────────────────
void drawRiderScanIdScreen() {
  drawScannerBg(); // brackets + laser + EXIT circle
  _boldText("SCAN RIDER ID", 160, 75, COLOR_GREY);
}

// ── Rider: Scan Parcel screen ─────────────────────────────
void drawRiderScanParcelScreen() {
  drawScannerBg();
  String prompt = "Scan Parcel #" + String(scannedCount + 1);
  _boldText(prompt.c_str(), 160, 75, COLOR_GREY);
}

// ── Rider: Pick up more prompt ────────────────────────────
void drawRiderPickupMorePrompt() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();
  String countStr = "#" + String(scannedCount) + " marked done";
  _smallText(countStr.c_str(), 160, 48, COLOR_GREEN);

  // PICK UP MORE (blue, plus icon) | DONE (green, check icon)
  _verticalOvalButton(80,  138, 100, 140, "MORE", COLOR_BLUE, 4);
  _verticalOvalButton(240, 138, 100, 140, "DONE", COLOR_GREEN, 2);

  tft.setFont();
}

// ── Scan Failed Prompt ────────────────────────────────────
void drawScanFailedPrompt() {
  tft.fillScreen(COLOR_BG);
  drawStatusBar();

  // Red oval (200x76) - More Spacious
  _horizontalOval(160, 105, 200, 76, COLOR_RED);
  drawIconX(160, 102, COLOR_TEXT);

  _boldText("SCAN FAILED", 160, 182, COLOR_TEXT);
  _smallText("3 attempts exceeded", 160, 205, COLOR_GREY);

  // RETRY and EXIT indicators
  _buttonIndicator(80,  232, COLOR_BLUE);
  _buttonIndicator(240, 232, COLOR_RED);
  _smallText("RETRY", 80,  218, COLOR_TEXT);
  _smallText("EXIT",  240, 218, COLOR_TEXT);
  tft.setFont();
}

// ── Legacy stub ──────────────────────────────────────────
void drawModernButton(int x, int y, int w, int h, uint16_t bgColor, const char* label) {
  // Replaced by circle indicators - no-op kept for compile compat
  (void)x; (void)y; (void)w; (void)h; (void)bgColor; (void)label;
}
