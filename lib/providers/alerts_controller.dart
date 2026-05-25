import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../models/traffic_event.dart';
import '../models/travel_time.dart';
import '../services/location_service.dart';
import '../services/notifications_service.dart';
import '../services/prefs.dart';
import '../services/roads_service.dart';

/// An event paired with its distance from the user (metres).
class NearbyEvent {
  final TrafficEvent event;
  final double distanceMeters;
  const NearbyEvent(this.event, this.distanceMeters);
}

/// Tracks the user's location and the set of watched roads, exposes nearby /
/// watched events, and fires local notifications (while the app is running) for
/// significant events that are nearby or on a watched road.
class AlertsController extends ChangeNotifier {
  AlertsController() {
    _watchedRoads.addAll(Prefs.getStringList('alerts.watchedRefs', const []));
    _watchedTravelTimes.addAll(
      Prefs.getStringList('alerts.watchedTravelTimeIds', const []),
    );
  }

  /// Alert radius for proximity notifications.
  static const double _alertRadiusMeters = 10000;

  Position? _position;
  bool _locationEnabled = false;
  bool _requesting = false;
  List<TrafficEvent> _events = const [];
  final Set<String> _watchedRoads = {};
  final Set<String> _watchedTravelTimes = {};
  final Set<String> _notified = {};
  final Map<String, TravelTime> _travelTimesById = {};
  final Map<String, TravelTime> _lastTravelAlertById = {};
  StreamSubscription<Position>? _sub;

  Position? get position => _position;
  bool get locationEnabled => _locationEnabled;
  bool get requesting => _requesting;

  /// All current events (sorted as delivered by the service: priority, road).
  List<TrafficEvent> get events => List.unmodifiable(_events);
  /// Watched road refs (e.g. "A1", "651").
  Set<String> get watchedRoads => Set.unmodifiable(_watchedRoads);
  Set<String> get watchedTravelTimes => Set.unmodifiable(_watchedTravelTimes);
  bool get hasWatched => _watchedRoads.isNotEmpty;

  bool isWatched(String ref) => _watchedRoads.contains(ref);
  bool isTravelTimeWatched(String id) => _watchedTravelTimes.contains(id);

  /// Toggle a watched road ref (used by the map picker).
  void toggleRoad(String ref) {
    if (ref.isEmpty) return;
    if (!_watchedRoads.add(ref)) _watchedRoads.remove(ref);
    _persistWatched();
  }

  void toggleTravelTime(String id) {
    if (id.isEmpty) return;
    if (!_watchedTravelTimes.add(id)) {
      _watchedTravelTimes.remove(id);
      _lastTravelAlertById.remove(id);
    } else {
      final current = _travelTimesById[id];
      if (current != null) _lastTravelAlertById[id] = current;
      unawaited(NotificationsService.instance.requestPermission());
    }
    _persistWatchedTravelTimes();
  }

  void setWatched(String ref, bool on) {
    if (on) {
      _watchedRoads.add(ref);
    } else {
      _watchedRoads.remove(ref);
    }
    _persistWatched();
  }

  void setWatchedRoads(Iterable<String> refs) {
    _watchedRoads
      ..clear()
      ..addAll(refs);
    _persistWatched();
  }

  void _persistWatched() {
    Prefs.setStringList('alerts.watchedRefs', _watchedRoads.toList());
    _checkAlerts();
    notifyListeners();
  }

  void _persistWatchedTravelTimes() {
    Prefs.setStringList(
      'alerts.watchedTravelTimeIds',
      _watchedTravelTimes.toList(),
    );
    notifyListeners();
  }

  bool _onWatchedRoad(TrafficEvent e) {
    final ref = eventRoadRef(e.road);
    return ref != null && _watchedRoads.contains(ref);
  }

  /// Active events on watched roads.
  List<TrafficEvent> get watchedEvents =>
      _events.where((e) => e.isActive() && _onWatchedRoad(e)).toList();

  /// All events sorted by distance from the user (empty without a fix).
  List<NearbyEvent> get nearbyEvents {
    final p = _position;
    if (p == null) return const [];
    final out = [
      for (final e in _events)
        NearbyEvent(
          e,
          LocationService.instance.distanceMeters(
            p.latitude,
            p.longitude,
            e.position.latitude,
            e.position.longitude,
          ),
        ),
    ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return out;
  }

  /// Called (via a proxy) whenever the events list changes. Defers work to
  /// after the current frame to avoid notifying during build.
  void updateEvents(List<TrafficEvent> events) {
    _events = events;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAlerts();
      notifyListeners();
    });
  }

  void updateTravelTimes(List<TravelTime> items) {
    final previous = Map<String, TravelTime>.from(_travelTimesById);
    _travelTimesById
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.id, item)));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTravelTimeAlerts(previous);
      notifyListeners();
    });
  }

  /// Silently start tracking if location permission is already granted (no
  /// prompt). Call once at startup so the UI doesn't ask again unnecessarily.
  Future<void> bootstrap() async {
    if (await LocationService.instance.hasPermission()) {
      await _startTracking();
    }
  }

  /// Prompts for permission (if needed) and starts tracking.
  Future<void> enableLocation() async {
    if (_requesting || _locationEnabled) return;
    _requesting = true;
    notifyListeners();
    final ok = await LocationService.instance.ensurePermission();
    if (ok) {
      await NotificationsService.instance.requestPermission();
      await _startTracking();
    }
    _requesting = false;
    notifyListeners();
  }

  Future<void> _startTracking() async {
    _locationEnabled = true;
    _position = await LocationService.instance.current() ?? _position;
    await _sub?.cancel();
    _sub = LocationService.instance.stream().listen((pos) {
      _position = pos;
      _checkAlerts();
      notifyListeners();
    });
    _checkAlerts();
    notifyListeners();
  }

  void _checkAlerts() {
    for (final e in _events) {
      if (!e.isActive()) continue;
      final significant = e.isRoadClosed || e.isJam || e.isRoadworks;
      final onWatched = significant && _onWatchedRoad(e);

      var nearby = false;
      final p = _position;
      if (p != null && (e.isRoadClosed || e.isJam)) {
        final d = LocationService.instance.distanceMeters(
          p.latitude,
          p.longitude,
          e.position.latitude,
          e.position.longitude,
        );
        nearby = d <= _alertRadiusMeters;
      }

      if ((onWatched || nearby) && !_notified.contains(e.id)) {
        _notified.add(e.id);
        final title = [
          if (e.cause.isNotEmpty) e.cause else e.title,
          if (e.road.isNotEmpty) e.road,
        ].join(' · ');
        NotificationsService.instance.show(
          id: e.id.hashCode & 0x7fffffff,
          title: title.isEmpty ? 'Prometni dogodek' : title,
          body: e.description.isNotEmpty ? e.description : e.title,
        );
      }
    }
    // Forget events that have disappeared so they can re-alert if they return.
    final ids = _events.map((e) => e.id).toSet();
    _notified.removeWhere((id) => !ids.contains(id));
  }

  void _checkTravelTimeAlerts(Map<String, TravelTime> previous) {
    for (final id in _watchedTravelTimes) {
      final current = _travelTimesById[id];
      if (current == null) continue;
      final baseline = _lastTravelAlertById[id] ?? previous[id];
      if (baseline == null) {
        _lastTravelAlertById[id] = current;
        continue;
      }
      final change = current.delayMs - baseline.delayMs;
      final statusChanged = current.status != baseline.status;
      if (!statusChanged && change.abs() < 120000) continue;

      _lastTravelAlertById[id] = current;
      final worsened = statusChanged
          ? current.status.index > baseline.status.index
          : change > 0;
      NotificationsService.instance.show(
        id: current.id.hashCode & 0x7fffffff,
        title: worsened ? 'Potovalni čas se slabša' : 'Potovalni čas se izboljšuje',
        body: [
          current.route,
          current.actualText,
          if (current.hasDelay) '+${current.delayText}' else 'tekoče',
        ].join(' · '),
      );
    }
    _lastTravelAlertById.removeWhere(
      (id, _) => !_watchedTravelTimes.contains(id) || !_travelTimesById.containsKey(id),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
