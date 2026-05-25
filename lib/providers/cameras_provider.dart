import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/traffic_camera.dart';
import '../models/weather_station.dart';
import '../services/cameras_service.dart';

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

  List<TrafficCamera> get cameras => List.unmodifiable(_cameras);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasData => _cameras.isNotEmpty;

  List<TrafficCamera> visibleCameras(List<WeatherStation> stations) {
    return _cameras.where((camera) => !_duplicatesStation(camera, stations)).toList();
  }

  bool _duplicatesStation(TrafficCamera camera, List<WeatherStation> stations) {
    const distance = Distance();
    for (final station in stations) {
      if (station.cameraLink.isEmpty) continue;
      if (!station.hasWeather) continue;
      if (distance(camera.position, station.position) <= 80) return true;
    }
    return false;
  }

  void start() {
    refresh();
    _timer ??= Timer.periodic(_refreshInterval, (_) => refresh());
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
      _lastUpdated = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
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
