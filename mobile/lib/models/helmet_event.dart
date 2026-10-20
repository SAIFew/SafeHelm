import 'dart:convert';
enum HelmetEventType { accident, manualSos, status, pong, unknown }
class HelmetEvent { const HelmetEvent(this.type,{this.eventId,this.deviceId,this.timestamp}); final HelmetEventType type; final String? eventId,deviceId; final int? timestamp; }
class BleMessageParser {
  static HelmetEvent? parse(String raw) { try { final m = _json(raw); if(m['version'] != 1 || m['type'] is! String) return null; final type={'ACCIDENT':HelmetEventType.accident,'MANUAL_SOS':HelmetEventType.manualSos,'STATUS':HelmetEventType.status,'PONG':HelmetEventType.pong}[m['type']]??HelmetEventType.unknown; if(type==HelmetEventType.unknown)return null; final emergency=type==HelmetEventType.accident||type==HelmetEventType.manualSos; if(emergency && (m['event_id'] is! String || (m['event_id'] as String).isEmpty || m['timestamp'] is! int)) return null; if(type==HelmetEventType.status && (m['device_id'] is! String || (m['device_id'] as String).isEmpty)) return null; return HelmetEvent(type,eventId:m['event_id'] as String?,deviceId:m['device_id'] as String?,timestamp:m['timestamp'] as int?); } catch(_) { return null; } }
  static Map<String,dynamic> _json(String input) => (jsonDecode(input) as Map).cast<String,dynamic>();
}
