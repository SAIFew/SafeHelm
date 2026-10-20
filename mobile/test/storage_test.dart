import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safehelm/models/contact.dart';
import 'package:safehelm/models/rider_profile.dart';
import 'package:safehelm/services/storage.dart';

void main() {
  test('contacts survive a storage reload', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await Storage.create();
    await first.saveContacts([
      const EmergencyContact(
        name: 'Mom',
        phone: '+919999999999',
        enabled: true,
        priority: 1,
      ),
    ]);
    final second = await Storage.create();
    expect(second.contacts().single.name, 'Mom');
    expect(second.contacts().single.phone, '+919999999999');
  });

  test('rider profile survives storage reload', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.create();

    const profile = RiderProfile(
      name: 'Saifuddin',
      bloodGroup: 'O+',
      allergies: 'Penicillin',
      medicalConditions: 'None',
      vehicleNumber: 'MH 04 AB 1234',
      emergencyNotes: 'Contact primary physician if unresponsive',
    );

    await storage.saveProfile(profile);

    final loaded = (await Storage.create()).getProfile();
    expect(loaded.name, 'Saifuddin');
    expect(loaded.bloodGroup, 'O+');
    expect(loaded.allergies, 'Penicillin');
    expect(loaded.vehicleNumber, 'MH 04 AB 1234');
    expect(loaded.isEmpty, false);
  });

  test('last helmet pairing survives storage reload for auto-reconnect', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.create();

    await storage.saveLastHelmet('AA:BB:CC:DD:EE:FF', 'SAFEHELM-0001');

    final loaded = await Storage.create();
    expect(loaded.getLastHelmetId(), 'AA:BB:CC:DD:EE:FF');
    expect(loaded.getLastHelmetName(), 'SAFEHELM-0001');

    await loaded.clearLastHelmet();
    expect(loaded.getLastHelmetId(), isNull);
  });
}
