import 'dart:convert';

enum HelmetEventType { accident, manualSos, cancel, status, pong, unknown }

class HelmetEvent {
  const HelmetEvent(this.type, {this.eventId, this.deviceId, this.timestamp});
  final HelmetEventType type;
  final String? eventId;
  final String? deviceId;
  final int? timestamp;
}

class BleMessageParser {
  static HelmetEvent? parse(String raw) {
    try {
      final m = _json(raw);
      if (m['version'] != 1 || m['type'] is! String) return null;

      final type = {
            'ACCIDENT': HelmetEventType.accident,
            'MANUAL_SOS': HelmetEventType.manualSos,
            'CANCEL': HelmetEventType.cancel,
            'STATUS': HelmetEventType.status,
            'PONG': HelmetEventType.pong,
          }[m['type']] ??
          HelmetEventType.unknown;

      if (type == HelmetEventType.unknown) return null;

      final isAlertOrCancel = type == HelmetEventType.accident ||
          type == HelmetEventType.manualSos ||
          type == HelmetEventType.cancel;

      if (isAlertOrCancel &&
          (m['event_id'] is! String || (m['event_id'] as String).isEmpty)) {
        return null;
      }

      if (type == HelmetEventType.status &&
          (m['device_id'] is! String || (m['device_id'] as String).isEmpty)) {
        return null;
      }

      return HelmetEvent(
        type,
        eventId: m['event_id'] as String?,
        deviceId: m['device_id'] as String?,
        timestamp: m['timestamp'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _json(String input) =>
      (jsonDecode(input) as Map).cast<String, dynamic>();
}
