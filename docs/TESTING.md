# SafeHelm Testing & Quality Assurance Guide

Comprehensive testing guidelines for validating both the software layers and physical embedded hardware of SafeHelm.

---

## 🧪 1. Mobile Unit Testing

The mobile Flutter app includes automated unit test suites covering:
- **`contact_book_test.dart`**: Phone number normalization, E.164 parsing, duplicate handling, contact limits.
- **`core_test.dart`**: BLE wire protocol deserialization, corrupt payload rejection, event deduplication.
- **`storage_test.dart`**: Persistent state serialization and deserialization.

### Running Unit Tests
```bash
cd mobile
flutter test
```

Expected output:
```
00:02 +3: All tests passed!
```

---

## 🔬 2. Hardware-in-the-Loop & Bench Testing

Follow this step-by-step verification checklist on the bench before mounting hardware onto a helmet:

1. **Power & Bootloader**:
   - Connect the ESP32 to USB. Open Serial Monitor at `115200` baud.
   - Verify boot output indicates `SafeHelm BLE Server Active: SAFEHELM-XXXX`.

2. **BLE Discovery**:
   - Open the SafeHelm mobile app on an Android device with Bluetooth and Location enabled.
   - Tap **Scan for Helmets** and verify `SAFEHELM-XXXX` appears in the scan list.
   - Connect to the helmet. The connection indicator should change to connected green.

3. **Sensor Majority-Voting Verification**:
   - Squeeze **Sensor 1** alone. Verify the buzzer does *not* sound.
   - Squeeze **Sensor 2** alone. Verify no trigger.
   - Squeeze **Sensors 1 and 2** simultaneously with firm pressure.
   - Verify the 5V buzzer immediately begins pulsing the Stage 1 countdown alarm.

4. **Hardware Abort Verification**:
   - While the buzzer is pulsing, tap the **Tactile Button (GPIO 13)** once.
   - Verify the buzzer stops immediately and the ESP32 logs `Countdown Aborted`.

5. **End-to-End Emergency SMS Verification**:
   - Add a test contact with your own phone number in the SafeHelm app.
   - Trigger the dual-sensor impact on the bench.
   - Allow both the 15s helmet buzzer and the 15s phone screen countdown to expire without clicking cancel.
   - Verify your test phone receives the emergency text message containing:
     - Crash timestamp.
     - Lat/Lng coordinates.
     - Clickable Google Maps URL.
