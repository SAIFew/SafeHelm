#include "BleServer.h"

void BleServer::begin() {
  NimBLEDevice::init(Config::DEVICE_NAME);
  NimBLEDevice::setMTU(247);

  server_ = NimBLEDevice::createServer();
  server_->setCallbacks(this);

  auto* service = server_->createService(Config::SERVICE_UUID);
  event_ = service->createCharacteristic(
      Config::EVENT_UUID,
      NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::READ);
  event_->setCallbacks(this);
  event_->setValue("{}");
  service->start();

  auto* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(Config::SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();

  Serial.println("[BLE] GATT Server initialized and advertising started");
}

void BleServer::onConnect(NimBLEServer* pServer) {
  connected_ = true;
  Serial.println("[BLE] Smartphone companion connected");
}

void BleServer::onDisconnect(NimBLEServer* pServer) {
  connected_ = false;
  Serial.println("[BLE] Companion disconnected, resuming advertisement");
  NimBLEDevice::startAdvertising();
}

void BleServer::notify(const String& payload) {
  if (event_ != nullptr) {
    event_->setValue(payload.c_str());
    event_->notify();
  }
}

void BleServer::sendEmergency(const char* type, const String& id) {
  StaticJsonDocument<180> doc;
  doc["version"] = 1;
  doc["type"] = type;
  doc["event_id"] = id;
  doc["timestamp"] = (unsigned long)(millis() / 1000);

  pendingPayload_ = "";
  serializeJson(doc, pendingPayload_);
  pendingId_ = id;
  acknowledged_ = false;
  attempts_ = 0;
  lastSent_ = 0;

  // Send first attempt immediately
  retry();
}

void BleServer::sendStatus() {
  StaticJsonDocument<120> doc;
  doc["version"] = 1;
  doc["type"] = "STATUS";
  doc["device_id"] = Config::DEVICE_NAME;
  String payload;
  serializeJson(doc, payload);
  notify(payload);
}

void BleServer::retry() {
  if (acknowledged_ || attempts_ >= 3) {
    return;
  }
  uint32_t now = millis();
  if (attempts_ > 0 && (now - lastSent_ < 2000)) {
    return;
  }

  attempts_++;
  lastSent_ = now;
  notify(pendingPayload_);

  Serial.printf("[BLE] Transmitted %s (Attempt %u/3): %s\n",
                pendingId_.c_str(), attempts_, pendingPayload_.c_str());
}

void BleServer::onWrite(NimBLECharacteristic* c) {
  StaticJsonDocument<256> doc;
  const std::string raw = c->getValue();
  if (deserializeJson(doc, raw.c_str())) {
    return;
  }
  if (doc["version"] != 1) {
    return;
  }

  const char* type = doc["type"] | "";
  const char* id = doc["event_id"] | "";

  if (strcmp(type, "ACK") == 0 && String(id) == pendingId_) {
    acknowledged_ = true;
    Serial.printf("[BLE] Phone confirmed ACK for event: %s. Retries stopped.\n", id);
  } else if (strcmp(type, "CANCEL") == 0) {
    cancelRequested_ = true;
    acknowledged_ = true;
    Serial.printf("[BLE] Phone requested CANCEL for event: %s.\n", id);
  } else if (strcmp(type, "PING") == 0) {
    StaticJsonDocument<64> pong;
    pong["version"] = 1;
    pong["type"] = "PONG";
    String payload;
    serializeJson(pong, payload);
    notify(payload);
  }
}

bool BleServer::isCancelRequested() {
  if (cancelRequested_) {
    cancelRequested_ = false;
    return true;
  }
  return false;
}

