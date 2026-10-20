import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'models/helmet_event.dart';
import 'services/helmet_service.dart';
import 'services/location_service.dart';
import 'services/sms_service.dart';
import 'services/storage.dart';
import 'state/emergency_controller.dart';
import 'ui/theme.dart';
import 'ui/screens/contacts_screen.dart';
import 'ui/screens/helmet_screen.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/profile_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/widgets/emergency_countdown_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.create();
  runApp(SafeHelmApp(storage));
}

class SafeHelmApp extends StatefulWidget {
  const SafeHelmApp(this.storage, {super.key});

  final Storage storage;

  @override
  State<SafeHelmApp> createState() => SafeHelmAppState();
}

class SafeHelmAppState extends State<SafeHelmApp> {
  late final HelmetService helmet = createHelmetService();
  late final EmergencyController emergency = EmergencyController(
    widget.storage,
    LocationService(),
    SmsService(),
    helmet: helmet,
  );

  HelmetConnection connection = HelmetConnection.disconnected;
  bool locationGranted = false;
  bool smsGranted = false;
  int currentPage = 0;

  @override
  void initState() {
    super.initState();
    _checkPermissions();

    // Listen to BLE connection changes
    helmet.connection.listen((conn) {
      if (mounted) setState(() => connection = conn);
    });

    // Listen to emergency events from the helmet
    helmet.events.listen((event) {
      if (event.type == HelmetEventType.accident ||
          event.type == HelmetEventType.manualSos) {
        emergency.start(event);
      } else if (event.type == HelmetEventType.cancel) {
        emergency.cancel(fromHelmet: true);
      }
    });

    emergency.addListener(() {
      if (mounted) setState(() {});
    });

    // Attempt recovery of any interrupted incidents and auto-reconnect to last known helmet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      emergency.recoverActiveIncidents();
      if (widget.storage.getLastHelmetId() != null) {
        helmet.reconnect(widget.storage);
      }
    });
  }

  Future<void> _checkPermissions() async {
    locationGranted = await Permission.locationWhenInUse.isGranted;
    smsGranted = await Permission.sms.isGranted;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeHelm',
      debugShowCheckedModeBanner: false,
      theme: SafeHelmTheme.darkTheme,
      home: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield, color: SafeHelmTheme.primaryLight, size: 22),
              const SizedBox(width: 8),
              const Text('SAFEHELM'),
            ],
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connection == HelmetConnection.connected
                        ? SafeHelmTheme.successGreen
                        : (connection == HelmetConnection.connecting ||
                                connection == HelmetConnection.scanning)
                            ? SafeHelmTheme.warningAmber
                            : SafeHelmTheme.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            IndexedStack(
              index: currentPage,
              children: [
                HomeScreen(
                  storage: widget.storage,
                  helmet: helmet,
                  emergency: emergency,
                  connection: connection,
                  locationGranted: locationGranted,
                  smsGranted: smsGranted,
                  onNavigateToTab: (index) => setState(() => currentPage = index),
                ),
                HelmetScreen(
                  service: helmet,
                  storage: widget.storage,
                  emergency: emergency,
                ),
                ContactsScreen(storage: widget.storage),
                ProfileScreen(storage: widget.storage),
                HistoryScreen(storage: widget.storage),
                SettingsScreen(
                  emergency: emergency,
                  locationGranted: locationGranted,
                  smsGranted: smsGranted,
                ),
              ],
            ),

            // Full-screen emergency countdown overlay with siren & cancel button
            EmergencyCountdownOverlay(emergency: emergency),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentPage,
          onDestinationSelected: (idx) => setState(() => currentPage = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.bluetooth_outlined),
              selectedIcon: Icon(Icons.bluetooth),
              label: 'Helmet',
            ),
            NavigationDestination(
              icon: Icon(Icons.contacts_outlined),
              selectedIcon: Icon(Icons.contacts),
              label: 'Contacts',
            ),
            NavigationDestination(
              icon: Icon(Icons.medical_information_outlined),
              selectedIcon: Icon(Icons.medical_information),
              label: 'Medical ID',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
