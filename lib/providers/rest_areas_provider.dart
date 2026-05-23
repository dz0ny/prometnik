import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/rest_area.dart';
import '../services/rest_areas_service.dart';

/// Holds rest areas and refreshes parking availability periodically.
class RestAreasProvider extends ChangeNotifier {
  final RestAreasService _service;

  RestAreasProvider({RestAreasService? service})
      : _service = service ?? RestAreasService();

  static const Duration _refreshInterval = Duration(minutes: 5);
  static const Duration _staleAfter = Duration(minutes: 3);

  Timer? _timer;
  List<RestArea> _items = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  List<RestArea> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasData => _items.isNotEmpty;

  void start() {
    refresh();
    _timer ??= Timer.periodic(_refreshInterval, (_) => refresh());
  }

  Future<void> refreshIfStale([Duration maxAge = _staleAfter]) {
    final u = _lastUpdated;
    if (u == null || DateTime.now().difference(u) > maxAge) return refresh();
    return Future.value();
  }

  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    if (!hasData) notifyListeners();
    try {
      _items = await _service.fetch();
      _lastUpdated = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('RestAreasProvider.refresh error: $e');
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
