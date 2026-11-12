#include "BleController.h"
#include "StateMetrics.h"
#include "config.h"
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <WiFi.h>
#include <esp_mac.h>
#include <esp_random.h>
#include <esp_timer.h>
#include <freertos/queue.h>
#include <mbedtls/gcm.h>
#include <mbedtls/md.h>
#include <mbedtls/platform_util.h>

void drawQRCode(int x, int y, int moduleSize, const String& text);
void displayMessage(const char* title, const char* msg);

namespace {
constexpr uint32_t WINDOW_MS = 120000;
constexpr uint32_t CHALLENGE_MS = 15000;
constexpr uint32_t WIFI_TIMEOUT_MS = 20000;
constexpr uint32_t GRANT_SECONDS = 8 * 60 * 60;
constexpr size_t MAX_PACKET = 400;
constexpr char WRITE_UUID[] = "a9f40002-49af-44eb-b1ba-000000000000";
constexpr char READ_UUID[] = "a9f40003-49af-44eb-b1ba-000000000000";

struct Chunk {
  uint8_t length;
  uint8_t bytes[20];
};

struct Reply {
  size_t length;
  uint8_t bytes[160];
};

QueueHandle_t incoming;
QueueHandle_t outgoing;
BLEServer* server;
String deviceId;
String challenge;
uint32_t challengeAt;
uint32_t startedAt;
uint32_t clockSeconds;
int64_t clockAt;
LocalBleMode mode;
bool active;
bool wasConnected;
uint8_t setupSecret[16];
char packet[MAX_PACKET + 1];
size_t packetSize;
uint8_t nextChunk;

String pendingSsid;
String pendingPassword;
uint32_t wifiRequestId;
uint32_t wifiStarted;
uint32_t rebootAt;
bool localDoorOpened;

class ReceiveChunks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    const size_t length = characteristic->getLength();
    if (length < 2 || length > sizeof(Chunk::bytes)) return;
    Chunk chunk{};
    chunk.length = length;
    memcpy(chunk.bytes, characteristic->getData(), length);
    xQueueSend(incoming, &chunk, 0);
  }
};

class ReadReply : public BLECharacteristicCallbacks {
  void onRead(BLECharacteristic* characteristic) override {
    Reply value{};
    if (xQueuePeek(outgoing, &value, 0) == pdTRUE) characteristic->setValue(value.bytes, value.length);
  }
};

String encodeHex(const uint8_t* bytes, size_t size) {
  const char digits[] = "0123456789abcdef";
  String result;
  result.reserve(size * 2);
  for (size_t i = 0; i < size; ++i) {
    result += digits[bytes[i] >> 4];
    result += digits[bytes[i] & 0xf];
  }
  return result;
}

int hexDigit(char value) {
  if (value >= '0' && value <= '9') return value - '0';
  if (value >= 'a' && value <= 'f') return value - 'a' + 10;
  return -1;
}

bool decodeHex(const char* input, uint8_t* output, size_t bytes) {
  if (!input || strlen(input) != bytes * 2) return false;
  for (size_t i = 0; i < bytes; ++i) {
    const int high = hexDigit(input[i * 2]);
    const int low = hexDigit(input[i * 2 + 1]);
    if (high < 0 || low < 0) return false;
    output[i] = (high << 4) | low;
  }
  return true;
}

bool hmac(const uint8_t* key, size_t keyBytes, const String& message, uint8_t (&digest)[32]) {
  const auto* sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  return sha256 && mbedtls_md_hmac(sha256, key, keyBytes,
      reinterpret_cast<const uint8_t*>(message.c_str()), message.length(), digest) == 0;
}

bool validProof(const uint8_t* key, size_t keyBytes, const String& message, const char* proof) {
  uint8_t expected[32];
  uint8_t supplied[32];
  if (!decodeHex(proof, supplied, sizeof(supplied)) || !hmac(key, keyBytes, message, expected)) return false;
  uint8_t difference = 0;
  for (size_t i = 0; i < sizeof(expected); ++i) difference |= expected[i] ^ supplied[i];
  return difference == 0;
}

const uint8_t* deviceKey() {
  return reinterpret_cast<const uint8_t*>(SPD_DEVICE_KEY);
}

String macAddress() {
  uint8_t bytes[6];
  if (esp_read_mac(bytes, ESP_MAC_WIFI_STA) != ESP_OK) return String();
  char id[18];
  snprintf(id, sizeof(id), "%02X:%02X:%02X:%02X:%02X:%02X",
      bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]);
  return String(id);
}

uint32_t trustedSeconds() {
  return clockSeconds ? clockSeconds + (esp_timer_get_time() - clockAt) / 1000000 : 0;
}

void respond(uint32_t id, const char* status, const String& proof = "", const String& nonce = "") {
  StaticJsonDocument<256> response;
  response["rid"] = id;
  response["status"] = status;
  if (proof.length()) response["proof"] = proof;
  if (nonce.length()) response["nonce"] = nonce;
  Reply value{};
  value.length = serializeJson(response, value.bytes, sizeof(value.bytes));
  xQueueOverwrite(outgoing, &value);
}

String responseProof(const uint8_t* key, size_t size, const String& message) {
  uint8_t digest[32];
  return hmac(key, size, message, digest) ? encodeHex(digest, sizeof(digest)) : String();
}

bool startWifi(const JsonDocument& request, const String& nonce) {
  uint8_t key[32], iv[12], tag[16], ciphertext[96], plaintext[97]{};
  const char* data = request["data"] | "";
  const size_t length = strlen(data) / 2;
  if (length < 2 || length > sizeof(ciphertext) || !decodeHex(data, ciphertext, length) ||
      !decodeHex(request["iv"] | "", iv, sizeof(iv)) || !decodeHex(request["tag"] | "", tag, sizeof(tag)) ||
      !hmac(setupSecret, sizeof(setupSecret), "SPD-BLE-WIFI-V1|" + deviceId + "|" + nonce, key)) return false;

  mbedtls_gcm_context context;
  mbedtls_gcm_init(&context);
  const bool decrypted = mbedtls_gcm_setkey(&context, MBEDTLS_CIPHER_ID_AES, key, 256) == 0 &&
      mbedtls_gcm_auth_decrypt(&context, length, iv, sizeof(iv), nullptr, 0, tag, sizeof(tag), ciphertext, plaintext) == 0;
  mbedtls_gcm_free(&context);
  mbedtls_platform_zeroize(key, sizeof(key));
  const size_t ssidBytes = plaintext[0];
  if (!decrypted || ssidBytes < 1 || ssidBytes > 32 || ssidBytes >= length ||
      memchr(plaintext + 1, 0, length - 1)) {
    mbedtls_platform_zeroize(plaintext, sizeof(plaintext));
    return false;
  }
  const size_t passwordBytes = length - 1 - ssidBytes;
  if (passwordBytes > 63 || (passwordBytes > 0 && passwordBytes < 8)) {
    mbedtls_platform_zeroize(plaintext, sizeof(plaintext));
    return false;
  }
  pendingSsid = String(reinterpret_cast<const char*>(plaintext + 1), ssidBytes);
  pendingPassword = reinterpret_cast<const char*>(plaintext + 1 + ssidBytes);
  mbedtls_platform_zeroize(plaintext, sizeof(plaintext));

  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.setAutoReconnect(false);
  const bool wasOnWifi = WiFi.status() == WL_CONNECTED;
  if (!WiFi.disconnect(false, false, 1000) && wasOnWifi) {
    WiFi.setAutoReconnect(true);
    pendingSsid = "";
    pendingPassword = "";
    return false;
  }
  wifiRequestId = request["rid"].as<uint32_t>();
  wifiStarted = millis();
  challenge = nonce;
  WiFi.begin(pendingSsid.c_str(), pendingPassword.c_str());
  displayMessage("WIFI SETUP", "Joining network...");
  return true;
}

void restoreWifi() {
  WiFi.disconnect();
  WiFi.setAutoReconnect(true);
  loadWifiCredentials();
  if (strlen(nvsWifiSSID)) WiFi.begin(nvsWifiSSID, nvsWifiPassword);
  else if (strlen(WIFI_SSID)) WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

void finishWifi(bool joined) {
  const bool saved = joined && saveWifiCredentials(pendingSsid, pendingPassword);
  const char* status = saved ? "connected" : (joined ? "storage_failed" : "wifi_failed");
  respond(wifiRequestId, status, responseProof(setupSecret, sizeof(setupSecret),
      "SPD-BLE-WIFI-RESULT-V1|" + deviceId + "|" + challenge + "|" + status));
  pendingPassword = "";
  pendingSsid = "";
  wifiRequestId = 0;
  challenge = "";
  if (saved) {
    displayMessage("WIFI CONNECTED", "Restarting Dropbox...");
    rebootAt = millis() + 3000;
  } else {
    restoreWifi();
    displayMessage("WIFI SETUP", "Retry from the app");
  }
}

bool openReceivedDoor(const JsonDocument& request, const String& nonce) {
  const char* grant = request["grant"] | "";
  uint8_t grantBytes[16];
  const uint32_t expires = request["expires"] | 0U;
  const uint32_t now = trustedSeconds();
  if (!deviceRegistered || cloudDeviceAuthenticated() || !now || expires <= now || expires - now > GRANT_SECONDS ||
      strlen(SPD_DEVICE_KEY) < 32 || !decodeHex(grant, grantBytes, sizeof(grantBytes)) ||
      lockTopOpen || lockPickupOpen || lockReceivedOpen || readReedDebounced(REED_RECEIVED) != 0) return false;

  uint8_t grantKey[32];
  if (!hmac(deviceKey(), strlen(SPD_DEVICE_KEY),
      "SPD-BLE-GRANT-V1|" + deviceId + "|" + grant + "|" + String(expires), grantKey)) return false;
  const bool authorized = validProof(grantKey, sizeof(grantKey), "SPD-BLE-OPEN-V1|" + nonce, request["proof"] | "");
  String proof;
  if (authorized) proof = responseProof(grantKey, sizeof(grantKey), "SPD-BLE-UNLOCK-RESULT-V1|" + nonce + "|opened");
  mbedtls_platform_zeroize(grantKey, sizeof(grantKey));
  if (!proof.length()) return false;

  handleControlDoor("{\"type\":\"received\",\"action\":\"open\"}");
  if (!lockReceivedOpen) return false;
  localDoorOpened = true;
  respond(request["rid"].as<uint32_t>(), "opened", proof);
  return true;
}

void handlePacket() {
  StaticJsonDocument<640> request;
  if (deserializeJson(request, static_cast<const char*>(packet), packetSize)) return;
  const uint32_t id = request["rid"] | 0U;
  if (!id || wifiRequestId || rebootAt || localDoorOpened) return;
  const char* op = request["op"] | "";
  if (strcmp(op, "hello") == 0) {
    challenge = makeBleNonce();
    challengeAt = millis();
    respond(id, "ready", "", challenge);
    return;
  }

  const String nonce = challenge;
  challenge = "";
  if (!nonce.length() || millis() - challengeAt > CHALLENGE_MS) {
    respond(id, "rejected");
    return;
  }
  if (mode == LocalBleMode::wifi && strcmp(op, "wifi") == 0 && startWifi(request, nonce)) return;
  if (mode == LocalBleMode::unlock && strcmp(op, "unlock") == 0 && openReceivedDoor(request, nonce)) return;
  respond(id, "rejected");
}

void receiveChunk(const Chunk& chunk) {
  const uint8_t sequence = chunk.bytes[0] & 0x7f;
  if (!sequence) {
    nextChunk = 0;
    packetSize = 0;
  }
  const size_t bytes = chunk.length - 1;
  if (sequence != nextChunk || packetSize + bytes > MAX_PACKET) {
    nextChunk = 0;
    packetSize = 0;
    return;
  }
  memcpy(packet + packetSize, chunk.bytes + 1, bytes);
  packetSize += bytes;
  ++nextChunk;
  if (chunk.bytes[0] & 0x80) {
    packet[packetSize] = '\0';
    handlePacket();
    nextChunk = 0;
    packetSize = 0;
  }
}
}

String makeBleNonce() {
  uint8_t bytes[16];
  esp_fill_random(bytes, sizeof(bytes));
  return encodeHex(bytes, sizeof(bytes));
}

bool acceptOfflineClock(const String& nonce, uint32_t seconds, const char* proof) {
  if (nonce.length() != 32 || seconds < 1700000000U || strlen(SPD_DEVICE_KEY) < 32 ||
      !validProof(deviceKey(), strlen(SPD_DEVICE_KEY),
          "SPD-BLE-CLOCK-V1|" + macAddress() + "|" + nonce + "|" + String(seconds), proof)) return false;
  clockSeconds = max(seconds, trustedSeconds());
  clockAt = esp_timer_get_time();
  return true;
}

bool offlineClockAvailable() { return clockSeconds != 0; }

bool startLocalBle(LocalBleMode selectedMode) {
  if (selectedMode == LocalBleMode::unlock && (!offlineClockAvailable() || !deviceRegistered || cloudDeviceAuthenticated())) {
    return false;
  }
  String mac = macAddress();
  mac.replace(":", "");
  if (mac.length() != 12 || mac == "000000000000") return false;
  deviceId = macAddress();
  if (!server) {
    if (!incoming) incoming = xQueueCreate(32, sizeof(Chunk));
    if (!outgoing) outgoing = xQueueCreate(1, sizeof(Reply));
    if (!incoming || !outgoing) return false;
    BLEDevice::init("SPD");
    server = BLEDevice::createServer();
    mac.toLowerCase();
    const String uuid = "a9f40001-49af-44eb-b1ba-" + mac;
    auto* service = server->createService(uuid.c_str());
    auto* receive = service->createCharacteristic(WRITE_UUID, BLECharacteristic::PROPERTY_WRITE);
    receive->setCallbacks(new ReceiveChunks());
    auto* reply = service->createCharacteristic(READ_UUID, BLECharacteristic::PROPERTY_READ);
    reply->setCallbacks(new ReadReply());
    service->start();
    BLEDevice::getAdvertising()->addServiceUUID(uuid.c_str());
  }

  xQueueReset(incoming);
  mode = selectedMode;
  active = true;
  wasConnected = false;
  localDoorOpened = false;
  startedAt = millis();
  nextChunk = 0;
  packetSize = 0;
  challenge = "";
  const Reply empty{2, {'{', '}'}};
  xQueueOverwrite(outgoing, &empty);
  BLEDevice::startAdvertising();
  if (mode == LocalBleMode::wifi) {
    esp_fill_random(setupSecret, sizeof(setupSecret));
    mac.toUpperCase();
    String qr = "SPDBLE:" + mac + ":" + encodeHex(setupSecret, sizeof(setupSecret));
    qr.toUpperCase();
    tft.fillScreen(COLOR_TEXT);
    tft.setTextColor(COLOR_BG);
    tft.setFont();
    tft.setTextSize(2);
    tft.setCursor(42, 17);
    tft.print("Bluetooth Wi-Fi");
    drawQRCode(87, 55, 5, qr);
    tft.setTextSize(1);
    tft.setCursor(48, 229);
    tft.print("Scan in SPD app within 2 minutes");
  } else {
    displayMessage("OFFLINE UNLOCK", "Confirm in the SPD app");
  }
  return true;
}

bool pollLocalBle() {
  if (!active) return false;
  if (rebootAt && static_cast<int32_t>(millis() - rebootAt) >= 0) ESP.restart();
  if (wifiRequestId) {
    if (WiFi.status() == WL_CONNECTED && WiFi.SSID() == pendingSsid) finishWifi(true);
    else if (millis() - wifiStarted >= WIFI_TIMEOUT_MS) finishWifi(false);
  }
  if (localDoorOpened) return lockReceivedOpen;
  if (rebootAt || wifiRequestId) return true;
  if (millis() - startedAt > WINDOW_MS) return false;

  const bool connected = server->getConnectedCount() != 0;
  if (!connected && wasConnected) {
    challenge = "";
    packetSize = 0;
    nextChunk = 0;
    xQueueReset(incoming);
    BLEDevice::startAdvertising();
  }
  wasConnected = connected;
  if (connected) {
    Chunk chunk;
    for (int i = 0; i < 32 && xQueueReceive(incoming, &chunk, 0) == pdTRUE; ++i) receiveChunk(chunk);
  }
  return true;
}

void stopLocalBle() {
  if (!active) return;
  if (rebootAt) ESP.restart();
  active = false;
  BLEDevice::stopAdvertising();
  if (server->getConnectedCount()) server->disconnect(server->getConnId());
  if (wifiRequestId) restoreWifi();
  if (localDoorOpened && lockReceivedOpen) handleControlDoor("{\"type\":\"received\",\"action\":\"close\"}");
  pendingPassword = "";
  pendingSsid = "";
  wifiRequestId = 0;
  challenge = "";
  mbedtls_platform_zeroize(setupSecret, sizeof(setupSecret));
}
