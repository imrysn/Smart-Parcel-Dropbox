// ============================================================
//  WiFiController.ino - Captive Portal for WiFi Setup
// ============================================================

WebServer server(80);
DNSServer dnsServer;

const byte DNS_PORT = 53;
IPAddress apIP(192, 168, 4, 1);
const char* apSSID = "SmartParcelBox_Setup";

void handleRoot();
void handleSave();
void handleNotFound();

void setupCaptivePortal() {
  Serial.println("[WiFi] Starting Captive Portal...");
  
  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
  WiFi.softAP(apSSID);
  
  Serial.print("[WiFi] AP IP: "); Serial.println(WiFi.softAPIP());

  // DNS Server setup (Captive Portal)
  dnsServer.start(DNS_PORT, "*", apIP);

  // Web Server Routes
  server.on("/", HTTP_GET, handleRoot);
  server.on("/save", HTTP_POST, handleSave);
  // Redirect for many mobile captive portal detectors
  server.on("/generate_204", handleRoot);
  server.on("/redirect", handleRoot);
  server.on("/hotspot-detect.html", handleRoot);
  
  server.onNotFound(handleNotFound);
  server.begin();
  
  Serial.println("[WiFi] Web server started.");
}

void loopCaptivePortal() {
  dnsServer.processNextRequest();
  server.handleClient();
}

void stopCaptivePortal() {
  server.stop();
  dnsServer.stop();
  WiFi.softAPdisconnect(true);
}

void handleRoot() {
  String html = "<!DOCTYPE html><html><head>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>";
  html += "body { font-family: -apple-system, system-ui, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #121212; color: white; text-align: center; padding: 20px; }";
  html += ".card { background: #1e1e1e; border-radius: 12px; padding: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); max-width: 400px; margin: auto; }";
  html += "h2 { color: #4285F4; margin-top: 0; }";
  html += "input { width: 90%%; padding: 12px; margin: 10px 0; border-radius: 8px; border: 1px solid #333; background: #2c2c2c; color: white; font-size: 16px; }";
  html += "button { width: 100%%; padding: 12px; margin: 20px 0; border-radius: 8px; border: none; background: #4285F4; color: white; font-weight: bold; font-size: 16px; cursor: pointer; }";
  html += "p { color: #888; font-size: 14px; }";
  html += "</style></head><body>";
  html += "<div class='card'>";
  html += "<h2>Smart Parcel Dropbox</h2>";
  html += "<p>Configure WiFi to get your box online.</p>";
  html += "<form action='/save' method='POST'>";
  html += "<input type='text' name='ssid' placeholder='SSID (WiFi Name)' required>";
  html += "<input type='password' name='pass' placeholder='Password' required>";
  html += "<button type='submit'>SAVE CONFIG</button>";
  html += "</form>";
  html += "<p>The box will reboot automatically.</p>";
  html += "</div></body></html>";
  
  server.send(200, "text/html", html);
}

void handleSave() {
  String ssid = server.arg("ssid");
  String pass = server.arg("pass");
  
  Serial.print("[WiFi] Saving credentials... SSID: "); Serial.println(ssid);
  
  nvsPrefs.begin("smartbox", false);
  nvsPrefs.putString("ssid", ssid);
  nvsPrefs.putString("password", pass);
  nvsPrefs.putBool("registered", false); // Stay unregistered until token process
  nvsPrefs.end();
  
  String html = "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body { background: #121212; color: white; text-align: center; padding: 50px; font-family: sans-serif; }</style></head><body>";
  html += "<h2 style='color:#34A853;'>CONFIG SAVED</h2>";
  html += "<p>The device is rebooting to connect...</p>";
  html += "<p>You can close this page now.</p></body></html>";
  
  server.send(200, "text/html", html);
  
  delay(1000);
  ESP.restart();
}

void handleNotFound() {
  server.sendHeader("Location", String("http://") + apIP.toString(), true);
  server.send(302, "text/plain", "");
}
