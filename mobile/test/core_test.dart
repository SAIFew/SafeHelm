import 'package:flutter_test/flutter_test.dart'; import 'package:safehelm/models/contact.dart'; import 'package:safehelm/models/helmet_event.dart'; import 'package:safehelm/services/sms_service.dart'; import 'package:safehelm/services/readiness.dart';
void main() {
  test('validates emergency contacts', () {
    expect(
      const EmergencyContact(name: 'Mom', phone: '+919999999999', enabled: true, priority: 1).isValid,
      true,
    );
    expect(
      const EmergencyContact(name: '', phone: 'x', enabled: true, priority: 1).isValid,
      false,
    );
  });

  test('rejects malformed and incomplete BLE', () {
    expect(BleMessageParser.parse('{'), isNull);
    expect(BleMessageParser.parse('{"version":1,"type":"ACCIDENT"}'), isNull);
    expect(
      BleMessageParser.parse('{"version":2,"type":"ACCIDENT","event_id":"x","timestamp":1}'),
      isNull,
    );
    expect(
      BleMessageParser.parse('{"version":1,"type":"MANUAL_SOS","event_id":"x","timestamp":1}')!.eventId,
      'x',
    );
  });

  test('builds explicit test message', () {
    expect(
      EmergencyMessageBuilder().build(
        type: 'TEST',
        time: DateTime(2026),
        latitude: null,
        longitude: null,
        test: true,
      ),
      contains('TEST ALERT — NOT AN EMERGENCY'),
    );
  });

  test('builds emergency message with last_known location note and rider info', () {
    final msg = EmergencyMessageBuilder().build(
      type: 'ACCIDENT',
      time: DateTime(2026, 10, 21, 10, 30),
      latitude: 19.0760,
      longitude: 72.8777,
      test: false,
      locationSource: 'last_known',
      riderName: 'Saif',
      bloodGroup: 'O+',
    );
    expect(msg, contains('SAFEHELM EMERGENCY ALERT'));
    expect(msg, contains('approximate last-known'));
    expect(msg, contains('Rider: Saif (Blood: O+)'));
    expect(msg, contains('https://maps.google.com/?q=19.076,72.8777'));
  });

  test('readiness exposes reasons', () {
    const r = Readiness(
      bluetooth: true,
      helmet: false,
      location: true,
      sms: true,
      contacts: false,
    );
    expect(r.ready, false);
    expect(r.reasons.length, 2);
  });
}


