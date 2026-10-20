import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../models/emergency.dart';
import '../models/helmet_event.dart';
import '../services/alarm_service.dart';
import '../services/helmet_service.dart';
import '../services/location_service.dart';
import '../services/native_journal_service.dart';
import '../services/sms_service.dart';
import '../services/storage.dart';

class EmergencyController extends ChangeNotifier {
  EmergencyController(
    this.storage,
    this.location,
    this.sms, {
    NativeJournalService? journal,
    this.helmet,
    this.countdownSeconds = 15,
  }) : journal = journal ?? NativeJournalService() {
    _initRadioListener();
  }

  final Storage storage;
  final LocationService location;
  final SmsService sms;
  final NativeJournalService journal;
  HelmetService? helmet;
  final int countdownSeconds;
  final _seen = <String>[];

  EmergencyState state = EmergencyState.idle;
  int seconds = 0;
  String? kind;
  String? currentIncidentId;
  Timer? _timer;
  int _run = 0;
  Future<LocationResult>? _prewarmedLocationFuture;
  StreamSubscription? _radioSub;

  bool get _active =>
      state == EmergencyState.countdown ||
      state == EmergencyState.acquiringLocation ||
      state == EmergencyState.sending;

  void setHelmetService(HelmetService s) {
    helmet = s;
  }

  void _initRadioListener() {
    try {
      _radioSub = sms.radioStatusStream.listen((event) {
        debugPrint('[SafeHelm Radio Status] $event');
      }, onError: (err) {
        debugPrint('[SafeHelm Radio Stream Error] $err');
      });
    } catch (_) {}
  }

  Future<void> recoverActiveIncidents() async {
    try {
      final active = await journal.getActiveIncidents();
      if (active.isNotEmpty) {
        debugPrint('[SafeHelm Recovery] Found ${active.length} active/interrupted incident(s) in journal');
        for (final inc in active) {
          if (inc.state == 'COUNTDOWN' || inc.state == 'LOCATION_ACQUIRED') {
            await journal.transitionState(
              incidentId: inc.incidentId,
              nextState: 'FAILED',
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<void> start(HelmetEvent e, {bool test = false}) async {
    final id = e.eventId ?? 'SH-${DateTime.now().millisecondsSinceEpoch}';
    if (_seen.contains(id) || _active) return;
    _seen.add(id);
    if (_seen.length > 100) _seen.removeAt(0);

    _timer?.cancel();
    final run = ++_run;
    currentIncidentId = id;
    kind = test
        ? 'TEST ALERT'
        : (e.type == HelmetEventType.accident ? 'ACCIDENT' : 'MANUAL SOS');
    state = EmergencyState.countdown;
    seconds = countdownSeconds;
    notifyListeners();

    // 1. Ingest incident into persistent SQLite journal before doing asynchronous work
    final enabledContacts = storage.contacts().where((c) => c.enabled && c.isValid).toList();
    unawaited(journal.ingestIncident(
      incidentId: id,
      eventType: test ? 'TEST_ALERT' : (e.type == HelmetEventType.accident ? 'ACCIDENT' : 'MANUAL_SOS'),
      triggerTimestampMs: DateTime.now().millisecondsSinceEpoch,
      countdownDurationMs: countdownSeconds * 1000,
      totalRecipients: enabledContacts.length,
    ));

    // 2. Pre-warm location acquisition in background so it is ready when countdown expires
    _prewarmedLocationFuture = location.current();

    // 3. Trigger high-priority audio alarm and vibration for real emergencies
    if (!test) {
      unawaited(AlarmService.startAlarm());
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (run != _run) {
        t.cancel();
        return;
      }
      seconds--;
      notifyListeners();
      if (seconds <= 0) {
        t.cancel();
        _dispatch(test, run, id);
      }
    });
  }

  Future<void> manual({bool test = false}) => start(
        HelmetEvent(HelmetEventType.manualSos, eventId: 'SH-MAN-${DateTime.now().millisecondsSinceEpoch}'),
        test: test,
      );

  Future<void> cancel({bool fromHelmet = false}) async {
    if (state != EmergencyState.countdown) return;
    _run++;
    _timer?.cancel();
    _prewarmedLocationFuture = null;
    unawaited(AlarmService.stopAlarm());

    final cancelledId = currentIncidentId;

    // Send cancel event to helmet over BLE if cancelled from phone
    if (!fromHelmet && helmet != null && cancelledId != null) {
      unawaited(helmet?.cancelAlert(cancelledId));
    }

    // Persist CANCELLED state to SQLite journal
    if (cancelledId != null) {
      unawaited(journal.transitionState(
        incidentId: cancelledId,
        nextState: 'CANCELLED',
      ));
    }

    state = EmergencyState.cancelled;
    notifyListeners();

    await storage.addEvent(EventRecord(
      type: kind ?? 'Alert',
      status: 'Cancelled',
      time: DateTime.now(),
      locationAvailable: false,
      recipients: 0,
      locationSource: fromHelmet ? 'cancelled_by_helmet' : 'cancelled_by_rider',
      incidentId: cancelledId,
    ));
  }

  Future<void> _dispatch(bool test, int run, String incidentId) async {
    if (run != _run) return;
    state = EmergencyState.acquiringLocation;
    notifyListeners();

    final loc = await (_prewarmedLocationFuture ?? location.current());
    if (run != _run) return;

    // Persist location fix to SQLite journal
    await journal.updateLocation(
      incidentId: incidentId,
      latitude: loc.latitude,
      longitude: loc.longitude,
      accuracy: loc.accuracy,
      source: loc.source ?? 'unavailable',
      acquisitionTimeMs: loc.timestamp?.millisecondsSinceEpoch,
    );

    // Transition journal state to DISPATCHING
    await journal.transitionState(
      incidentId: incidentId,
      nextState: 'DISPATCHING',
    );

    state = EmergencyState.sending;
    notifyListeners();

    final contacts = storage
        .contacts()
        .where((c) => c.enabled && c.isValid)
        .toList();
    final permitted = await Permission.sms.request().isGranted;
    var ok = 0;

    if (permitted && contacts.isNotEmpty) {
      final profile = storage.getProfile();
      final body = EmergencyMessageBuilder().build(
        type: kind ?? 'Emergency',
        time: DateTime.now(),
        latitude: loc.latitude,
        longitude: loc.longitude,
        test: test,
        locationSource: loc.source,
        riderName: profile.name,
        bloodGroup: profile.bloodGroup,
      );

      for (final c in contacts) {
        if (run != _run) break;
        final res = await sms.send(
          c.phone,
          body,
          incidentId: incidentId,
          contactName: c.name,
        );
        if (res.accepted) ok++;
      }
    }

    if (run != _run) return;
    unawaited(AlarmService.stopAlarm());

    final finalJournalState = (ok == contacts.length && ok > 0)
        ? 'DISPATCHED'
        : (ok > 0 ? 'PARTIAL_FAILURE' : 'FAILED');

    await journal.transitionState(
      incidentId: incidentId,
      nextState: finalJournalState,
    );

    state = (ok == contacts.length && ok > 0)
        ? EmergencyState.requested
        : (ok > 0 ? EmergencyState.partialFailure : EmergencyState.failed);

    await storage.addEvent(EventRecord(
      type: kind ?? 'Emergency',
      status: state.name,
      time: DateTime.now(),
      locationAvailable: loc.available,
      recipients: ok,
      locationSource: loc.source ?? 'unavailable',
      incidentId: incidentId,
    ));

    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _radioSub?.cancel();
    unawaited(AlarmService.stopAlarm());
    super.dispose();
  }
}

