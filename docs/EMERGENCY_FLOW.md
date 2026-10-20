# SafeHelm Emergency Flow & Timeout Budget

SafeHelm employs a deterministic multi-stage emergency pipeline engineered to balance **rapid response during incapacitation** against **zero false alerts for conscious riders**.

---

## ⏱️ Timeline & State Machine

```
Time (t)     Event / Stage                                     Actor / Target
─────────────────────────────────────────────────────────────────────────────
t = 0.0s     Severe impact detected (≥ 2 FSRs ≥ 150)           ESP32 Firmware
             State transitions to COUNTDOWN_HELMET
             Active buzzer begins pulsing alarm pattern

t = 0 - 15s  Stage 1: Helmet Hardware Abort Window            Rider
             • If rider short-presses button (GPIO 13):
               Countdown is CANCELLED, buzzer stops, state returns to IDLE.

t = 15.0s    Stage 1 completes without abort                   ESP32 Firmware
             Firmware dispatches `ACCIDENT` packet via BLE
             Firmware awaits BLE `ACK` (retries up to 3 times)

t = 15.2s    App receives `ACCIDENT`, immediately transmits `ACK` Phone / App
             App verifies event ID is fresh (deduplication)
             State transitions to COUNTDOWN_PHONE
             Phone sounds loud audio alarm and displays full-screen modal

t = 15 - 30s Stage 2: Smartphone UI Abort Window               Rider / App
             • If rider taps "Cancel Emergency" on phone screen:
               Alert is CANCELLED. Event logged locally. No SMS sent.

t = 30.0s    Stage 2 completes without abort                   Phone / App
             State transitions to ACQUIRING_LOCATION
             GPS provider requested with 12s hard timeout budget

t = 30 - 42s High-precision GPS lock acquired                  Location Engine
             (If GPS fix succeeds or 12s expires, proceed immediately)

t = 42.0s    Message Construction & Dispatch                   Telematics Engine
             • Builds concise emergency SMS text with coordinates & Google Maps link
             • Iterates through active emergency contacts in local contact book
             • Invokes native Android SmsManager stack

t = 42.5s    Dispatch Complete                                 Audit Log
             • Status recorded: SUCCESS, PARTIAL, or FAILED
             • Rider app returns to MONITORING state with alert confirmation banner
─────────────────────────────────────────────────────────────────────────────
Total budget from crash to dispatch: Maximum 42.5 seconds (or instant + 27s for manual SOS).
```

---

## 🆘 Manual SOS Bypass
When the rider feels unsafe or requires roadside medical assistance:
- **Trigger**: Short-pressing the helmet button when the system is in `IDLE` state.
- **Bypass**: Bypasses the 15-second Stage 1 helmet countdown and immediately dispatches `MANUAL_SOS` over BLE.
- The phone receives the event and initiates the 15-second visual countdown on screen before dispatching SMS.
