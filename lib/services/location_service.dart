import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Thin wrapper around geolocator for permission + position access.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// Whether permission is already granted (without prompting).
  Future<bool> hasPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  /// Ensures location services are on and permission is granted (while-in-use).
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  /// Current fix, or the last known one if no fix arrives in time (indoors,
  /// tunnels) or location services were switched off meanwhile.
  Future<Position?> current() async {
    if (!await ensurePermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on Exception catch (e) {
      debugPrint('getCurrentPosition failed: $e');
      try {
        return await Geolocator.getLastKnownPosition();
      } on Exception {
        return null;
      }
    }
  }

  /// Position updates while the app is in use (every ~200 m of movement).
  Stream<Position> stream() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 200,
    ),
  );

  double distanceMeters(double lat1, double lon1, double lat2, double lon2) =>
      Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
}
