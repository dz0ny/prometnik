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
    // (DARS often lists a station's camera a few hundred metres away),
    // including a station's second and third camera.
    if (image.isNotEmpty &&
        station.cameras.any((url) => image == _imageId(url))) {
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

/// The DARS feed's entry for the camera picture [url], if it lists it; it
/// carries the camera's name and view ("…, pogled proti Planici").
TrafficCamera? cameraForImage(List<TrafficCamera> cameras, String url) {
  final id = _imageId(url);
  if (id.isEmpty) return null;
  for (final c in cameras) {
    if (_imageId(c.imageUrl) == id) return c;
  }
  return null;
}

/// A short label telling a station's cameras apart: the last part of the
/// DARS description ("R1-202, Rateče - Podkoren, krožišče Rateče" →
/// "krožišče Rateče"), else the title; null without either.
String? cameraShortLabel(TrafficCamera? camera) {
  if (camera == null) return null;
  final parts = camera.description
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isNotEmpty) return parts.last;
  final title = camera.title.trim();
  return title.isEmpty ? null : title;
}
