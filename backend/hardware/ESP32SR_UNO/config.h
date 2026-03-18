// ============================================================
//  config.h — SMART PARCEL DROPBOX SECRETS
//  ⚠ DO NOT COMMIT THIS FILE TO SOURCE CONTROL
//  Add "config.h" to your .gitignore
// ============================================================
#pragma once

// WiFi credentials
#define WIFI_SSID     "Android"
#define WIFI_PASSWORD "Perez@543210"

// Backend server
// LOCAL  → use plain begin(), PORT=3000
// REMOTE → use beginSSL(), PORT=443, HOST="your-app.onrender.com"
#define SERVER_HOST   "10.222.49.205"
#define SERVER_PORT   3000
#define SERVER_PATH   "/socket.io/?EIO=3"
