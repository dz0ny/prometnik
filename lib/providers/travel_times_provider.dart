import 'dart:collection';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/travel_time.dart';
import '../services/travel_times_service.dart';
import '../services/user_error.dart';

/// Holds travel times and keeps them fresh by polling the promet.si data
/// channel (which caches for ~60s).
class TravelTimesProvider extends ChangeNotifier {
  final TravelTimesService _service;

  TravelTimesProvider({TravelTimesService? service})
    : _service = service ?? TravelTimesService();

  static const Duration _refreshInterval = Duration(minutes: 2);
  static const Duration _staleAfter = Duration(minutes: 1);

  Timer? _timer;
  List<TravelTime> _items = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  // Cached read-only view: same identity until new data arrives, so
  // widgets can memoize derived lists (and skip rebuilds) by identity.
  List<TravelTime> _view = const [];
  List<TravelTime> get items => _view;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasData => _items.isNotEmpty;

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
      _items = await _service.fetchTravelTimes();
      _view = UnmodifiableListView(_items);
      _lastUpdated = DateTime.now();
      _error = null;
    } catch (e) {
      _error = userErrorMessage(e);
      debugPrint('TravelTimesProvider.refresh error: $e');
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
