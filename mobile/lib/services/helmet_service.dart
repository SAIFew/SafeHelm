import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/protocol.dart';
import '../models/helmet_event.dart';

enum HelmetConnection { disconnected, scanning, connecting, connected, error }

abstract class HelmetService {
  Stream<HelmetConnection> get connection;
  Stream<HelmetEvent> get events;
  Future<List<ScanResult>> scan();
  Future<void> connect(ScanResult result);
  Future<void> disconnect();
}

class BleHelmetService implements HelmetService {
  final _connection = StreamController<HelmetConnection>.broadcast();
  final _events = StreamController<HelmetEvent>.broadcast();
  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;

  BleHelmetService() {
    FlutterBluePlus.adapterState.listen((s) {
      if (s != BluetoothAdapterState.on) {
        _connection.add(HelmetConnection.disconnected);
      }
    });
  }

  @override
  Stream<HelmetConnection> get connection => _connection.stream;

  @override
  Stream<HelmetEvent> get events => _events.stream;

  Future<int> _getAndroidSdkInt() async {
    if (!Platform.isAndroid) return 31;
    try {
      const channel = MethodChannel('safehelm/platform');
      final sdk = await channel.invokeMethod<int>('getSdkInt');
      if (sdk != null) return sdk;
    } catch (_) {}
    return 31;
  }

  Future<void> _checkScanPermissions() async {
    if (!Platform.isAndroid) return;
    final sdk = await _getAndroidSdkInt();
    if (sdk <= 30) {
      // Android 11 (API 30) and lower:
      // 1. Location Services (GPS) must be enabled for BLE scanning
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services must be enabled to scan for Bluetooth devices on Android 11');
      }
      // 2. Request ACCESS_FINE_LOCATION runtime permission required for BLE scan on Android 11
      final status = await Permission.location.request();
      if (!status.isGranted) {
        throw Exception('Location permission is required for Bluetooth scanning on Android 11');
      }
    } else {
      // Android 12+ (API 31+): BLUETOOTH_SCAN runtime permission
      if (!await Permission.bluetoothScan.request().isGranted) {
        throw Exception('Nearby devices scan permission is required');
      }
    }
  }

  Future<void> _checkConnectPermissions() async {
    if (!Platform.isAndroid) return;
    final sdk = await _getAndroidSdkInt();
    if (sdk >= 31) {
      // Android 12+ requires BLUETOOTH_CONNECT runtime permission
      if (!await Permission.bluetoothConnect.request().isGranted) {
        throw Exception('Nearby devices connection permission is required');
      }
    }
    // On Android 11 and lower, BLUETOOTH permission is granted at install time.
  }

  @override
  Future<List<ScanResult>> scan() async {
    await _checkScanPermissions();
    _connection.add(HelmetConnection.scanning);
    final results = <ScanResult>[];

    // Include already bonded/paired devices (e.g. if paired in Android Bluetooth settings)
    try {
      final bonded = await FlutterBluePlus.bondedDevices;
      for (final d in bonded) {
        final name = d.platformName.isNotEmpty ? d.platformName : d.advName;
        if (name.startsWith(safeHelmNamePrefix) &&
            !results.any((e) => e.device.remoteId == d.remoteId)) {
          results.add(ScanResult(
            device: d,
            advertisementData: AdvertisementData(
              advName: name,
              txPowerLevel: null,
              appearance: null,
              connectable: true,
              manufacturerData: const {},
              serviceData: const {},
              serviceUuids: [Guid(safeHelmServiceUuid)],
            ),
            rssi: 0,
            timeStamp: DateTime.now(),
          ));
        }
      }
    } catch (_) {}

    final sub = FlutterBluePlus.scanResults.listen((r) {
      for (final x in r) {
        final name = x.advertisementData.advName.isNotEmpty
            ? x.advertisementData.advName
            : (x.device.advName.isNotEmpty
                ? x.device.advName
                : x.device.platformName);
        final matchesName = name.startsWith(safeHelmNamePrefix);
        final matchesService = x.advertisementData.serviceUuids
            .contains(Guid(safeHelmServiceUuid));
        if ((matchesName || matchesService) &&
            !results.any((e) => e.device.remoteId == x.device.remoteId)) {
          results.add(x);
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
      );
      await Future<void>.delayed(const Duration(seconds: 8));
      return results;
    } finally {
      await FlutterBluePlus.stopScan();
      await sub.cancel();
      _connection.add(HelmetConnection.disconnected);
    }
  }

  @override
  Future<void> connect(ScanResult result) async {
    try {
      await _checkConnectPermissions();
      _connection.add(HelmetConnection.connecting);
      _device = result.device;
      await _device!.connect(timeout: const Duration(seconds: 12));
      _device!.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _connection.add(HelmetConnection.disconnected);
        }
      });
      try {
        await _device!.requestMtu(247);
      } catch (_) {}
      final services = await _device!.discoverServices();
      final service =
          services.where((s) => s.uuid == Guid(safeHelmServiceUuid)).firstOrNull;
      if (service == null) throw Exception('SafeHelm service was not found');
      _characteristic = service.characteristics
          .where((c) => c.uuid == Guid(safeHelmEventUuid))
          .firstOrNull;
      if (_characteristic == null) {
        throw Exception('SafeHelm event characteristic was not found');
      }
      await _characteristic!.setNotifyValue(true);
      _characteristic!.lastValueStream.listen((bytes) {
        final event = BleMessageParser.parse(
          utf8.decode(bytes, allowMalformed: true),
        );
        if (event == null) return;
        if (event.eventId != null) _ack(event.eventId!);
        _events.add(event);
      });
      _connection.add(HelmetConnection.connected);
    } catch (_) {
      _connection.add(HelmetConnection.error);
      rethrow;
    }
  }

  Future<void> _ack(String id) =>
      _characteristic?.write(
        utf8.encode(jsonEncode({'version': 1, 'type': 'ACK', 'event_id': id})),
        withoutResponse: false,
      ) ??
      Future.value();

  @override
  Future<void> disconnect() async {
    await _device?.disconnect();
    _connection.add(HelmetConnection.disconnected);
  }
}

class SimulatedHelmetService implements HelmetService {
  final _connection = StreamController<HelmetConnection>.broadcast();
  final _events = StreamController<HelmetEvent>.broadcast();
  @override
  Stream<HelmetConnection> get connection => _connection.stream;
  @override
  Stream<HelmetEvent> get events => _events.stream;
  @override
  Future<List<ScanResult>> scan() async => [];
  @override
  Future<void> connect(ScanResult r) async =>
      _connection.add(HelmetConnection.connected);
  @override
  Future<void> disconnect() async =>
      _connection.add(HelmetConnection.disconnected);
  void simulate(HelmetEvent e) => _events.add(e);
}

// Real BLE is the default in both debug and release builds. The simulator is only
// reachable when a developer explicitly injects SimulatedHelmetService in a test.
HelmetService createHelmetService() => BleHelmetService();