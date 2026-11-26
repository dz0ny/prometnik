import 'dart:collection';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/drsi_station.dart';
import '../services/drsi_service.dart';
import '../services/user_error.dart';

/// Holds DRSI road weather stations and refreshes them periodically
/// (stations report every ~5 minutes).
class DrsiProvider extends ChangeNotifier {
  final DrsiService _service;

  DrsiProvider({DrsiService? service}) : _service = service ?? DrsiService();

  static const Duration _refreshInterval = Duration(minutes: 5);
  static const Duration _staleAfter = Duration(minutes: 3);

  Timer? _timer;
  List<DrsiStation> _items = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  // Cached read-only view: same identity until new data arrives, so
  // widgets can memoize derived lists (and skip rebuilds) by identity.
  List<DrsiStation> _view = const [];
  List<DrsiStation> get items => _view;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasData => _items.isNotEmpty;

  void start() {
    if (!DrsiService.isSupported) return;
    unawaited(refresh());
    _timer ??= Timer.periodic(_refreshInterval, (_) => unawaited(refresh()));
  }

  /// Stop polling (app backgrounded). [start] resumes and refreshes.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refreshIfStale([Duration maxAge = _staleAfter]) {
    final u = _lastUpdated;
    if (u == null || DateTime.now().difference(u) > maxAge) return refresh();
    return Future.value();
  }

  Future<void> refresh() async {
    if (_isLoading || !DrsiService.isSupported) return;
    _isLoading = true;
    if (!hasData) notifyListeners();
    try {
      _items = await _service.fetch();
      _view = UnmodifiableListView(_items);
      _lastUpdated = DateTime.now();
      _error = null;
    } on Exception catch (e) {
      _error = userErrorMessage(e);
      debugPrint('DrsiProvider.refresh error: $e');
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
