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
  
  // Use AP_STA so we can scan for networks while acting as an AP
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
  WiFi.softAP(apSSID);
  
  // Pre-scan for handleRoot
  WiFi.scanNetworks(true); 

  Serial.print("[WiFi] AP IP: "); Serial.println(WiFi.softAPIP());
  dnsServer.start(DNS_PORT, "*", apIP);

  server.on("/", HTTP_GET, handleRoot);
  server.on("/save", HTTP_POST, handleSave);
  server.on("/generate_204", handleRoot);
  server.on("/redirect", handleRoot);
  server.on("/hotspot-detect.html", handleRoot);
  
  server.onNotFound(handleNotFound);
  server.begin();
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
  int n = WiFi.scanComplete();
  if (n == -2) {
    WiFi.scanNetworks(true);
  }

  String html = "<!DOCTYPE html><html><head>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>";
  html += "body { font-family: -apple-system, sans-serif; background: #F5F5F7; color: #333; padding: 20px; margin: 0; }";
  html += ".container { max-width: 450px; margin: auto; }";
  html += "h2 { color: #FF9800; text-align: center; margin-bottom: 25px; font-weight: 800; }";
  html += ".net-list { background: #FFFFFF; border-radius: 16px; overflow: hidden; margin-bottom: 20px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); border: 1px solid #EEE; }";
  html += ".net-item { display: flex; align-items: center; padding: 16px 20px; border-bottom: 1px solid #F5F5F5; cursor: pointer; transition: 0.2s; }";
  html += ".net-item:last-child { border-bottom: none; }";
  html += ".net-item:hover { background: #FFF3E0; }";
  html += ".net-info { flex: 1; }";
  html += ".net-ssid { font-weight: 700; font-size: 16px; color: #222; }";
  html += ".net-strength { color: #999; font-size: 12px; margin-top: 2px; }";
  html += ".form-card { background: #FFFFFF; border-radius: 16px; padding: 25px; display: none; margin-top: 20px; box-shadow: 0 8px 24px rgba(0,0,0,0.12); border: 1px solid #EEE; }";
  html += "input { width: 100%; box-sizing: border-box; padding: 14px; margin: 15px 0; border-radius: 12px; border: 1px solid #DDD; background: #FAFAFA; color: #333; font-size: 16px; outline: none; }";
  html += "input:focus { border-color: #FF9800; }";
  html += "button { width: 100%; padding: 16px; border-radius: 12px; border: none; background: #FF9800; color: white; font-weight: bold; font-size: 16px; cursor: pointer; box-shadow: 0 4px 10px rgba(255,152,0,0.3); }";
  html += ".footer { text-align: center; color: #BBB; font-size: 11px; margin-top: 40px; letter-spacing: 1px; text-transform: uppercase; }";
  html += ".lock { margin-left: 10px; opacity: 0.4; filter: grayscale(1); }";
  html += ".wifi-icon { font-size: 20px; margin-left: 10px; color: #FF9800; }";
  html += "</style></head><body>";
  html += "<div class='container'>";
  html += "<h2>Smart Box Setup</h2>";
  
  html += "<p style='color:#666; margin-left: 8px; margin-bottom: 12px; font-weight: 600; font-size: 13px;'>SELECT YOUR WIFI</p>";
  html += "<div class='net-list'>";
  
  if (n <= 0) {
    html += "<div class='net-item'><div class='net-info'><div class='net-ssid'>Scanning...</div><div class='net-strength'>Please wait a moment</div></div></div>";
  } else {
    for (int i = 0; i < n; ++i) {
      String ssid = WiFi.SSID(i);
      int rssi = WiFi.RSSI(i);
      bool secure = (WiFi.encryptionType(i) != WIFI_OFF);
      
      html += "<div class='net-item' onclick='selectNet(\"" + ssid + "\")'>";
      html += "<div class='net-info'>";
      html += "<div class='net-ssid'>" + ssid + "</div>";
      html += "<div class='net-strength'>" + String(rssi) + " dBm</div>";
      html += "</div>";
      if (secure) html += "<div class='lock'>🔒</div>";
      html += "<div class='wifi-icon'>📡</div>";
      html += "</div>";
    }
  }
  html += "<div class='net-item' onclick='selectNet(\"\")'><div class='net-info'><div class='net-ssid' style='color:#FF9800;'>+ Add Hidden Network</div></div></div>";
  html += "</div>";

  html += "<div id='pw-form' class='form-card'>";
  html += "<h3 id='selected-ssid' style='margin-top:0; color:#222; font-size:18px;'>Connect</h3>";
  html += "<form action='/save' method='POST'>";
  html += "<input type='hidden' name='ssid' id='ssid-field'>";
  html += "<input type='password' name='pass' placeholder='WiFi Password' autofocus required>";
  html += "<button type='submit'>SAVE AND CONNECT</button>";
  html += "</form>";
  html += "</div>";
  
  html += "<div class='footer'>SMART PARCEL DROPBOX v1.5</div>";
  html += "</div>";

  html += "<script>";
  html += "function selectNet(ssid) {";
  html += "  document.getElementById('pw-form').style.display='block';";
  html += "  var field = document.getElementById('ssid-field');";
  html += "  field.value = ssid;";
  html += "  document.getElementById('selected-ssid').innerText = 'Connect to ' + (ssid || 'Hidden Network');";
  html += "  if(!ssid) { field.type='text'; field.placeholder='Hidden SSID'; field.required=true; } else { field.type='hidden'; }";
  html += "  window.scrollTo({top: document.body.scrollHeight, behavior: 'smooth'});";
  html += "}";
  html += "</script>";

  html += "</body></html>";
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
