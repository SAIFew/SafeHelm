# SafeHelm Architecture & Data Flow Specification

SafeHelm is divided into distinct, decoupled architectural layers ensuring deterministic behavior during emergencies:

```
[Hardware Sensor Array]
         │ (ADC Voltage Divider)
         ▼
[ESP32 Filter & Debounce Engine]
         │ (Majority Voting ≥ 2/3 sensors)
         ▼
[Hardware Countdown & Buzzer Controller]
         │ (BLE GATT Notification - UUID: 7a01a8b4-...)
         ▼
[Flutter BLE Client Layer]
         │ (Event Deduplication & Handshake ACK)
         ▼
[Emergency State Controller]
         │ (15s Visual/Audible Abort Window)
         ▼
[GPS Telematics Provider] ── (12s Timeout Budget)
         │
         ▼
[Message Assembly Engine]
         │
         ▼
[Android SmsManager Native Bridge]
         │ (GSM Baseband Dispatch)
         ▼
[Emergency Contacts]
```

---

## 🏗️ Architectural Layers

### 1. Embedded Layer (ESP32 / FreeRTOS)
- **`SensorMonitor`**: Continuously polls the 3 Force Sensitive Resistors (FSRs) using calibrated 8-bit ADC scaling. Applies exponential moving average (EMA) noise filtering to prevent false spikes caused by engine vibrations or helmet buffeting.
- **`Decision Engine`**: Requires **at least 2 of 3 sensors** to exceed `CRASH_THRESHOLD (150)` within a sliding window. Single-point pressure (e.g. thumb press or carrying the helmet) is discarded.
- **`BleServer`**: High-performance NimBLE stack advertising GATT service `7a01a8b4-4b1e-4a7c-9be5-6a1e9484bb01`. Manages notification delivery and listens for incoming ACKs.

### 2. Transport Layer (BLE GATT v1)
- Custom single-packet JSON protocol (< 180 bytes) optimized to avoid MTU fragmentation issues across various Android hardware chipsets.
- Bidirectional confirmation: The phone sends an `ACK` packet immediately upon receipt. If the helmet does not receive an ACK, it retries transmission up to 3 times spaced 2 seconds apart.

### 3. Mobile Telematics Layer (Flutter / Dart)
- **`HelmetService`**: Abstract interface decoupling physical Bluetooth from app logic.
  - `BleHelmetService`: Production implementation using `flutter_blue_plus`.
  - `SimulatedHelmetService`: Debug implementation for automated testing and demonstrations without hardware.
- **`EmergencyController`**: Central finite state machine (FSM). Coordinates timers, audio alarms, abort callbacks, and transitions:
  `IDLE ➔ HARDWARE_COUNTDOWN ➔ PHONE_COUNTDOWN ➔ LOCATING ➔ DISPATCHING ➔ COMPLETED / CANCELLED`.
- **`LocationService`**: Requests high-accuracy GPS with a strict 12-second timeout. If GPS fails or times out (e.g. underground parking), fallback coarse location or "Coordinates Unavailable" telemetry is used to ensure SMS dispatch is never blocked.
- **`ContactBook & Storage`**: Manages prioritized emergency contacts with local encrypted persistence via `shared_preferences`.

---

## 🛡️ Failure Path Handling & Resilience

| Scenario | System Behavior |
|---|---|
| **Invalid BLE packet / Corrupt JSON** | Parser catches format error and ignores frame; app does not crash. |
| **Duplicate Event ID Received** | Deduplicated via bounded recent-event cache; sends ACK back to helmet without triggering a second countdown. |
| **Helmet Disconnects During Ride** | Readiness status turns red; phone prompts rider with disconnect alert. |
| **GPS Fix Fails / Times Out** | Location service falls back to last known location or marks location as unavailable; emergency SMS dispatches regardless. |
| **No SIM / Airplane Mode Active** | SMS service catches platform exception and logs `SMS_FAILED` in local event audit log. |
