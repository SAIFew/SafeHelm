import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../models/helmet_event.dart';
import '../../services/helmet_service.dart';
import '../../services/storage.dart';
import '../../state/emergency_controller.dart';
import '../theme.dart';

class HelmetScreen extends StatefulWidget {
  const HelmetScreen({
    required this.service,
    required this.storage,
    required this.emergency,
    super.key,
  });

  final HelmetService service;
  final Storage storage;
  final EmergencyController emergency;

  @override
  State<HelmetScreen> createState() => _HelmetScreenState();
}

class _HelmetScreenState extends State<HelmetScreen> {
  bool _isScanning = false;
  String _scanStatus = 'Ready to scan for nearby SafeHelm helmets';
  List<ScanResult> _devices = [];

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _scanStatus = 'Scanning for BLE devices advertising SAFEHELM-* ...';
      _devices = [];
    });
    try {
      final results = await widget.service.scan();
      setState(() {
        _devices = results;
        _isScanning = false;
        _scanStatus = results.isEmpty
            ? 'No SafeHelm helmets discovered. Make sure ESP32 is powered on.'
            : 'Found ${results.length} SafeHelm device(s)';
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _scanStatus = 'Scan error: $e';
      });
    }
  }

  Future<void> _connect(ScanResult result) async {
    setState(() => _scanStatus = 'Connecting to ${result.device.platformName}...');
    try {
      await widget.service.connect(result, storage: widget.storage);
      setState(() => _scanStatus = 'Connected to ${result.device.platformName}');
    } catch (e) {
      setState(() => _scanStatus = 'Connection failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final devName = widget.service.connectedDeviceName ?? widget.storage.getLastHelmetName();

    return StreamBuilder<HelmetConnection>(
      stream: widget.service.connection,
      initialData: widget.service.connectedDeviceName != null
          ? HelmetConnection.connected
          : HelmetConnection.disconnected,
      builder: (context, snapshot) {
        final conn = snapshot.data ?? HelmetConnection.disconnected;
        final isConnected = conn == HelmetConnection.connected;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero Status Card
              Card(
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
                              Icon(
                                isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                                color: isConnected ? SafeHelmTheme.successGreen : SafeHelmTheme.primaryLight,
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isConnected ? (devName ?? 'SafeHelm Connected') : 'Helmet Disconnected',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (isConnected ? SafeHelmTheme.successGreen : SafeHelmTheme.warningAmber)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              conn.name.toUpperCase(),
                              style: TextStyle(
                                color: isConnected ? SafeHelmTheme.successGreen : SafeHelmTheme.warningAmber,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isConnected
                            ? 'NimBLE GATT Server connected over ATT MTU 247 with bidirectional ACK confirmation.'
                            : _scanStatus,
                        style: const TextStyle(fontSize: 13, color: SafeHelmTheme.textMuted, height: 1.3),
                      ),
                      const SizedBox(height: 16),
                      if (isConnected)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SafeHelmTheme.emergencyRed,
                            side: const BorderSide(color: SafeHelmTheme.emergencyRed),
                          ),
                          onPressed: widget.service.disconnect,
                          icon: const Icon(Icons.link_off),
                          label: const Text('Disconnect Helmet'),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _isScanning ? null : _startScan,
                                icon: _isScanning
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.radar),
                                label: Text(_isScanning ? 'Scanning...' : 'Scan for Helmet'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton.outlined(
                              tooltip: 'Auto-reconnect to last known helmet',
                              onPressed: () => widget.service.reconnect(widget.storage),
                              icon: const Icon(Icons.sync),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Discovered Devices Section
              if (!isConnected && _devices.isNotEmpty) ...[
                const Text(
                  'DISCOVERED DEVICES',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final d = _devices[index];
                    final name = d.advertisementData.advName.isNotEmpty
                        ? d.advertisementData.advName
                        : (d.device.platformName.isNotEmpty ? d.device.platformName : 'SAFEHELM-DEVICE');
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth, color: SafeHelmTheme.primaryLight),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('RSSI: ${d.rssi} dBm • ID: ${d.device.remoteId.str}'),
                        trailing: FilledButton.tonal(
                          onPressed: () => _connect(d),
                          child: const Text('Connect'),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Hardware Simulation & Diagnostics Sandbox Card
              Card(
                color: SafeHelmTheme.surfaceHighlight,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.science_outlined, color: SafeHelmTheme.primaryLight, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'SIMULATION & BENCH TESTING',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Allows testing the mobile audio siren, vibration, and SMS dispatch flow safely without physical crash sensors:',
                        style: TextStyle(fontSize: 12, color: SafeHelmTheme.textMuted),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: SafeHelmTheme.emergencyRed),
                                foregroundColor: SafeHelmTheme.emergencyRed,
                              ),
                              onPressed: () {
                                widget.emergency.start(
                                  HelmetEvent(
                                    HelmetEventType.accident,
                                    eventId: 'sim-${DateTime.now().millisecondsSinceEpoch}',
                                  ),
                                  test: true,
                                );
                              },
                              child: const Text('Demo Crash'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: SafeHelmTheme.warningAmber),
                                foregroundColor: SafeHelmTheme.warningAmber,
                              ),
                              onPressed: () => widget.emergency.manual(test: true),
                              child: const Text('Demo SOS'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
