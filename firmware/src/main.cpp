#include <Arduino.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>

// ============================================================
// SAFEHELM ACCIDENT DETECTION FIRMWARE
// ============================================================

// -------------------------
// Hardware pins
// -------------------------
static const int FSR1_PIN = 36;
static const int FSR2_PIN = 39;
static const int FSR3_PIN = 34;

static const int BUZZER_PIN = 12;
static const int BUTTON_PIN = 13;

// -------------------------
// Accident configuration
// -------------------------
static const int FSR_THRESHOLD = 150;

// Accident condition must remain valid for 300 ms
static const unsigned long CONFIRM_TIME_MS = 300;

// Rider has 15 seconds to cancel
static const unsigned long CANCEL_TIME_MS = 15000;

// -------------------------
// BLE configuration
// -------------------------
static const char* DEVICE_NAME = "SAFEHELM-0001";

static const char* SERVICE_UUID =
    "7a01a8b4-4b1e-4a7c-9be5-6a1e9484bb01";

static const char* CHARACTERISTIC_UUID =
    "7a01a8b4-4b1e-4a7c-9be5-6a1e9484bb02";

NimBLECharacteristic* eventCharacteristic = nullptr;

// ============================================================
// State
// ============================================================

// True while the 15-second cancellation window is running.
bool accidentPending = false;

// True after an accident has been sent/confirmed.
// System will not trigger again until sensors are released.
bool accidentLocked = false;

// Time at which the 2-of-3 condition first became valid.
unsigned long conditionStartTime = 0;

// Time at which the 15-second cancellation window started.
unsigned long accidentStartTime = 0;

// Event ID of the current accident.
String currentEventId = "";

// ============================================================
// Read FSR sensors
// ============================================================

int readTriggeredSensors(int& v1, int& v2, int& v3) {

    v1 = analogRead(FSR1_PIN);
    v2 = analogRead(FSR2_PIN);
    v3 = analogRead(FSR3_PIN);

    int triggered = 0;

    if (v1 > FSR_THRESHOLD) {
        triggered++;
    }

    if (v2 > FSR_THRESHOLD) {
        triggered++;
    }

    if (v3 > FSR_THRESHOLD) {
        triggered++;
    }

    return triggered;
}

// ============================================================
// Create unique event ID
// ============================================================

String createEventId() {

    uint64_t chipId = ESP.getEfuseMac();

    char buffer[40];

    snprintf(
        buffer,
        sizeof(buffer),
        "%08lX-%lu",
        (unsigned long)(chipId & 0xFFFFFFFFULL),
        (unsigned long)millis()
    );

    return String(buffer);
}

// ============================================================
// Send ACCIDENT BLE notification
// ============================================================

void sendAccidentEvent() {

    if (eventCharacteristic == nullptr) {

        Serial.println("BLE ERROR: characteristic unavailable");

        return;
    }

    currentEventId = createEventId();

    StaticJsonDocument<256> document;

    document["version"] = 1;
    document["type"] = "ACCIDENT";
    document["event_id"] = currentEventId;

    // ESP32 uptime timestamp.
    // The Android application uses the phone/GPS time for the
    // actual emergency message.
    document["timestamp"] = (unsigned long)millis();

    String payload;

    serializeJson(document, payload);

    // Store the complete JSON in the characteristic.
    eventCharacteristic->setValue(payload);

    // Send exactly one notification for this accident.
    eventCharacteristic->notify();

    Serial.println();
    Serial.println("================================");
    Serial.println("BLE ACCIDENT EVENT SENT");
    Serial.println(payload);
    Serial.println("================================");
    Serial.println();
}

// ============================================================
// BLE setup
// ============================================================

void setupBLE() {

    Serial.println();
    Serial.println("Starting SafeHelm BLE...");

    NimBLEDevice::init(DEVICE_NAME);

    // Important:
    // Android previously received only the first ~20 bytes when
    // the default ATT MTU was used.
    //
    // Request/use a larger MTU so the complete JSON notification
    // can be delivered.
    NimBLEDevice::setMTU(247);

    NimBLEServer* server = NimBLEDevice::createServer();

    NimBLEService* service =
        server->createService(SERVICE_UUID);

    eventCharacteristic =
        service->createCharacteristic(
            CHARACTERISTIC_UUID,
            NIMBLE_PROPERTY::READ |
            NIMBLE_PROPERTY::WRITE |
            NIMBLE_PROPERTY::NOTIFY
        );

    // Initial value.
    eventCharacteristic->setValue("{}");

    service->start();

    NimBLEAdvertising* advertising =
        NimBLEDevice::getAdvertising();

    advertising->addServiceUUID(SERVICE_UUID);

    // Allow the phone to see the device name in scan response.
    advertising->setScanResponse(true);

    NimBLEDevice::startAdvertising();

    Serial.println("BLE READY");
    Serial.print("Device: ");
    Serial.println(DEVICE_NAME);

    Serial.print("Service UUID: ");
    Serial.println(SERVICE_UUID);

    Serial.print("Characteristic UUID: ");
    Serial.println(CHARACTERISTIC_UUID);

    Serial.println("BLE ADVERTISING");
    Serial.println();
}

// ============================================================
// Setup
// ============================================================

void setup() {

    Serial.begin(115200);

    // Buzzer OFF at startup.
    pinMode(BUZZER_PIN, OUTPUT);
    digitalWrite(BUZZER_PIN, LOW);

    // Cancel button:
    // pressed = LOW
    pinMode(BUTTON_PIN, INPUT_PULLUP);

    // ESP32 ADC resolution.
    analogReadResolution(12);

    Serial.println();
    Serial.println("================================");
    Serial.println("SAFEHELM ACCIDENT SYSTEM");
    Serial.println("================================");

    Serial.println("FSR1 = GPIO36");
    Serial.println("FSR2 = GPIO39");
    Serial.println("FSR3 = GPIO34");
    Serial.println("BUZZER = GPIO12");
    Serial.println("BUTTON = GPIO13");

    Serial.print("FSR threshold = ");
    Serial.println(FSR_THRESHOLD);

    Serial.print("Confirmation time = ");
    Serial.print(CONFIRM_TIME_MS);
    Serial.println(" ms");

    Serial.print("Cancellation time = ");
    Serial.print(CANCEL_TIME_MS);
    Serial.println(" ms");

    setupBLE();

    Serial.println("SYSTEM READY");
    Serial.println();
}

// ============================================================
// Main loop
// ============================================================

void loop() {

    int v1;
    int v2;
    int v3;

    int triggered =
        readTriggeredSensors(v1, v2, v3);

    unsigned long now = millis();

    // ========================================================
    // NORMAL STATE
    // ========================================================

    if (!accidentPending && !accidentLocked) {

        digitalWrite(BUZZER_PIN, LOW);

        // At least 2 of the 3 FSRs must exceed threshold.
        if (triggered >= 2) {

            // Start persistence timer.
            if (conditionStartTime == 0) {

                conditionStartTime = now;

                Serial.println(
                    "ACCIDENT CONDITION DETECTED"
                );
            }

            // Condition remained valid for 300 ms.
            else if (
                now - conditionStartTime >=
                CONFIRM_TIME_MS
            ) {

                accidentPending = true;

                accidentStartTime = now;

                digitalWrite(BUZZER_PIN, HIGH);

                Serial.println();
                Serial.println("================================");
                Serial.println("ACCIDENT CONDITION CONFIRMED");
                Serial.println("15 SECOND CANCEL PERIOD STARTED");
                Serial.println("PRESS BUTTON TO CANCEL");
                Serial.println("================================");

                // IMPORTANT:
                // DO NOT send BLE yet.
                //
                // BLE emergency notification is sent ONLY
                // after the complete 15-second cancellation
                // period expires.
            }
        }

        else {

            // Condition disappeared before 300 ms.
            conditionStartTime = 0;
        }
    }

    // ========================================================
    // ACCIDENT PENDING
    // ========================================================

    if (accidentPending) {

        // Keep buzzer ON throughout the 15-second window.
        digitalWrite(BUZZER_PIN, HIGH);

        // ----------------------------------------------------
        // CANCEL BUTTON
        // ----------------------------------------------------

        if (digitalRead(BUTTON_PIN) == LOW) {

            accidentPending = false;

            accidentLocked = false;

            conditionStartTime = 0;

            digitalWrite(BUZZER_PIN, LOW);

            Serial.println();
            Serial.println("================================");
            Serial.println("ACCIDENT CANCELLED BY BUTTON");
            Serial.println("SYSTEM RETURNED TO NORMAL");
            Serial.println("================================");
            Serial.println();
        }

        // ----------------------------------------------------
        // 15 SECONDS EXPIRED
        // ----------------------------------------------------

        else if (
            now - accidentStartTime >=
            CANCEL_TIME_MS
        ) {

            // Stop buzzer.
            digitalWrite(BUZZER_PIN, LOW);

            // Leave pending state.
            accidentPending = false;

            // Lock until sensors are released.
            accidentLocked = true;

            Serial.println();
            Serial.println("================================");
            Serial.println("ACCIDENT CONFIRMED");
            Serial.println("15 SECOND PERIOD EXPIRED");
            Serial.println("SENDING BLE EMERGENCY EVENT");
            Serial.println("================================");

            // THIS is the important mobile-alert command.
            sendAccidentEvent();
        }
    }

    // ========================================================
    // ACCIDENT LOCK / RE-ARM
    // ========================================================

    if (accidentLocked) {

        // Do not allow another event while 2+ sensors
        // are still above threshold.
        if (triggered < 2) {

            accidentLocked = false;

            conditionStartTime = 0;

            Serial.println("SYSTEM RE-ARMED");
            Serial.println();
        }
    }

    // ========================================================
    // DEBUG OUTPUT
    // ========================================================

    static unsigned long lastDebugTime = 0;

    if (now - lastDebugTime >= 250) {

        lastDebugTime = now;

        Serial.print("FSR1=");
        Serial.print(v1);

        Serial.print("  FSR2=");
        Serial.print(v2);

        Serial.print("  FSR3=");
        Serial.print(v3);

        Serial.print("  TRIGGERED=");
        Serial.print(triggered);

        Serial.print("  PENDING=");
        Serial.print(accidentPending ? 1 : 0);

        Serial.print("  LOCKED=");
        Serial.println(accidentLocked ? 1 : 0);
    }

    // Non-blocking sensor loop.
    delay(20);
}