import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// A cross-tab request: switch to the map and focus a station or a location.
@immutable
sealed class MapRequest {
  const MapRequest();
}

class ShowStationOnMap extends MapRequest {
  final int stationId;
  const ShowStationOnMap(this.stationId);
}

class ShowLocationOnMap extends MapRequest {
  final LatLng location;
  const ShowLocationOnMap(this.location);
}

/// The pending [MapRequest], consumed by the main scaffold (`ref.listen`),
/// which then calls [clear].
class MapRequestNotifier extends Notifier<MapRequest?> {
  @override
  MapRequest? build() => null;

  void showStationOnMap(int stationId) => state = ShowStationOnMap(stationId);

  void showLocationOnMap(LatLng location) =>
      state = ShowLocationOnMap(location);

  void clear() => state = null;
}

final mapRequestProvider = NotifierProvider<MapRequestNotifier, MapRequest?>(
  MapRequestNotifier.new,
);
