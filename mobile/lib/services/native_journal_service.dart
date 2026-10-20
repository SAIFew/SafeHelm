import 'package:flutter/services.dart';

class NativeIncident {
  const NativeIncident({
    required this.incidentId,
    required this.eventType,
    required this.state,
    required this.triggerTimestampMs,
    required this.countdownDurationMs,
    this.cancelledTimestampMs,
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    this.locationTimestampMs,
    this.locationSource,
    required this.totalRecipients,
    required this.successfulRecipients,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String incidentId;
  final String eventType;
  final String state;
  final int triggerTimestampMs;
  final int countdownDurationMs;
  final int? cancelledTimestampMs;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracy;
  final int? locationTimestampMs;
  final String? locationSource;
  final int totalRecipients;
  final int successfulRecipients;
  final int createdAtMs;
  final int updatedAtMs;

  factory NativeIncident.fromMap(Map<dynamic, dynamic> map) {
    return NativeIncident(
      incidentId: map['incidentId'] as String? ?? '',
      eventType: map['eventType'] as String? ?? 'ACCIDENT',
      state: map['state'] as String? ?? 'UNKNOWN',
      triggerTimestampMs: (map['triggerTimestampMs'] as num?)?.toInt() ?? 0,
      countdownDurationMs: (map['countdownDurationMs'] as num?)?.toInt() ?? 15000,
      cancelledTimestampMs: (map['cancelledTimestampMs'] as num?)?.toInt(),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      locationAccuracy: (map['locationAccuracy'] as num?)?.toDouble(),
      locationTimestampMs: (map['locationTimestampMs'] as num?)?.toInt(),
      locationSource: map['locationSource'] as String?,
      totalRecipients: (map['totalRecipients'] as num?)?.toInt() ?? 0,
      successfulRecipients: (map['successfulRecipients'] as num?)?.toInt() ?? 0,
      createdAtMs: (map['createdAtMs'] as num?)?.toInt() ?? 0,
      updatedAtMs: (map['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class NativeDispatch {
  const NativeDispatch({
    required this.dispatchId,
    required this.incidentId,
    required this.recipientPhone,
    this.recipientName,
    required this.messageBody,
    required this.status,
    this.radioResultCode,
    required this.retryCount,
    required this.lastAttemptMs,
    required this.partsTotal,
    required this.partsConfirmed,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String dispatchId;
  final String incidentId;
  final String recipientPhone;
  final String? recipientName;
  final String messageBody;
  final String status;
  final int? radioResultCode;
  final int retryCount;
  final int lastAttemptMs;
  final int partsTotal;
  final int partsConfirmed;
  final int createdAtMs;
  final int updatedAtMs;

  factory NativeDispatch.fromMap(Map<dynamic, dynamic> map) {
    return NativeDispatch(
      dispatchId: map['dispatchId'] as String? ?? '',
      incidentId: map['incidentId'] as String? ?? '',
      recipientPhone: map['recipientPhone'] as String? ?? '',
      recipientName: map['recipientName'] as String?,
      messageBody: map['messageBody'] as String? ?? '',
      status: map['status'] as String? ?? 'PENDING',
      radioResultCode: (map['radioResultCode'] as num?)?.toInt(),
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      lastAttemptMs: (map['lastAttemptMs'] as num?)?.toInt() ?? 0,
      partsTotal: (map['partsTotal'] as num?)?.toInt() ?? 1,
      partsConfirmed: (map['partsConfirmed'] as num?)?.toInt() ?? 0,
      createdAtMs: (map['createdAtMs'] as num?)?.toInt() ?? 0,
      updatedAtMs: (map['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class NativeJournalService {
  static const _channel = MethodChannel('safehelm/journal');

  Future<bool> ingestIncident({
    required String incidentId,
    required String eventType,
    required int triggerTimestampMs,
    int countdownDurationMs = 15000,
    int totalRecipients = 0,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('ingestIncident', {
        'incidentId': incidentId,
        'eventType': eventType,
        'triggerTimestampMs': triggerTimestampMs,
        'countdownDurationMs': countdownDurationMs,
        'totalRecipients': totalRecipients,
      });
      return res != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> transitionState({
    required String incidentId,
    required String nextState,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('transitionState', {
        'incidentId': incidentId,
        'nextState': nextState,
      });
      return res?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateLocation({
    required String incidentId,
    required double? latitude,
    required double? longitude,
    double? accuracy,
    String source = 'UNAVAILABLE',
    int? acquisitionTimeMs,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('updateLocation', {
        'incidentId': incidentId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'source': source,
        'acquisitionTimeMs': acquisitionTimeMs ?? DateTime.now().millisecondsSinceEpoch,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<NativeIncident>> getActiveIncidents() async {
    try {
      final list = await _channel.invokeListMethod<dynamic>('getActiveIncidents');
      if (list == null) return [];
      return list.whereType<Map>().map((m) => NativeIncident.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<NativeIncident>> getAllIncidents() async {
    try {
      final list = await _channel.invokeListMethod<dynamic>('getAllIncidents');
      if (list == null) return [];
      return list.whereType<Map>().map((m) => NativeIncident.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<NativeDispatch>> getDispatches(String incidentId) async {
    try {
      final list = await _channel.invokeListMethod<dynamic>('getDispatches', {
        'incidentId': incidentId,
      });
      if (list == null) return [];
      return list.whereType<Map>().map((m) => NativeDispatch.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }
}
