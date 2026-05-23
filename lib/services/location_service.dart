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

  Future<Position?> current() async {
    if (!await ensurePermission()) return null;
    return Geolocator.getCurrentPosition();
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
