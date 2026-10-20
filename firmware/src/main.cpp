#include <Arduino.h>
#include <Preferences.h>
#include "Config.h"
#include "SensorMonitor.h"
#include "BleServer.h"

// ============================================================
// SAFEHELM FIRMWARE (MODULAR V2)
// ============================================================

static SensorMonitor sensors;
static BleServer ble;
static Preferences prefs;

// NVS Monotonic counters
static uint32_t bootCount = 0;
static uint32_t eventSeq = 0;

// State tracking
enum class SystemState {
  IDLE,
  ACCIDENT_COUNTDOWN,
  ACCIDENT_LOCKED
};

static SystemState state = SystemState::IDLE;
static unsigned long countdownStartTime = 0;
static String activeEventId = "";

// Buzzer pattern generator (non-blocking)
enum class BuzzerMode {
  SILENT,
  PULSING_COUNTDOWN,
  CHIRP_CANCEL,
  CHIRP_SOS
};

static BuzzerMode buzzerMode = BuzzerMode::SILENT;
static unsigned long buzzerPatternStart = 0;

void setBuzzerMode(BuzzerMode mode) {
  buzzerMode = mode;
  buzzerPatternStart = millis();
  if (mode == BuzzerMode::SILENT) {
    digitalWrite(Config::BUZZER_PIN, LOW);
  }
}

void updateBuzzer() {
  unsigned long now = millis();
  unsigned long elapsed = now - buzzerPatternStart;

  switch (buzzerMode) {
    case BuzzerMode::SILENT:
      digitalWrite(Config::BUZZER_PIN, LOW);
      break;

    case BuzzerMode::PULSING_COUNTDOWN: {
      // Accelerating acoustic pulse as countdown approaches 0
      // 0-5s elapsed: 1 Hz (100ms on, 900ms off)
      // 5-10s elapsed: 2 Hz (100ms on, 400ms off)
      // 10-15s elapsed: 4 Hz rapid urgent pulse (100ms on, 150ms off)
      unsigned long cycle = 1000;
      if (elapsed > 10000) {
        cycle = 250;
      } else if (elapsed > 5000) {
        cycle = 500;
      }
      unsigned long phase = elapsed % cycle;
      digitalWrite(Config::BUZZER_PIN, (phase < 100) ? HIGH : LOW);
      break;
    }

    case BuzzerMode::CHIRP_CANCEL: {
      // Double chirp: 80ms ON, 60ms OFF, 80ms ON, then silent
      if (elapsed < 80) {
        digitalWrite(Config::BUZZER_PIN, HIGH);
      } else if (elapsed < 140) {
        digitalWrite(Config::BUZZER_PIN, LOW);
      } else if (elapsed < 220) {
        digitalWrite(Config::BUZZER_PIN, HIGH);
      } else {
        digitalWrite(Config::BUZZER_PIN, LOW);
        buzzerMode = BuzzerMode::SILENT;
      }
      break;
    }

    case BuzzerMode::CHIRP_SOS: {
      // Triple urgent beep: 3x (120ms ON, 80ms OFF)
      if (elapsed < 120 || (elapsed >= 200 && elapsed < 320) || (elapsed >= 400 && elapsed < 520)) {
        digitalWrite(Config::BUZZER_PIN, HIGH);
      } else if (elapsed >= 520) {
        digitalWrite(Config::BUZZER_PIN, LOW);
        buzzerMode = BuzzerMode::SILENT;
      } else {
        digitalWrite(Config::BUZZER_PIN, LOW);
      }
      break;
    }
  }
}

// ============================================================
// Event ID Generator (Monotonic & Persistent)
// ============================================================
String generateEventId() {
  eventSeq++;
  prefs.putUInt("seq", eventSeq);

  uint64_t chipId = ESP.getEfuseMac();
  uint16_t mac4 = (uint16_t)(chipId & 0xFFFF);

  char buffer[32];
  snprintf(buffer, sizeof(buffer), "%04X-%u-%lu", mac4, (unsigned int)bootCount, (unsigned long)eventSeq);
  return String(buffer);
}

// ============================================================
// Button Debounce & Long-Press SOS Handler
// ============================================================
static unsigned long buttonPressStart = 0;
static bool buttonWasDown = false;
static bool sosTriggeredForCurrentPress = false;

void handleButton() {
  bool isDown = (digitalRead(Config::MANUAL_BUTTON_PIN) == LOW);
  unsigned long now = millis();

  if (isDown) {
    if (!buttonWasDown) {
      // Just pressed
      buttonPressStart = now;
      buttonWasDown = true;
      sosTriggeredForCurrentPress = false;
    } else {
      // Held down
      unsigned long duration = now - buttonPressStart;

      // In IDLE state, a 2.5s hold triggers MANUAL SOS
      if (state == SystemState::IDLE && !sosTriggeredForCurrentPress && duration >= Config::SOS_LONG_PRESS_MS) {
        sosTriggeredForCurrentPress = true;
        setBuzzerMode(BuzzerMode::CHIRP_SOS);

        activeEventId = generateEventId();
        Serial.println();
        Serial.println("========================================");
        Serial.printf("MANUAL SOS TRIGGERED (Event: %s)\n", activeEventId.c_str());
        Serial.println("========================================");
        Serial.println();

        ble.sendEmergency("MANUAL_SOS", activeEventId);
      }
    }
  } else {
    // Released
    if (buttonWasDown) {
      unsigned long duration = now - buttonPressStart;
      buttonWasDown = false;

      // Short press (> debounce ms and not already handled as long press)
      if (duration >= Config::BUTTON_DEBOUNCE_MS && !sosTriggeredForCurrentPress) {
        if (state == SystemState::ACCIDENT_COUNTDOWN) {
          // CANCEL COUNTDOWN
          state = SystemState::IDLE;
          setBuzzerMode(BuzzerMode::CHIRP_CANCEL);
          sensors.clear();
          ble.sendEmergency("CANCEL", activeEventId);

          Serial.println();
          Serial.println("========================================");
          Serial.println("ACCIDENT CANCELLED BY HELMET BUTTON");
          Serial.println("Countdown aborted. Notified companion app.");
          Serial.println("========================================");
          Serial.println();
        }
      }
    }
  }
}

// ============================================================
// Setup
// ============================================================
void setup() {
  Serial.begin(115200);

  // Hardware Pins
  pinMode(Config::BUZZER_PIN, OUTPUT);
  digitalWrite(Config::BUZZER_PIN, LOW);
  pinMode(Config::MANUAL_BUTTON_PIN, INPUT_PULLUP);

  // NVS Setup for monotonic IDs
  prefs.begin("safehelm", false);
  bootCount = prefs.getUInt("boot", 0) + 1;
  prefs.putUInt("boot", bootCount);
  eventSeq = prefs.getUInt("seq", 0);

  // Initialize sensors and BLE
  sensors.begin();
  ble.begin();

  Serial.println();
  Serial.println("========================================");
  Serial.println("SAFEHELM HARDENED FIRMWARE READY");
  Serial.printf("Device: %s (Boot #%u, LastSeq #%lu)\n",
                Config::DEVICE_NAME, bootCount, (unsigned long)eventSeq);
  Serial.println("========================================");
  Serial.println();
}

// ============================================================
// Main Loop
// ============================================================
void loop() {
  unsigned long now = millis();

  // 1. Update sensors
  sensors.update();

  // 2. Handle button (cancel / SOS)
  handleButton();

  // 3. Handle remote cancel from companion phone over BLE
  if (ble.isCancelRequested() && state == SystemState::ACCIDENT_COUNTDOWN) {
    state = SystemState::IDLE;
    setBuzzerMode(BuzzerMode::CHIRP_CANCEL);
    sensors.clear();
    Serial.println();
    Serial.println("========================================");
    Serial.println("ACCIDENT CANCELLED REMOTELY BY PHONE APP");
    Serial.println("Countdown aborted. System returned to IDLE.");
    Serial.println("========================================");
    Serial.println();
  }

  // 4. Retry unacknowledged BLE emergency packets (3x every 2s)
  ble.retry();

  // 5. Update buzzer pattern
  updateBuzzer();

  // 6. State Machine
  switch (state) {
    case SystemState::IDLE: {
      if (sensors.confirmed()) {
        state = SystemState::ACCIDENT_COUNTDOWN;
        countdownStartTime = now;
        activeEventId = generateEventId();
        setBuzzerMode(BuzzerMode::PULSING_COUNTDOWN);

        // UNIFIED COUNTDOWN: Notify companion phone IMMEDIATELY upon crash confirmation
        ble.sendEmergency("ACCIDENT", activeEventId);

        Serial.println();
        Serial.println("========================================");
        Serial.println("CRASH CONDITION CONFIRMED (2+ FSRs > 150)");
        Serial.printf("STARTING UNIFIED 15-SECOND COUNTDOWN (Event: %s)\n", activeEventId.c_str());
        Serial.println("Press helmet button or cancel in companion app.");
        Serial.println("========================================");
        Serial.println();
      }
      break;
    }

    case SystemState::ACCIDENT_COUNTDOWN: {
      if (now - countdownStartTime >= Config::CANCELLATION_MS) {
        // 15 seconds elapsed without rider aborting on either device
        state = SystemState::ACCIDENT_LOCKED;
        setBuzzerMode(BuzzerMode::SILENT);

        Serial.println();
        Serial.println("========================================");
        Serial.printf("COUNTDOWN EXPIRED (Event: %s)\n", activeEventId.c_str());
        Serial.println("System locked. Companion phone dispatches emergency alerts.");
        Serial.println("========================================");
        Serial.println();
      }
      break;
    }

    case SystemState::ACCIDENT_LOCKED: {
      // Re-arm only after force sensors return below threshold
      if (sensors.belowThreshold()) {
        state = SystemState::IDLE;
        sensors.clear();
        Serial.println("[SAFEHELM] Sensors returned to normal. System re-armed.");
      }
      break;
    }
  }


  // Debug output every 500ms
  static unsigned long lastDebugTime = 0;
  if (now - lastDebugTime >= 500) {
    lastDebugTime = now;
    uint16_t l, r, c;
    sensors.getValues(l, r, c);
    Serial.printf("[STATUS] L:%u R:%u C:%u | Trig:%u | State:%d | BLE:%s | Ack:%s\n",
                  l, r, c,
                  sensors.getTriggeredCount(),
                  (int)state,
                  ble.isConnected() ? "CONNECTED" : "ADVERTISING",
                  ble.acknowledged() ? "YES" : "WAITING");
  }

  delay(10);
}