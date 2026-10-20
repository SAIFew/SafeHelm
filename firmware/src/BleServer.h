#pragma once
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>
#include "Config.h"

class BleServer : public NimBLECharacteristicCallbacks, public NimBLEServerCallbacks {
 public:
  void begin();
  void sendEmergency(const char* type, const String& id);
  void sendStatus();
  void retry();
  bool acknowledged() const { return acknowledged_; }
  bool isConnected() const { return connected_; }
  uint8_t getAttempts() const { return attempts_; }
  bool isCancelRequested();

  // Characteristic Callbacks
  void onWrite(NimBLECharacteristic* c) override;

  // Server Callbacks
  void onConnect(NimBLEServer* pServer) override;
  void onDisconnect(NimBLEServer* pServer) override;

 private:
  NimBLEServer* server_ = nullptr;
  NimBLECharacteristic* event_ = nullptr;
  String pendingId_;
  String pendingPayload_;
  bool acknowledged_ = true;
  bool connected_ = false;
  bool cancelRequested_ = false;
  uint8_t attempts_ = 0;
  uint32_t lastSent_ = 0;

  void notify(const String& payload);
};

