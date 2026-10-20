import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../state/emergency_controller.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.emergency,
    required this.locationGranted,
    required this.smsGranted,
    super.key,
  });

  final EmergencyController emergency;
  final bool locationGranted;
  final bool smsGranted;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // Permission Status Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.security, color: SafeHelmTheme.primaryLight, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'SYSTEM PERMISSIONS',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPermissionRow('Precise GPS Location', locationGranted),
                _buildPermissionRow('Direct Emergency SMS', smsGranted),
                _buildPermissionRow('Background Foreground Service', true),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Open Android App Settings'),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Test Simulation Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bug_report_outlined, color: SafeHelmTheme.warningAmber, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'SAFETY SIMULATION SANDBOX',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Fires an explicitly labelled test emergency alert without alarming emergency contacts or reporting a real crash.',
                  style: TextStyle(fontSize: 13, color: SafeHelmTheme.textMuted),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => emergency.manual(test: true),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run Test Alert Countdown'),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // About Card
        const Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: SafeHelmTheme.primaryLight, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'ABOUT SAFEHELM',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'SafeHelm v2.0 (Hardened Production Architecture)\n'
                  '• Embedded Platform: ESP32 FreeRTOS & NimBLE\n'
                  '• Telematics: Flutter 3.x with Android SDK 35\n'
                  '• Protocol: Custom JSON-GATT with 3-Stage Retransmission\n'
                  '• License: MIT Open Source',
                  style: TextStyle(fontSize: 13, color: SafeHelmTheme.textMuted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionRow(String title, bool granted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 13)),
          Row(
            children: [
              Icon(
                granted ? Icons.check_circle : Icons.error_outline,
                size: 16,
                color: granted ? SafeHelmTheme.successGreen : SafeHelmTheme.warningAmber,
              ),
              const SizedBox(width: 4),
              Text(
                granted ? 'Granted' : 'Missing',
                style: TextStyle(
                  fontSize: 12,
                  color: granted ? SafeHelmTheme.successGreen : SafeHelmTheme.warningAmber,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
