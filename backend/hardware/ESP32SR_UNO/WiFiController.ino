#include "StateMetrics.h"
#include "BleController.h"

namespace {
struct WifiCredentials {
  char ssid[33];
  char password[64];
};
}

void loadWifiCredentials() {
  WifiCredentials saved{};
  if (nvsPrefs.begin("smartbox", true)) {
    const bool loaded = nvsPrefs.getBytesLength("wifiCreds") == sizeof(saved) &&
        nvsPrefs.getBytes("wifiCreds", &saved, sizeof(saved)) == sizeof(saved);
    if (!loaded) {
      nvsPrefs.getString("ssid", "").toCharArray(saved.ssid, sizeof(saved.ssid));
      nvsPrefs.getString("password", "").toCharArray(saved.password, sizeof(saved.password));
    }
    nvsPrefs.end();
  }
  saved.ssid[sizeof(saved.ssid) - 1] = '\0';
  saved.password[sizeof(saved.password) - 1] = '\0';
  memcpy(nvsWifiSSID, saved.ssid, sizeof(saved.ssid));
  memcpy(nvsWifiPassword, saved.password, sizeof(saved.password));
}

bool saveWifiCredentials(const String& ssid, const String& password) {
  WifiCredentials saved{};
  if (!ssid.length() || ssid.length() >= sizeof(saved.ssid) ||
      password.length() >= sizeof(saved.password)) return false;
  ssid.toCharArray(saved.ssid, sizeof(saved.ssid));
  password.toCharArray(saved.password, sizeof(saved.password));
  if (!nvsPrefs.begin("smartbox", false)) return false;
  const bool stored = nvsPrefs.putBytes("wifiCreds", &saved, sizeof(saved)) == sizeof(saved);
  nvsPrefs.end();
  if (!stored) return false;
  memcpy(nvsWifiSSID, saved.ssid, sizeof(saved.ssid));
  memcpy(nvsWifiPassword, saved.password, sizeof(saved.password));
  return true;
}
