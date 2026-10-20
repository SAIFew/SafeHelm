# Android Setup, Permissions & Architecture Guide

SafeHelm's mobile companion app is engineered for Android (targeting **Android SDK 35**, with backward compatibility to **Android 8.0 / API 26+**). It interfaces with the ESP32 helmet via Bluetooth Low Energy (BLE), tracks precise GPS telemetry, and coordinates autonomous emergency SMS dispatch.

---

## 🔒 Required Runtime Permissions

To respect user privacy and adhere to modern Android security models, all sensitive permissions are requested contextually with user explanations:

| Permission | Android API Level | Purpose | Justification |
|---|---|---|---|
| `android.permission.BLUETOOTH_SCAN` | API 31+ (Android 12+) | Discovers nearby SafeHelm BLE devices | Essential for helmet connection (`neverForLocation` flag where applicable). |
| `android.permission.BLUETOOTH_CONNECT` | API 31+ (Android 12+) | Maintains GATT connection and receives notifications | Required to stream telemetry and receive emergency events. |
| `android.permission.ACCESS_FINE_LOCATION` | All (API 26+) | High-precision GPS latitude and longitude | Attaches exact crash location coordinates to emergency SMS. |
| `android.permission.ACCESS_COARSE_LOCATION` | All (API 26+) | Fallback network location triangulation | Used if GPS fix is delayed or rider is indoors/tunnel. |
| `android.permission.SEND_SMS` | All (API 26+) | Autonomous emergency text message dispatch | Direct background SMS dispatch to saved emergency contacts. |

---

## 📲 Direct SMS Dispatch via `SmsManager`

SafeHelm utilizes the native Android `android.telephony.SmsManager` API:

```kotlin
// Native Android SmsManager dispatch snippet
val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    context.getSystemService(SmsManager::class.java)
} else {
    @Suppress("DEPRECATION")
    SmsManager.getDefault()
}

val parts = smsManager.divideMessage(emergencyMessage)
smsManager.sendMultipartTextMessage(contactNumber, null, parts, sentIntents, deliveryIntents)
```

### Production & Distribution Notes:
1. **Direct `SmsManager` vs SMS Intent**: The prototype sends SMS directly in the background without user intervention because the rider may be unconscious after a severe crash.
2. **Google Play Store Policy**: Google Play restricts apps using `SEND_SMS` unless granted a Core Functionality Exception under physical safety/emergency criteria. For development and field testing, direct APK sideloading works without restriction.
3. **Carrier Delivery Confirmation**: Dispatched SMS is queued at the radio baseband layer. While `SmsManager` confirms transmission from the device, network delivery depends on active cellular reception and carrier balance.

---

## 🔋 Background Execution & Battery Optimization

1. **BLE Background Throttling**: Stock Android restricts BLE scan intervals when an app is moved to the background. SafeHelm maintains active GATT subscriptions once paired.
2. **Foreground Service Recommendation**: In production builds, SafeHelm should run with a user-visible Foreground Service notification (`type="connectedDevice|location"`) to prevent Android's low-memory killer (OOM) from terminating the helmet link during long rides.
3. **Battery Saver Exemption**: For high-reliability testing, add SafeHelm to the OS "Unrestricted Battery" whitelist in system settings.
