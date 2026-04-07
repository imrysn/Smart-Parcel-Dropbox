// ============================================================
//  config.h — SMART PARCEL DROPBOX SECRETS
//  ⚠ DO NOT COMMIT THIS FILE TO SOURCE CONTROL
//  Add "config.h" to your .gitignore
// ============================================================
#pragma once

// WiFi credentials — compile-time fallback for first-boot registration only.
// At runtime, credentials are saved to NVS by the in-app Hardware Config screen.
#define WIFI_SSID     "itel S25"
#define WIFI_PASSWORD "0987654321"

// Backend server
// LOCAL  → use plain begin(), PORT=3000
// REMOTE → use beginSSL(), PORT=443, HOST="your-app.onrender.com"
#define SERVER_HOST   "smart-parcel-dropbox.onrender.com"
#define SERVER_PORT   443
#define SERVER_PATH   "/socket.io/?EIO=3"
