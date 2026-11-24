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
#if __has_include("device_secrets.h")
#include "device_secrets.h"
#endif
#ifndef SPD_DEVICE_KEY
#define SPD_DEVICE_KEY ""
#endif
#ifndef SPD_FIRMWARE_VERSION
#define SPD_FIRMWARE_VERSION "1.0.0"
#endif

// Set these values in the bench device configuration after testing the chute and bin.
#ifndef SPD_BATCH_CHUTE_NEAR_CM
#define SPD_BATCH_CHUTE_NEAR_CM 0
#endif
#ifndef SPD_BATCH_CHUTE_SAMPLE_MS
#define SPD_BATCH_CHUTE_SAMPLE_MS 0
#endif
#ifndef SPD_BATCH_MAX_ITEMS
#define SPD_BATCH_MAX_ITEMS 0
#endif
#ifndef SERVER_HOST
#define SERVER_HOST   "smart-parcel-dropbox-depth.onrender.com"
#endif
#define SERVER_PORT   443
#define SERVER_PATH   "/socket.io/?EIO=3&clientType=hardware"
