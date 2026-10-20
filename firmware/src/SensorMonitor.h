#pragma once
#include <Arduino.h>
#include "Config.h"

class SensorMonitor {
 public:
  void begin();
  void update();
  bool confirmed() const;
  bool belowThreshold() const;
  void clear();
  void getValues(uint16_t& left, uint16_t& right, uint16_t& center) const;
  uint8_t getTriggeredCount() const;

 private:
  uint16_t filtered_[3] = {0, 0, 0};
  uint32_t aboveSince_ = 0;
  uint32_t lastSample_ = 0;
  uint8_t lastAboveCount_ = 0;
};

