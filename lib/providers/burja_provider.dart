import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/burja_station.dart';
import '../services/burja_service.dart';

/// Holds burja (crosswind) measurements and refreshes them periodically.
class BurjaProvider extends ChangeNotifier {
  final BurjaService _service;

  BurjaProvider({BurjaService? service}) : _service = service ?? BurjaService();

  static const Duration _refreshInterval = Duration(minutes: 5);
  static const Duration _staleAfter = Duration(minutes: 3);

  Timer? _timer;
  List<BurjaStation> _items = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  List<BurjaStation> get items => List.unmodifiable(_items);
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
      debugPrint('BurjaProvider.refresh error: $e');
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
