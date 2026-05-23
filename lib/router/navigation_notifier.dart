import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Coordinates cross-tab navigation requests (e.g. "show this station on the
/// map") between screens and the main scaffold.
class NavigationNotifier extends ChangeNotifier {
  int? _pendingStationOnMap;
  LatLng? _pendingLocationOnMap;

  int? get pendingStationOnMap => _pendingStationOnMap;
  LatLng? get pendingLocationOnMap => _pendingLocationOnMap;

  /// Request switching to the map tab and focusing the given station.
  void showStationOnMap(int stationId) {
    _pendingStationOnMap = stationId;
    notifyListeners();
  }

  void clearPendingStation() {
    _pendingStationOnMap = null;
  }

  /// Request switching to the map tab and centring on an arbitrary location
  /// (e.g. a traffic event).
  void showLocationOnMap(LatLng location) {
    _pendingLocationOnMap = location;
    notifyListeners();
  }

  void clearPendingLocation() {
    _pendingLocationOnMap = null;
  }
}
