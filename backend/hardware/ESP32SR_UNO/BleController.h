#pragma once

#include <Arduino.h>

enum class LocalBleMode { wifi, unlock };

bool startLocalBle(LocalBleMode mode);
bool pollLocalBle();
void stopLocalBle();
String makeBleNonce();
bool acceptOfflineClock(const String& nonce, uint32_t seconds, const char* proof);
bool offlineClockAvailable();
bool cloudDeviceAuthenticated();
void loadWifiCredentials();
bool saveWifiCredentials(const String& ssid, const String& password);
