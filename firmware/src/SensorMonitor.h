#pragma once
#include "Config.h"
class SensorMonitor {
 public:
  void begin(); void update(); bool confirmed() const; bool belowThreshold() const; void clear();
 private:
  uint16_t filtered_[3] = {}; uint32_t aboveSince_ = 0; uint32_t lastSample_ = 0;
};
