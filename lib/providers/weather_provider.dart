import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/weather_station.dart';
import '../services/weather_service.dart';

/// Holds the list of weather/camera stations and keeps it fresh by polling
/// the ceste.si API on the same cadence as the official web app (10 min).
class WeatherProvider extends ChangeNotifier {
  final WeatherService _service;

  WeatherProvider({WeatherService? service})
      : _service = service ?? WeatherService();

  static const Duration _refreshInterval = Duration(minutes: 10);

  Timer? _timer;
  List<WeatherStation> _stations = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  List<WeatherStation> get stations => List.unmodifiable(_stations);
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasData => _stations.isNotEmpty;

  /// Stations that report a temperature, used for the map heat markers.
  List<WeatherStation> get stationsWithWeather =>
      _stations.where((s) => s.hasWeather).toList(growable: false);

  WeatherStation? byId(int id) {
    for (final s in _stations) {
      if (s.stationId == id) return s;
    }
    return null;
  }

  static const Duration _staleAfter = Duration(minutes: 5);

  /// Start an initial load and the periodic refresh timer.
  void start() {
    refresh();
    _timer ??= Timer.periodic(_refreshInterval, (_) => refresh());
  }

  /// Refresh only if the data is missing or older than [maxAge] (default 5 min).
  /// Called when a tab becomes active so switching tabs picks up fresh data.
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
      final fetched = await _service.fetchStations();
      _stations = fetched;
      _lastUpdated = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('WeatherProvider.refresh error: $e');
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
