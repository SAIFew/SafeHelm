import 'package:geolocator/geolocator.dart';
import '../models/emergency.dart';

class LocationService {
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(error: 'Location services are disabled', source: 'disabled');
      }

      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        return const LocationResult(error: 'Location permission is unavailable', source: 'denied');
      }
    } catch (_) {
      return const LocationResult(error: 'Location services unavailable', source: 'unavailable');
    }

    // 1. First Tier: High-precision fresh GPS fix (up to 12 seconds)
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationResult(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        timestamp: pos.timestamp,
        source: 'gps_fresh',
      );
    } catch (_) {}

    // 2. Second Tier: Fallback to hardware-cached last-known position
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return LocationResult(
          latitude: last.latitude,
          longitude: last.longitude,
          accuracy: last.accuracy,
          timestamp: last.timestamp,
          source: 'last_known',
        );
      }
    } catch (_) {}

    // 3. Third Tier: Medium-accuracy network/cell tower fix (5s quick budget)
    try {
      final networkPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return LocationResult(
        latitude: networkPos.latitude,
        longitude: networkPos.longitude,
        accuracy: networkPos.accuracy,
        timestamp: networkPos.timestamp,
        source: 'network_approximate',
      );
    } catch (_) {}

    return const LocationResult(
      error: 'Current location timed out or is unavailable',
      source: 'unavailable',
    );
  }
}
