import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact.dart';
import '../models/emergency.dart';
import '../models/rider_profile.dart';

class Storage {
  Storage(this._prefs);
  final SharedPreferences _prefs;

  static Future<Storage> create() async =>
      Storage(await SharedPreferences.getInstance());

  List<EmergencyContact> contacts() =>
      ((_prefs.getStringList('contacts') ?? [])
          .map((s) => EmergencyContact.fromJson(
              (jsonDecode(s) as Map).cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => a.priority.compareTo(b.priority)));

  Future<void> saveContacts(List<EmergencyContact> v) =>
      _prefs.setStringList('contacts', v.map((c) => jsonEncode(c.toJson())).toList());

  List<EventRecord> history() => ((_prefs.getStringList('history') ?? [])
      .map((s) => EventRecord.fromJson(
          (jsonDecode(s) as Map).cast<String, dynamic>()))
      .toList());

  Future<void> addEvent(EventRecord r) async {
    final items = history()..insert(0, r);
    await _prefs.setStringList(
        'history', items.take(100).map((e) => jsonEncode(e.toJson())).toList());
  }

  Future<void> clearHistory() => _prefs.remove('history');

  bool get onboarded => _prefs.getBool('onboarded') ?? false;
  Future<void> finishOnboarding() => _prefs.setBool('onboarded', true);

  // Rider Profile
  RiderProfile getProfile() {
    final raw = _prefs.getString('rider_profile');
    if (raw == null || raw.isEmpty) return const RiderProfile();
    try {
      return RiderProfile.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return const RiderProfile();
    }
  }

  Future<void> saveProfile(RiderProfile profile) =>
      _prefs.setString('rider_profile', jsonEncode(profile.toJson()));

  // Last paired helmet memory for auto-reconnect
  String? getLastHelmetId() => _prefs.getString('last_helmet_id');
  String? getLastHelmetName() => _prefs.getString('last_helmet_name');

  Future<void> saveLastHelmet(String id, String name) async {
    await _prefs.setString('last_helmet_id', id);
    await _prefs.setString('last_helmet_name', name);
  }

  Future<void> clearLastHelmet() async {
    await _prefs.remove('last_helmet_id');
    await _prefs.remove('last_helmet_name');
  }
}
