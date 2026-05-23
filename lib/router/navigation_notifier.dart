import 'package:flutter/foundation.dart';

/// Coordinates cross-tab navigation requests (e.g. "show this station on the
/// map") between screens and the main scaffold.
class NavigationNotifier extends ChangeNotifier {
  int? _pendingStationOnMap;

  int? get pendingStationOnMap => _pendingStationOnMap;

  /// Request switching to the map tab and focusing the given station.
  void showStationOnMap(int stationId) {
    _pendingStationOnMap = stationId;
    notifyListeners();
  }

  void clearPendingStation() {
    _pendingStationOnMap = null;
  }
}
