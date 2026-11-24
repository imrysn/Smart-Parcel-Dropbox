#include <Arduino.h>
#include <ArduinoJson.h>
#include <esp_random.h>
#include "config.h"
#include "StateMetrics.h"

namespace {
constexpr uint8_t batchLimit = 32;
constexpr unsigned long attemptMs = 8000;
constexpr unsigned long responseMs = 5000;
constexpr unsigned long clearMs = 350;
constexpr unsigned long openMs = 15000;
constexpr unsigned long batchIdleMs = 60000;
enum class BatchOutcome : uint8_t { awaiting, confirmed, review };
enum class BatchStage : uint8_t { scan, authorizing, opening, passage, rearming, closing };
struct BatchItem {
  char trackingRecordId[25];
  BatchOutcome outcome;
  bool synced;
  bool needsOperator;
};
struct BatchLedger {
  uint8_t version = 1;
  char batchId[33] = {};
  uint8_t count = 0;
  bool closed = false;
  BatchItem items[batchLimit] = {};
};

BatchLedger ledger;
BatchStage batchStage;
bool loaded = false;
bool storageFault = false;
bool finishing = false;
bool finishRequested = false;
bool opened = false;
bool nearSeen = false;
bool redReleased = false;
unsigned long redPressedAt;
bool lastRawDoorOpen = false;
bool stableDoorOpen = false;
unsigned long doorChangedAt;
bool replayConflict = false;
unsigned long stageAt, lastActivity, sampledAt, validSampleAt, clearAt, sentAt;
uint32_t requestSequence = 0, scanRequest = 0, replayRequest = 0;
uint8_t replayIndex = 0;
char batchScan[64] = {};
uint8_t batchScanLength = 0;
bool discardScan = false;

bool persistBatch() {
  Preferences prefs;
  if (!prefs.begin("dropoff", false)) return false;
  const bool saved = prefs.putBytes("batch", &ledger, sizeof(ledger)) == sizeof(ledger);
  prefs.end();
  return saved;
}

void loadBatch() {
  if (loaded) return;
  loaded = true;
  Preferences prefs;
  if (!prefs.begin("dropoff", false)) {
    storageFault = true;
    return;
  }
  const size_t bytes = prefs.getBytesLength("batch");
  if (bytes) {
    storageFault = bytes != sizeof(ledger) ||
      prefs.getBytes("batch", &ledger, sizeof(ledger)) != sizeof(ledger) ||
      ledger.version != 1 || ledger.count > batchLimit;
  }
  prefs.end();
  if (!storageFault) {
    for (uint8_t i = 0; i < ledger.count; i++) {
      replayConflict |= ledger.items[i].needsOperator;
    }
  }
}

void closeBatchLatch() {
  digitalWrite(LOCK_TOP, HIGH);
  lockTopOpen = false;
  emitDoorState();
}

void showBatchScanner() {
  unsigned confirmed = 0;
  for (uint8_t i = 0; i < ledger.count; i++) {
    if (ledger.items[i].outcome == BatchOutcome::confirmed) confirmed++;
  }
  char message[52];
  snprintf(message, sizeof(message), "%u accepted / %u review", confirmed, ledger.count - confirmed);
  displayMessage("SCAN NEXT PARCEL", message);
}

void enterBatchStage(BatchStage stage) {
  batchStage = stage;
  stageAt = millis();
}

uint32_t sendBatchRequest(const char* name, const JsonDocument& data) {
  const uint32_t id = ++requestSequence;
  String packet(id);
  packet += "[\"";
  packet += name;
  packet += "\",";
  serializeJson(data, packet);
  packet += ']';
  return socketIO.send(sIOtype_EVENT, packet) ? id : 0;
}

void finishBatchScanning() {
  finishing = true;
  scanRequest = 0;
  closeBatchLatch();
  if (batchStage != BatchStage::passage) enterBatchStage(BatchStage::closing);
  displayMessage("FINISH DROPOFF", finishRequested ? "Close door to finish" : "Press Red, then close door");
}

void saveBatchOutcome(BatchOutcome outcome) {
  ledger.items[ledger.count - 1].outcome = outcome;
  if (!persistBatch()) {
    storageFault = true;
    ledger.items[ledger.count - 1].outcome = BatchOutcome::review;
    finishBatchScanning();
  }
  lastActivity = millis();
  if (ledger.count >= SPD_BATCH_MAX_ITEMS) finishBatchScanning();
  if (finishing) {
    enterBatchStage(BatchStage::closing);
    displayMessage("FINISH DROPOFF", finishRequested ? "Close door to finish" : "Press Red, then close door");
  } else if (outcome == BatchOutcome::review) {
    clearAt = 0;
    enterBatchStage(BatchStage::rearming);
    displayMessage("CHECKING CHUTE", "Parcel saved for owner review");
  } else {
    enterBatchStage(BatchStage::scan);
    showBatchScanner();
    if (outcome == BatchOutcome::confirmed) triggerBuzzer(1);
  }
}

void finalizeBatch() {
  if (!opened) ledger = BatchLedger{};
  ledger.closed = ledger.count > 0;
  if (!persistBatch()) {
    storageFault = true;
    displayMessage("STORAGE ERROR", "Saved records need service");
    return;
  }
  closeBatchLatch();
  changeState(RESETTING);
}
}

bool batchDropoffAvailable() {
  return SPD_BATCH_CHUTE_NEAR_CM > 1 && SPD_BATCH_CHUTE_NEAR_CM < 343 &&
    SPD_BATCH_CHUTE_SAMPLE_MS > 0 && SPD_BATCH_CHUTE_SAMPLE_MS <= clearMs &&
    SPD_BATCH_MAX_ITEMS > 0 && SPD_BATCH_MAX_ITEMS <= batchLimit;
}

bool startBatchDropoff() {
  loadBatch();
  if (!batchDropoffAvailable() || storageFault || ledger.count > 0 || !cloudDeviceAuthenticated() ||
      readReedDebounced(REED_TOP) != 0 || lockTopOpen) {
    displayMessage("BATCH UNAVAILABLE", storageFault || replayConflict
      ? "Contact support" : ledger.count > 0 ? "Waiting for batch sync" : "Check network and door");
    return false;
  }
  ledger = BatchLedger{};
  snprintf(ledger.batchId, sizeof(ledger.batchId), "%08lx%08lx%08lx%08lx",
    (unsigned long)esp_random(), (unsigned long)esp_random(),
    (unsigned long)esp_random(), (unsigned long)esp_random());
  finishing = finishRequested = opened = nearSeen = redReleased = discardScan = false;
  lastRawDoorOpen = stableDoorOpen = false;
  doorChangedAt = millis();
  redPressedAt = 0;
  scanRequest = batchScanLength = 0;
  clearAt = sampledAt = 0;
  validSampleAt = lastActivity = millis();
  changeState(BATCH_DROPOFF);
  enterBatchStage(BatchStage::scan);
  displayMessage("MULTIPLE PARCELS", "Scan the first parcel");
  return true;
}

void updateBatchDropoff() {
  const unsigned long now = millis();
  const bool rawDoorOpen = digitalRead(REED_TOP) == HIGH;
  if (rawDoorOpen != lastRawDoorOpen) {
    lastRawDoorOpen = rawDoorOpen;
    doorChangedAt = now;
  }
  if (now - doorChangedAt >= 20) stableDoorOpen = rawDoorOpen;
  const bool doorOpen = stableDoorOpen;
  if (batchStage == BatchStage::opening && doorOpen) {
    opened = true;
    closeBatchLatch();
    enterBatchStage(BatchStage::passage);
  }
  if (digitalRead(BTN_PICKUP) == HIGH) {
    redReleased = true;
    redPressedAt = 0;
  } else if (redReleased && !finishRequested) {
    if (!redPressedAt) redPressedAt = now;
    if (now - redPressedAt >= 30) {
      finishRequested = true;
      if (batchStage == BatchStage::opening) saveBatchOutcome(BatchOutcome::review);
      finishBatchScanning();
    }
  }
  if (batchStage == BatchStage::opening && now - stageAt >= openMs) {
    saveBatchOutcome(BatchOutcome::review);
    finishBatchScanning();
  }
  if (!finishing && now - lastActivity >= batchIdleMs) finishBatchScanning();
  if (batchStage == BatchStage::closing) {
    if (finishRequested && !doorOpen && !storageFault) finalizeBatch();
    return;
  }

  // Only this loop triggers the chute sensor during a batch.
  if (now - sampledAt >= SPD_BATCH_CHUTE_SAMPLE_MS) {
    sampledAt = now;
    const float distance = sampleDropoffChute();
    if (distance > 1.0 && distance < 900.0) {
      validSampleAt = now;
      if (distance <= SPD_BATCH_CHUTE_NEAR_CM) {
        clearAt = 0;
        if ((batchStage == BatchStage::opening || batchStage == BatchStage::passage) && rawDoorOpen) nearSeen = true;
        else if (opened && doorOpen) finishBatchScanning();
      } else if (clearAt == 0) {
        clearAt = now;
      }
    } else {
      clearAt = 0;
    }
  }
  const bool clear = clearAt != 0 && now - clearAt >= clearMs && now - validSampleAt <= clearMs;
  if (batchStage == BatchStage::passage) {
    while (Serial2.available()) Serial2.read();
    batchScanLength = 0;
    discardScan = false;
    if (nearSeen && clear) {
      saveBatchOutcome(BatchOutcome::confirmed);
    } else if (now - stageAt >= attemptMs || (!doorOpen && !nearSeen)) {
      // A healthy, clear chute lets the rider keep going after a missed detection.
      if (!clear) finishing = true;
      saveBatchOutcome(BatchOutcome::review);
    }
    return;
  }
  if (now - validSampleAt >= 1500 || (opened && !doorOpen)) {
    finishBatchScanning();
    return;
  }
  if (batchStage == BatchStage::rearming && clear) {
    enterBatchStage(BatchStage::scan);
    showBatchScanner();
  }
  if (batchStage == BatchStage::authorizing && now - stageAt >= responseMs) {
    scanRequest = 0;
    enterBatchStage(BatchStage::scan);
    displayMessage("SCAN TIMED OUT", "Scan again or press Red");
  }

  while (Serial2.available()) {
    const char byte = Serial2.read();
    if (byte == '\r' || byte == '\n') {
      if (!discardScan && batchScanLength >= 3 && batchStage == BatchStage::scan && clear) {
        batchScan[batchScanLength] = '\0';
        StaticJsonDocument<128> data;
        data["barcode"] = batchScan;
        if (cloudDeviceAuthenticated()) scanRequest = sendBatchRequest("verifyBatchScan", data);
        if (scanRequest) {
          enterBatchStage(BatchStage::authorizing);
          displayMessage("VERIFYING", "Wait before dropping");
        } else {
          displayMessage("NO SERVER", "Press Red to finish");
        }
      }
      batchScanLength = 0;
      discardScan = false;
    } else if (byte < 32 || byte > 126 || byte == '[' || byte == ']' || batchScanLength == sizeof(batchScan) - 1) {
      discardScan = true;
    } else if (!discardScan) {
      batchScan[batchScanLength++] = byte;
    }
  }
}

void serviceBatchReplay() {
  loadBatch();
  if (!ledger.count || storageFault || currentState == BATCH_DROPOFF ||
      !cloudDeviceAuthenticated()) return;
  if (!ledger.closed) {
    // A power cut during an open batch leaves the saved attempts for owner review.
    if (readReedDebounced(REED_TOP) != 0) return;
    closeBatchLatch();
    for (uint8_t i = 0; i < ledger.count; i++) ledger.items[i].outcome = BatchOutcome::review;
    ledger.closed = true;
    storageFault = !persistBatch();
    if (storageFault) return;
  }
  const unsigned long now = millis();
  if (now - sentAt < responseMs) return;
  sentAt = now;
  for (replayIndex = 0; replayIndex < ledger.count; replayIndex++) {
    if (!ledger.items[replayIndex].synced && !ledger.items[replayIndex].needsOperator) break;
  }
  if (replayIndex == ledger.count) {
    replayRequest = 0;
    if (replayConflict) return;
    ledger = BatchLedger{};
    storageFault = !persistBatch();
    return;
  }
  const BatchItem& item = ledger.items[replayIndex];
  StaticJsonDocument<240> data;
  data["eventId"] = String(ledger.batchId) + "-" + String(replayIndex);
  data["batchId"] = ledger.batchId;
  data["trackingRecordId"] = item.trackingRecordId;
  data["needsReview"] = item.outcome != BatchOutcome::confirmed;
  replayRequest = sendBatchRequest("batchDropoffItem", data);
}

void handleBatchAck(const uint8_t* payload, size_t length) {
  uint32_t id = 0;
  size_t offset = 0;
  while (offset < length && payload[offset] >= '0' && payload[offset] <= '9') {
    id = id * 10 + payload[offset++] - '0';
  }
  if (!id || (id != scanRequest && id != replayRequest)) return;
  StaticJsonDocument<256> data;
  if (deserializeJson(data, payload + offset, length - offset)) return;
  const JsonVariantConst response = data[0].as<JsonVariantConst>();
  const bool ok = response["ok"] | false;
  if (id == replayRequest) {
    replayRequest = 0;
    if (ok) {
      ledger.items[replayIndex].synced = true;
      storageFault = !persistBatch();
      sentAt = millis() - responseMs;
    } else {
      const String reason = response["reason"] | "";
      if (reason == "tracking_ineligible" || reason == "event_conflict" || reason == "invalid_event") {
        replayConflict = true;
        ledger.items[replayIndex].needsOperator = true;
        storageFault = !persistBatch();
        sentAt = millis() - responseMs;
        Serial.println("[BATCH] Saved delivery needs reconciliation.");
      }
    }
    return;
  }
  scanRequest = 0;
  if (currentState != BATCH_DROPOFF || batchStage != BatchStage::authorizing || finishing) return;
  const char* trackingId = response["trackingRecordId"] | "";
  bool eligible = ok && strlen(trackingId) == 24 && clearAt != 0 &&
    millis() - clearAt >= clearMs && (!opened || stableDoorOpen);
  for (uint8_t i = 0; i < ledger.count; i++) {
    if (strcmp(ledger.items[i].trackingRecordId, trackingId) == 0) eligible = false;
  }
  if (!eligible || ledger.count >= SPD_BATCH_MAX_ITEMS) {
    enterBatchStage(BatchStage::scan);
    displayMessage("SCAN REJECTED", "Scan another parcel");
    return;
  }
  BatchItem& item = ledger.items[ledger.count++];
  snprintf(item.trackingRecordId, sizeof(item.trackingRecordId), "%s", trackingId);
  item.outcome = BatchOutcome::awaiting;
  if (!persistBatch()) {
    storageFault = true;
    finishBatchScanning();
    return;
  }
  nearSeen = false;
  lastActivity = millis();
  if (!opened) {
    digitalWrite(LOCK_TOP, LOW);
    lockTopOpen = true;
    enterBatchStage(BatchStage::opening);
    emitDoorState();
  } else {
    enterBatchStage(BatchStage::passage);
  }
  displayMessage("DROP PARCEL", "Wait for the next prompt");
}
