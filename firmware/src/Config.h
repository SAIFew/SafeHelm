#pragma once
#include <Arduino.h>

namespace Config {
// Tested breadboard wiring: GPIO36=VP, GPIO39=VN, GPIO34=D34
constexpr int FORCE_SENSOR_LEFT_PIN = 36;
constexpr int FORCE_SENSOR_RIGHT_PIN = 39;
constexpr int FORCE_SENSOR_CENTER_PIN = 34;

// GPIO12 drives 2N2222A base via 1kΩ; never drives 5V buzzer directly
constexpr int BUZZER_PIN = 12;

// Tactile button: INPUT_PULLUP, pressed = LOW
constexpr int MANUAL_BUTTON_PIN = 13;

// Sensor thresholds
constexpr uint16_t ACCIDENT_THRESHOLD = 150;
constexpr uint32_t SAMPLE_INTERVAL_MS = 10;   // 100 Hz sampling for impact detection
constexpr uint32_t CONFIRMATION_MS = 50;       // 50ms multi-sample persistence window
constexpr uint32_t CANCELLATION_MS = 15000;

// Button timing
constexpr uint32_t BUTTON_DEBOUNCE_MS = 50;
constexpr uint32_t SOS_LONG_PRESS_MS = 2500; // Hold button 2.5s for manual SOS

// BLE Configuration
constexpr char DEVICE_NAME[] = "SAFEHELM-0001";
constexpr char SERVICE_UUID[] = "7a01a8b4-4b1e-4a7c-9be5-6a1e9484bb01";
constexpr char EVENT_UUID[] = "7a01a8b4-4b1e-4a7c-9be5-6a1e9484bb02";

// Debug / Calibration
constexpr bool SAFEHELM_CALIBRATION = false;
}

