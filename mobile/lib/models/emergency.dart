enum EmergencyState { idle, countdown, cancelled, acquiringLocation, sending, requested, partialFailure, failed }

class EventRecord {
  const EventRecord({
    required this.type,
    required this.status,
    required this.time,
    required this.locationAvailable,
    required this.recipients,
    required this.locationSource,
    this.incidentId,
  });

  final String type, status, locationSource;
  final DateTime time;
  final bool locationAvailable;
  final int recipients;
  final String? incidentId;

  Map<String, dynamic> toJson() => {
        'type': type,
        'status': status,
        'time': time.toIso8601String(),
        'locationAvailable': locationAvailable,
        'recipients': recipients,
        'locationSource': locationSource,
        if (incidentId != null) 'incidentId': incidentId,
      };

  factory EventRecord.fromJson(Map<String, dynamic> j) => EventRecord(
        type: j['type'] as String,
        status: j['status'] as String,
        time: DateTime.parse(j['time'] as String),
        locationAvailable: j['locationAvailable'] as bool,
        recipients: j['recipients'] as int,
        locationSource: j['locationSource'] as String? ?? 'unknown',
        incidentId: j['incidentId'] as String?,
      );
}

class LocationResult {
  const LocationResult({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.timestamp,
    this.error,
    this.source = 'unavailable',
  });

  final double? latitude, longitude, accuracy;
  final DateTime? timestamp;
  final String? error, source;

  bool get available => latitude != null && longitude != null;
}
