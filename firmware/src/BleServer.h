#pragma once
#include <NimBLEDevice.h>
#include <ArduinoJson.h>
#include "Config.h"
class BleServer : public NimBLECharacteristicCallbacks {
 public:
  void begin(); void sendEmergency(const char* type, const String& id); void sendStatus(); void retry(); bool acknowledged()const{return acknowledged_;}
  void onWrite(NimBLECharacteristic* c) override;
 private:
  NimBLECharacteristic* event_ = nullptr; String pendingId_; String pendingPayload_; bool acknowledged_=true; uint8_t attempts_=0; uint32_t lastSent_=0;
  void notify(const String& payload);
};
