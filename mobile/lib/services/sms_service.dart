import 'package:flutter/services.dart';

class SmsDispatch {
  const SmsDispatch(
    this.accepted,
    this.message, {
    this.status = 'UNKNOWN',
    this.dispatchId,
    this.parts = 1,
  });

  final bool accepted;
  final String message;
  final String status;
  final String? dispatchId;
  final int parts;
}

class SmsService {
  static const _channel = MethodChannel('safehelm/sms');
  static const _events = EventChannel('safehelm/sms_events');

  Stream<Map<String, dynamic>>? _radioStream;

  Stream<Map<String, dynamic>> get radioStatusStream {
    _radioStream ??= _events
        .receiveBroadcastStream()
        .map((event) => (event as Map).cast<String, dynamic>());
    return _radioStream!;
  }

  Future<SmsDispatch> send(
    String phone,
    String body, {
    String? incidentId,
    String? contactName,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('sendSms', {
        'phone': phone,
        'body': body,
        'incidentId': incidentId,
        'contactName': contactName,
      });

      final accepted = res?['accepted'] as bool? ?? false;
      final status = res?['status'] as String? ?? (accepted ? 'SUBMITTED_TO_RIL' : 'FAILED');
      final dispatchId = res?['dispatchId'] as String?;
      final parts = res?['parts'] as int? ?? 1;

      return SmsDispatch(
        accepted,
        accepted ? 'Submitted to Android telephony radio' : 'Android SMS system rejected request',
        status: status,
        dispatchId: dispatchId,
        parts: parts,
      );
    } on PlatformException catch (e) {
      return SmsDispatch(
        false,
        e.message ?? 'SMS unavailable',
        status: 'FAILED',
      );
    }
  }
}

class EmergencyMessageBuilder {
  String build({
    required String type,
    required DateTime time,
    required double? latitude,
    required double? longitude,
    required bool test,
    String? locationSource,
    String? riderName,
    String? bloodGroup,
  }) {
    String loc;
    if (latitude == null || longitude == null) {
      loc = 'Current location unavailable';
    } else {
      final note = (locationSource == 'last_known') ? ' (approximate last-known)' : '';
      loc = '$latitude, $longitude$note\nMap: https://maps.google.com/?q=$latitude,$longitude';
    }

    final header = test ? 'TEST ALERT — NOT AN EMERGENCY' : 'SAFEHELM EMERGENCY ALERT';
    final riderInfo = (riderName != null && riderName.isNotEmpty)
        ? '\nRider: $riderName${(bloodGroup != null && bloodGroup.isNotEmpty) ? ' (Blood: $bloodGroup)' : ''}'
        : '';

    return '$header\n$type detected. Please contact the rider immediately.$riderInfo\nLocation: $loc\nTime: ${time.toLocal()}';
  }
}
