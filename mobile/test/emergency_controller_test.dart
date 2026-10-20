import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safehelm/models/contact.dart';
import 'package:safehelm/models/emergency.dart';
import 'package:safehelm/models/helmet_event.dart';
import 'package:safehelm/services/helmet_service.dart';
import 'package:safehelm/services/location_service.dart';
import 'package:safehelm/services/native_journal_service.dart';
import 'package:safehelm/services/sms_service.dart';
import 'package:safehelm/services/storage.dart';
import 'package:safehelm/state/emergency_controller.dart';

class FakeJournalService extends NativeJournalService {
  final List<String> ingested = [];
  final List<String> states = [];
  final List<String> locations = [];

  @override
  Future<bool> ingestIncident({
    required String incidentId,
    required String eventType,
    required int triggerTimestampMs,
    int countdownDurationMs = 15000,
    int totalRecipients = 0,
  }) async {
    ingested.add('$incidentId:$eventType');
    return true;
  }

  @override
  Future<bool> transitionState({
    required String incidentId,
    required String nextState,
  }) async {
    states.add('$incidentId:$nextState');
    return true;
  }

  @override
  Future<bool> updateLocation({
    required String incidentId,
    required double? latitude,
    required double? longitude,
    double? accuracy,
    String source = 'UNAVAILABLE',
    int? acquisitionTimeMs,
  }) async {
    locations.add('$incidentId:$latitude,$longitude');
    return true;
  }

  @override
  Future<List<NativeIncident>> getActiveIncidents() async => [];
}

class FakeHelmetService extends SimulatedHelmetService {
  String? cancelledEventId;

  @override
  Future<void> cancelAlert(String eventId) async {
    cancelledEventId = eventId;
  }
}

class FakeLocationService extends LocationService {
  @override
  Future<LocationResult> current() async {
    return const LocationResult(
      latitude: 19.0760,
      longitude: 72.8777,
      accuracy: 5.0,
      source: 'fake_gps',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmergencyController Tests', () {
    late Storage storage;
    late FakeJournalService journal;
    late FakeHelmetService helmet;
    late FakeLocationService location;
    late SmsService sms;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await Storage.create();
      journal = FakeJournalService();
      helmet = FakeHelmetService();
      location = FakeLocationService();
      sms = SmsService();
    });

    test('starts countdown and ingests incident to journal', () async {
      final controller = EmergencyController(
        storage,
        location,
        sms,
        journal: journal,
        helmet: helmet,
        countdownSeconds: 5,
      );

      final event = HelmetEvent(
        HelmetEventType.accident,
        eventId: 'SH-ACC-001',
      );

      await controller.start(event, test: true);

      expect(controller.state, EmergencyState.countdown);
      expect(controller.seconds, 5);
      expect(controller.currentIncidentId, 'SH-ACC-001');
      expect(journal.ingested, contains('SH-ACC-001:TEST_ALERT'));

      controller.dispose();
    });

    test('cancelling transitions state and sends cancelAlert to helmet', () async {
      final controller = EmergencyController(
        storage,
        location,
        sms,
        journal: journal,
        helmet: helmet,
        countdownSeconds: 5,
      );

      final event = HelmetEvent(
        HelmetEventType.accident,
        eventId: 'SH-ACC-002',
      );

      await controller.start(event, test: true);
      expect(controller.state, EmergencyState.countdown);

      await controller.cancel();

      expect(controller.state, EmergencyState.cancelled);
      expect(journal.states, contains('SH-ACC-002:CANCELLED'));
      expect(helmet.cancelledEventId, 'SH-ACC-002');

      final history = storage.history();
      expect(history.length, 1);
      expect(history.first.status, 'Cancelled');
      expect(history.first.locationSource, 'cancelled_by_rider');

      controller.dispose();
    });

    test('deduplicates identical event IDs', () async {
      final controller = EmergencyController(
        storage,
        location,
        sms,
        journal: journal,
        helmet: helmet,
        countdownSeconds: 5,
      );

      final event = HelmetEvent(
        HelmetEventType.accident,
        eventId: 'SH-ACC-003',
      );

      await controller.start(event, test: true);
      expect(controller.seconds, 5);

      // Attempt immediate duplicate
      await controller.start(event, test: true);
      expect(journal.ingested.where((s) => s.contains('SH-ACC-003')).length, 1);

      controller.dispose();
    });

    test('native incident model parsing', () {
      final map = {
        'incidentId': 'SH-REC-01',
        'eventType': 'ACCIDENT',
        'state': 'DISPATCHED',
        'triggerTimestampMs': 1700000000000,
        'countdownDurationMs': 15000,
        'latitude': 19.076,
        'longitude': 72.877,
        'locationAccuracy': 4.5,
        'locationSource': 'gps_fresh',
        'totalRecipients': 2,
        'successfulRecipients': 2,
        'createdAtMs': 1700000000000,
        'updatedAtMs': 1700000015000,
      };

      final inc = NativeIncident.fromMap(map);
      expect(inc.incidentId, 'SH-REC-01');
      expect(inc.state, 'DISPATCHED');
      expect(inc.latitude, 19.076);
      expect(inc.totalRecipients, 2);
    });
  });
}
