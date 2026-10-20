# SafeHelm Diagnostic & Troubleshooting Guide

Common issues, diagnostic checklists, and resolution steps for hardware and mobile integration.

---

## 🔍 Diagnostic Checklist

### 1. ESP32 Not Appearing in Mobile App Scan
- **Check Power**: Ensure the ESP32 power LED is lit and stable. If using a battery, check that output voltage is ≥ 4.5V into `VIN`.
- **Verify Serial Logs**: Connect to PC via USB, open Serial Monitor at `115200` baud. Check if the firmware boots and reports BLE initialization.
- **Android Permissions**: On Android 12+, ensure **Nearby devices** permission is granted. On Android 11 and below, ensure **Location** services are toggled ON.
- **BLE Name Prefix**: The mobile app filters devices with the prefix `SAFEHELM-`. If the prefix was changed in firmware `Config.h`, ensure the app filter matches.

---

### 2. False Crash Triggers or Sensors Too Sensitive
- **Threshold Calibration**: Open `firmware/src/Config.h` and check `CRASH_THRESHOLD`. Default is `150`. If mechanical vibration causes triggers, increase the threshold to `175` or `200`.
- **Pull-down Resistor Check**: Verify each FSR has a physical 1kΩ pull-down resistor to GND. Without a pull-down resistor, the high-impedance ADC pin will float and register random spikes.
- **Majority Voting**: Ensure `#define REQUIRED_SENSORS 2` is enabled so a single bumped sensor never initiates an emergency countdown.

---

### 3. Buzzer Doesn't Sound or Sounds Weak
- **Driver Transistor**: Verify the 2N2222A NPN pinout (Emitter to GND, Base to GPIO12 via 1kΩ resistor, Collector to Buzzer Negative).
- **Flyback Diode Polarity**: The 1N4007 diode band (cathode) must connect to `+5V` and anode to the collector. If reversed, it shorts the 5V rail to ground whenever GPIO12 is driven high.
- **Buzzer Type**: SafeHelm uses an **active** buzzer (contains internal oscillator, sounds continuously with DC voltage applied). If using a passive buzzer, it requires a PWM square wave signal.

---

### 4. SMS Not Received by Emergency Contacts
- **SIM Card & Carrier**: Confirm the phone has an active SIM card, cellular carrier signal, and balance to send SMS.
- **Runtime Permissions**: Ensure **Send SMS** permission is granted in Android system settings.
- **Phone Number Format**: Use standard international E.164 formatting with country code (e.g. `+1234567890` or `+919876543210`).
- **GPS Coordinates**: If GPS times out (e.g. testing indoors), the app will still dispatch an SMS stating "Location unavailable" rather than failing.
