# Hardware, Circuitry & Sensor Calibration Guide

SafeHelm combines sensitive force sensors with an ESP32 microcontroller, protected audio circuitry, and tactile inputs to create a reliable crash-sensing helmet.

---

## ⚡ Pinout Mapping (`firmware/src/Config.h`)

| Pin / Label | MCU Pin | Type | Connected Component | Circuit Configuration |
|---|---|---|---|---|
| **FSR 1** | GPIO 36 (`VP`) | ADC1_CH0 | Left Temporal Force Sensor | 3.3V ➔ FSR ➔ Node ➔ 1kΩ ➔ GND |
| **FSR 2** | GPIO 39 (`VN`) | ADC1_CH3 | Right Temporal Force Sensor | 3.3V ➔ FSR ➔ Node ➔ 1kΩ ➔ GND |
| **FSR 3** | GPIO 34 (`D34`) | ADC1_CH6 | Crown / Front Force Sensor | 3.3V ➔ FSR ➔ Node ➔ 1kΩ ➔ GND |
| **Buzzer Out** | GPIO 12 | Digital Out | 5V Active Buzzer Driver | 1kΩ Resistor to 2N2222A Base |
| **SOS Button** | GPIO 13 | Digital In | Tactile Pushbutton (Abort/SOS) | Internal `INPUT_PULLUP` to GND |
| **Common Ground**| GND | Power | All Sensors, Transistor Emitter | Shared common ground rail |
| **MCU Power** | VIN / 5V | Power | USB or 5V Power Supply | Regulated 5V rail |

> **IMPORTANT**: Pins GPIO 34, 36, and 39 are input-only ADC1 channels on the ESP32 and do not have internal pull-up/pull-down resistors. External 1kΩ pull-down resistors are required as specified below.

---

## 📐 Circuit Design & Wiring Schematics

### 1. FSR Voltage Divider
```
3.3V ────[ FSR (Force Sensitive Resistor) ]────┬──── GPIO 36/39/34 (ADC)
                                               │
                                             [1kΩ]
                                               │
                                              GND
```
- **Unpressed**: Resistance is > 1MΩ. ADC reads ~0V (`0–20` digital value).
- **Hard Impact**: Resistance drops to < 200Ω. ADC reads > 2.8V (`220–245` digital value).

---

### 2. Buzzer Transistor Driver with Flyback Protection
An active 5V buzzer draws up to 30–50mA, exceeding the safe 12mA current limit of ESP32 GPIO pins. A 2N2222A NPN transistor is used as an open-collector low-side switch:

```
                  +5V (VIN)
                     │
         ┌───────────┴───────────┐
         │                       │
     [ Buzzer + ]           [ 1N4007 Diode ]
     [ Buzzer - ]          (Cathode to +5V,
         │                  Anode to Collector)
         ├───────────────────────┘
         │
      Collector (C)
GPIO 12 ──[1kΩ]── Base (B)  [2N2222A NPN]
      Emitter (E)
         │
        GND
```

> **CRITICAL**: The **1N4007 flyback diode** is required. The buzzer coil produces large reverse inductive spikes when switched off that can destroy the 2N2222A transistor or cause brownouts on the ESP32.

---

### 3. Tactile Abort / SOS Pushbutton
```
GPIO 13 ────[ Pushbutton ]──── GND
```
- Uses ESP32 `pinMode(GPIO13, INPUT_PULLUP)`.
- When released: Pin reads `HIGH`.
- When pressed: Pin reads `LOW`.
- **Dual Function**:
  - During a countdown: Short press immediately **aborts** the emergency alert.
  - While idle: Short press immediately triggers a **manual emergency SOS**.

---

## 🎛️ Sensor Calibration Procedure

1. Set `#define SAFEHELM_CALIBRATION 1` in `Config.h`.
2. Open Serial Monitor at **115200 baud**.
3. Observe live output:
   ```
   [CALIB] FSR1: 12 | FSR2: 8 | FSR3: 15 | Filtered: [11, 9, 14] -> State: IDLE
   ```
4. Squeeze each sensor individually. Verify single-sensor pressure does not exceed the count threshold.
5. Apply firm dual-point pressure. Verify both sensors cross `CRASH_THRESHOLD (150)` and the countdown triggers.
