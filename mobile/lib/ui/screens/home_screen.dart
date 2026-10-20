import 'package:flutter/material.dart';
import '../../models/emergency.dart';
import '../../services/helmet_service.dart';
import '../../services/readiness.dart';
import '../../services/storage.dart';
import '../../state/emergency_controller.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.storage,
    required this.helmet,
    required this.emergency,
    required this.connection,
    required this.locationGranted,
    required this.smsGranted,
    required this.onNavigateToTab,
    super.key,
  });

  final Storage storage;
  final HelmetService helmet;
  final EmergencyController emergency;
  final HelmetConnection connection;
  final bool locationGranted;
  final bool smsGranted;
  final ValueChanged<int> onNavigateToTab;

  void _showSosConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SafeHelmTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: SafeHelmTheme.emergencyRed),
            SizedBox(width: 8),
            Text('Trigger Manual SOS?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'This initiates the 15-second abort countdown and prepares autonomous emergency SMS dispatch to all enabled emergency contacts.',
          style: TextStyle(color: SafeHelmTheme.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: SafeHelmTheme.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SafeHelmTheme.emergencyRed),
            onPressed: () {
              Navigator.pop(dialogContext);
              emergency.manual();
            },
            child: const Text('Start SOS Countdown'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = storage.contacts().where((x) => x.enabled && x.isValid).toList();
    final readiness = Readiness(
      bluetooth: connection != HelmetConnection.error,
      helmet: connection == HelmetConnection.connected,
      location: locationGranted,
      sms: smsGranted,
      contacts: contacts.isNotEmpty,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Connection Status Hero Card
          _buildConnectionCard(context),

          const SizedBox(height: 16),

          // 2. Readiness Matrix Card
          _buildReadinessCard(context, readiness),

          const SizedBox(height: 16),

          // 3. Multi-Zone Sensor Overview Card
          _buildSensorZonesCard(context),

          const SizedBox(height: 24),

          // 4. Large Emergency SOS Button
          SizedBox(
            height: 72,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: SafeHelmTheme.emergencyRed,
                foregroundColor: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: () => _showSosConfirmation(context),
              icon: const Icon(Icons.emergency, size: 32),
              label: const Text(
                'EMERGENCY SOS',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hold helmet button 2.5s or tap SOS to trigger alert',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: SafeHelmTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(BuildContext context) {
    final isConnected = connection == HelmetConnection.connected;
    final isConnecting = connection == HelmetConnection.connecting || connection == HelmetConnection.scanning;
    final devName = helmet.connectedDeviceName ?? storage.getLastHelmetName() ?? 'SafeHelm Device';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isConnected) {
      statusColor = SafeHelmTheme.successGreen;
      statusLabel = 'PROTECTION ARMED';
      statusIcon = Icons.bluetooth_connected;
    } else if (isConnecting) {
      statusColor = SafeHelmTheme.warningAmber;
      statusLabel = 'CONNECTING...';
      statusIcon = Icons.bluetooth_searching;
    } else {
      statusColor = SafeHelmTheme.textMuted;
      statusLabel = 'DISCONNECTED';
      statusIcon = Icons.bluetooth_disabled;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 28),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          devName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          isConnected ? 'BLE GATT Link Active' : 'Standby / Disconnected',
                          style: const TextStyle(fontSize: 12, color: SafeHelmTheme.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: SafeHelmTheme.surfaceHighlight, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () => onNavigateToTab(1), // Go to Helmet Tab
                  icon: const Icon(Icons.settings_bluetooth, size: 18),
                  label: const Text('Manage Helmet'),
                ),
                if (!isConnected)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SafeHelmTheme.primaryLight,
                      side: const BorderSide(color: SafeHelmTheme.primary),
                    ),
                    onPressed: () => helmet.reconnect(storage),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Auto-Reconnect'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadinessCard(BuildContext context, Readiness r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SYSTEM READINESS',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (r.ready ? SafeHelmTheme.successGreen : SafeHelmTheme.warningAmber).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    r.ready ? 'ALL SYSTEMS GO' : 'ACTION NEEDED',
                    style: TextStyle(
                      color: r.ready ? SafeHelmTheme.successGreen : SafeHelmTheme.warningAmber,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildReadinessRow('Helmet BLE Link', r.helmet, 'Connected to ESP32 GATT server'),
            _buildReadinessRow('GPS Telematics', r.location, 'Location coordinates acquired for SMS'),
            _buildReadinessRow('Autonomous SMS Stack', r.sms, 'Android SMS manager permitted'),
            _buildReadinessRow('Emergency Contacts', r.contacts, '${storage.contacts().length}/5 contacts configured'),
          ],
        ),
      ),
    );
  }

  Widget _buildReadinessRow(String title, bool isReady, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            isReady ? Icons.check_circle : Icons.error_outline,
            color: isReady ? SafeHelmTheme.successGreen : SafeHelmTheme.warningAmber,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: SafeHelmTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorZonesCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.shield_outlined, color: SafeHelmTheme.primaryLight, size: 20),
                SizedBox(width: 8),
                Text(
                  'IMPACT SENSOR MATRIX',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Triangulated Force Sensitive Resistor zones with 2-of-3 majority voting and 15s dual abort cancellation:',
              style: TextStyle(fontSize: 12, color: SafeHelmTheme.textMuted),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildZonePill('Left Temporal', 'GPIO 36', Icons.arrow_back),
                const SizedBox(width: 8),
                _buildZonePill('Crown (Top)', 'GPIO 34', Icons.arrow_upward),
                const SizedBox(width: 8),
                _buildZonePill('Right Temporal', 'GPIO 39', Icons.arrow_forward),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZonePill(String name, String pin, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: SafeHelmTheme.surfaceHighlight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SafeHelmTheme.cardBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: SafeHelmTheme.primaryLight, size: 18),
            const SizedBox(height: 4),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            Text(
              pin,
              style: const TextStyle(fontSize: 10, color: SafeHelmTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
