import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/traffic_event.dart';
import '../services/events_service.dart';

/// Holds the list of traffic events and keeps it fresh by polling the
/// promet.si data channel (which caches for ~60s).
class EventsProvider extends ChangeNotifier {
  final EventsService _service;

  EventsProvider({EventsService? service})
      : _service = service ?? EventsService();

  static const Duration _refreshInterval = Duration(minutes: 2);
  static const Duration _staleAfter = Duration(minutes: 1);

  Timer? _timer;
  List<TrafficEvent> _events = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  List<TrafficEvent> get events => List.unmodifiable(_events);
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasData => _events.isNotEmpty;

  TrafficEvent? byId(String id) {
    for (final e in _events) {
      if (e.id == id) return e;
    }
    return null;
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
      _events = await _service.fetchEvents();
      _lastUpdated = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('EventsProvider.refresh error: $e');
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
