# SafeHelm BLE protocol v1

The ESP32 advertises as `SAFEHELM-XXXX`. The mobile app filters that prefix before connecting.

| Item | UUID |
|---|---|
| Service | `7a01a8b4-4b1e-4a7c-9be5-6a1e9484bb01` |
| Event characteristic (Notify, Write) | `7a01a8b4-4b1e-4a7c-9be5-6a1e9484bb02` |

UTF-8 JSON is sent in a single GATT notification/write and must stay below 180 bytes. All messages have `version: 1` and `type`. Emergency messages additionally have a unique `event_id`.

```json
{"version":1,"type":"ACCIDENT","event_id":"a1b2c3d4","timestamp":123456}
{"version":1,"type":"MANUAL_SOS","event_id":"e5f6a7b8","timestamp":123456}
{"version":1,"type":"STATUS","device_id":"SAFEHELM-0001"}
{"version":1,"type":"ACK","event_id":"a1b2c3d4"}
{"version":1,"type":"PING"}
{"version":1,"type":"PONG"}
```

The phone immediately writes `ACK` for a valid `ACCIDENT` or `MANUAL_SOS`, including duplicates. It processes an event ID only once in a bounded recent-event cache. `timestamp` is required for an emergency event and is ESP32 uptime seconds—not wall-clock time—so the phone does not use it as a stale-event test. Unknown types, non-JSON payloads, missing fields and non-v1 messages are rejected without crashing. Firmware retries an unacknowledged emergency up to three times, 2 seconds apart. Battery is deliberately absent: no voltage measurement hardware has been specified.

The prototype GATT service is not encrypted or paired; do not represent it as secure. Production hardware should add BLE bonding and message authentication.
