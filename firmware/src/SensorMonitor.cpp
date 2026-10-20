#include "SensorMonitor.h"

void SensorMonitor::begin() {
  analogReadResolution(12);
  filtered_[0] = 0;
  filtered_[1] = 0;
  filtered_[2] = 0;
  aboveSince_ = 0;
  lastSample_ = 0;
  lastAboveCount_ = 0;
}

void SensorMonitor::update() {
  uint32_t now = millis();
  if (now - lastSample_ < Config::SAMPLE_INTERVAL_MS) {
    return;
  }
  lastSample_ = now;

  const int pins[] = {
    Config::FORCE_SENSOR_LEFT_PIN,
    Config::FORCE_SENSOR_RIGHT_PIN,
    Config::FORCE_SENSOR_CENTER_PIN
  };

  uint8_t aboveCount = 0;
  for (int i = 0; i < 3; i++) {
    uint16_t raw = analogRead(pins[i]);
    // 4-tap running average filter: (3 * filtered + raw) / 4
    filtered_[i] = (uint16_t)(((uint32_t)filtered_[i] * 3 + raw) / 4);
    if (filtered_[i] >= Config::ACCIDENT_THRESHOLD) {
      aboveCount++;
    }
  }

  lastAboveCount_ = aboveCount;

  if (Config::SAFEHELM_CALIBRATION) {
    Serial.printf("[FSR] L:%u R:%u C:%u (trig:%u)\n",
                  filtered_[0], filtered_[1], filtered_[2], aboveCount);
  }

  // Majority-voting: requires at least 2 of 3 sensors to cross threshold simultaneously
  if (aboveCount >= 2) {
    if (aboveSince_ == 0) {
      aboveSince_ = now;
    }
  } else {
    aboveSince_ = 0;
  }
}

bool SensorMonitor::confirmed() const {
  return aboveSince_ != 0 && (millis() - aboveSince_ >= Config::CONFIRMATION_MS);
}

bool SensorMonitor::belowThreshold() const {
  return lastAboveCount_ < 2;
}

void SensorMonitor::clear() {
  aboveSince_ = 0;
}

void SensorMonitor::getValues(uint16_t& left, uint16_t& right, uint16_t& center) const {
  left = filtered_[0];
  right = filtered_[1];
  center = filtered_[2];
}

uint8_t SensorMonitor::getTriggeredCount() const {
  return lastAboveCount_;
}

