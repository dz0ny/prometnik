import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Outcome of asking for location access.
enum LocationStatus {
  granted,

  /// The user declined the prompt; asking again may show it again (Android).
  denied,

  /// Declined for good (iOS after the first "no", Android "don't ask again"):
  /// only the app settings can turn it back on.
  deniedForever,

  /// Location services are off system-wide.
  serviceDisabled;

  /// Slovenian explanation for the UI, or null when access is granted.
  String? get message => switch (this) {
    LocationStatus.granted => null,
    LocationStatus.denied || LocationStatus.deniedForever =>
      'Dostop do lokacije je zavrnjen. Omogoči ga v nastavitvah.',
    LocationStatus.serviceDisabled => 'Lokacijske storitve so izklopljene.',
  };
}

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

  /// Ensures location services are on and permission is granted (while-in-use),
  /// prompting if the user has not decided yet. Says why when it isn't.
  Future<LocationStatus> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationStatus.serviceDisabled;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    switch (p) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationStatus.granted;
      case LocationPermission.deniedForever:
        return LocationStatus.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationStatus.denied;
    }
  }

  /// [requestPermission] as a yes/no.
  Future<bool> ensurePermission() async =>
      await requestPermission() == LocationStatus.granted;

  /// Opens the system screen that fixes [status]: app settings for a
  /// permanently denied permission, location settings when services are off.
  /// Returns false if nothing could be opened (or nothing needs fixing).
  Future<bool> openSettingsFor(LocationStatus status) async {
    try {
      switch (status) {
        case LocationStatus.deniedForever:
        case LocationStatus.denied:
          return await Geolocator.openAppSettings();
        case LocationStatus.serviceDisabled:
          return await Geolocator.openLocationSettings();
        case LocationStatus.granted:
          return false;
      }
    } catch (e) {
      // Web / unsupported platforms throw UnimplementedError (not Exception).
      debugPrint('openSettingsFor($status) failed: $e');
      return false;
    }
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
