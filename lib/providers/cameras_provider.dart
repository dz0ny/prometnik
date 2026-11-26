import 'dart:collection';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/traffic_camera.dart';
import '../models/weather_station.dart';
import '../services/cameras_service.dart';
import '../services/user_error.dart';
import '../services/webcam_store.dart';

/// Holds the DARS camera list and refreshes it periodically. The camera set is
/// fairly static; the live JPEG images are cache-busted at display time.
class CamerasProvider extends ChangeNotifier {
  final CamerasService _service;

  CamerasProvider({CamerasService? service})
    : _service = service ?? CamerasService();

  static const Duration _refreshInterval = Duration(minutes: 15);
  static const Duration _staleAfter = Duration(minutes: 10);

  Timer? _timer;
  List<TrafficCamera> _cameras = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  // Cached read-only view: same identity until new data arrives, so
  // widgets can memoize derived lists (and skip rebuilds) by identity.
  List<TrafficCamera> _view = const [];
  List<TrafficCamera> get cameras => _view;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasData => _cameras.isNotEmpty;

  List<TrafficCamera> visibleCameras(List<WeatherStation> stations) {
    return _cameras
        .where((camera) => !_duplicatesStation(camera, stations))
        .toList();
  }

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
  static String _imageId(String url) => url.isEmpty
      ? ''
      : cameraKey(url).toLowerCase().replaceFirst(RegExp(r'^https?://'), '');

  void start() {
    refresh();
    _timer ??= Timer.periodic(_refreshInterval, (_) => refresh());
  }

  /// Stop polling (app backgrounded). [start] resumes and refreshes.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refreshIfStale([Duration maxAge = _staleAfter]) {
    final updated = _lastUpdated;
    if (updated == null || DateTime.now().difference(updated) > maxAge) {
      return refresh();
    }
    return Future.value();
  }

  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    if (!hasData) notifyListeners();

    try {
      _cameras = await _service.fetchCameras();
      _view = UnmodifiableListView(_cameras);
      _lastUpdated = DateTime.now();
      _error = null;
    } catch (e) {
      _error = userErrorMessage(e);
      debugPrint('CamerasProvider.refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
