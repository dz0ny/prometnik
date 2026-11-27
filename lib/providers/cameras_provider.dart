import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/traffic_camera.dart';
import '../models/weather_station.dart';
import '../services/cameras_service.dart';
import '../services/webcam_store.dart';
import 'feed.dart';

final camerasServiceProvider = Provider<CamerasService>(
  (ref) => CamerasService(),
);

/// DARS traffic cameras. The set is fairly static; the live JPEG frames are
/// cache-busted at display time.
class CamerasFeed extends FeedNotifier<TrafficCamera> {
  @override
  Duration get refreshInterval => const Duration(minutes: 15);

  @override
  Duration get staleAfter => const Duration(minutes: 10);

  @override
  Future<List<TrafficCamera>> fetchItems() =>
      ref.read(camerasServiceProvider).fetchCameras();
}

final camerasProvider = NotifierProvider<CamerasFeed, FeedState<TrafficCamera>>(
  CamerasFeed.new,
);

/// [cameras] without the ones a weather station already shows.
List<TrafficCamera> visibleCameras(
  List<TrafficCamera> cameras,
  List<WeatherStation> stations,
) => [
  for (final camera in cameras)
    if (!_duplicatesStation(camera, stations)) camera,
];

bool _duplicatesStation(TrafficCamera camera, List<WeatherStation> stations) {
  const distance = Distance();
  final image = _imageId(camera.imageUrl);
  for (final station in stations) {
    if (station.cameraLink.isEmpty) continue;
    // The very same picture is a duplicate wherever the feed places it
    // (DARS often lists a station's camera a few hundred metres away).
    if (image.isNotEmpty && image == _imageId(station.cameraLink)) {
      return true;
    }
    if (!station.hasWeather) continue;
    if (distance(camera.position, station.position) <= 80) return true;
  }
  return false;
}

/// A camera picture's identity: its URL without scheme, `t` or case.
String _imageId(String url) => url.isEmpty
    ? ''
    : cameraKey(url).toLowerCase().replaceFirst(RegExp(r'^https?://'), '');
