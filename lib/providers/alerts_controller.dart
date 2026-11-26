import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../models/traffic_event.dart';
import '../models/travel_time.dart';
import 'events_provider.dart';
import 'travel_times_provider.dart';
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
    // Remember what was already alerted so a cold start doesn't re-notify
    // every long-running closure / roadworks on watched roads.
    _notified.addAll(Prefs.getStringList(_notifiedKey, const []));
  }

  static const _notifiedKey = 'alerts.notifiedIds';

  /// Minimum gap between two travel-time notifications for the same route.
  static const Duration _travelAlertCooldown = Duration(minutes: 10);

  EventsProvider? _eventsSource;
  TravelTimesProvider? _travelSource;

  /// Listen to the data providers directly (not via a widget rebuild), so
  /// alerts still fire when a poll completes while the app is backgrounded.
  void attach(EventsProvider events, TravelTimesProvider travelTimes) {
    _eventsSource = events..addListener(_onEventsChanged);
    _travelSource = travelTimes..addListener(_onTravelTimesChanged);
    _onEventsChanged();
    _onTravelTimesChanged();
  }

  void _onEventsChanged() {
    final src = _eventsSource;
    if (src != null) updateEvents(src.events);
  }

  void _onTravelTimesChanged() {
    final src = _travelSource;
    if (src != null) updateTravelTimes(src.items);
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
  final Map<String, DateTime> _lastTravelAlertAt = {};
  StreamSubscription<Position>? _sub;
  Future<void>? _starting;
  bool _disposed = false;

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
    // Watched refs come from OSM and may be combined ("A1;A2").
    return ref != null && _watchedRoads.any((w) => roadRefMatches(ref, w));
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
        if (e.hasPosition)
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

  /// Called whenever the events list changes. Deferred to a microtask (not a
  /// post-frame callback, which never runs while the app draws no frames in
  /// the background) so we never notify in the middle of a build.
  void updateEvents(List<TrafficEvent> events) {
    _events = events;
    scheduleMicrotask(() {
      if (_disposed) return;
      _checkAlerts();
      notifyListeners();
    });
  }

  void updateTravelTimes(List<TravelTime> items) {
    final previous = Map<String, TravelTime>.from(_travelTimesById);
    _travelTimesById
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.id, item)));

    scheduleMicrotask(() {
      if (_disposed) return;
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
    try {
      final ok = await LocationService.instance.ensurePermission();
      if (ok) {
        await NotificationsService.instance.requestPermission();
        await _startTracking();
      }
    } on Exception catch (e) {
      debugPrint('enableLocation failed: $e');
      _locationEnabled = false;
    } finally {
      _requesting = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Single-flight: bootstrap() and enableLocation() may overlap.
  Future<void> _startTracking() =>
      _starting ??= _doStartTracking().whenComplete(() => _starting = null);

  Future<void> _doStartTracking() async {
    await _sub?.cancel();
    _sub = LocationService.instance.stream().listen(
      (pos) {
        _position = pos;
        _checkAlerts();
        notifyListeners();
      },
      onError: (Object e) {
        // Location switched off / permission revoked while running.
        debugPrint('position stream error: $e');
        _locationEnabled = false;
        unawaited(_sub?.cancel());
        _sub = null;
        if (!_disposed) notifyListeners();
      },
    );
    _locationEnabled = true;
    _position = await LocationService.instance.current() ?? _position;
    if (_disposed) return;
    _checkAlerts();
    notifyListeners();
  }

  void _checkAlerts() {
    var changed = false;
    for (final e in _events) {
      if (e.id.isEmpty || !e.isActive()) continue;
      final significant = e.isRoadClosed || e.isJam || e.isRoadworks;
      final onWatched = significant && _onWatchedRoad(e);

      var nearby = false;
      final p = _position;
      if (p != null && e.hasPosition && (e.isRoadClosed || e.isJam)) {
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
        changed = true;
        final title = [
          if (e.cause.isNotEmpty) e.cause else e.title,
          if (e.road.isNotEmpty) e.road,
        ].join(' · ');
        NotificationsService.instance.show(
          id: 'ev:${e.id}'.hashCode & 0x7fffffff,
          title: title.isEmpty ? 'Prometni dogodek' : title,
          body: e.description.isNotEmpty ? e.description : e.title,
        );
      }
    }
    // Forget events that have disappeared so they can re-alert if they return.
    // An empty list is most likely a failed/partial fetch, not "all clear".
    if (_events.isNotEmpty) {
      final ids = _events.map((e) => e.id).toSet();
      final before = _notified.length;
      _notified.removeWhere((id) => !ids.contains(id));
      if (_notified.length != before) changed = true;
    }
    if (changed) Prefs.setStringList(_notifiedKey, _notified.toList());
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
      // A status flip caused by a few seconds around a threshold is noise;
      // require a real change in delay either way.
      if (change.abs() < 120000 && !(statusChanged && change.abs() >= 60000)) {
        continue;
      }
      final last = _lastTravelAlertAt[id];
      final now = DateTime.now();
      if (last != null && now.difference(last) < _travelAlertCooldown) continue;

      _lastTravelAlertById[id] = current;
      _lastTravelAlertAt[id] = now;
      final worsened = statusChanged
          ? current.status.index > baseline.status.index
          : change > 0;
      NotificationsService.instance.show(
        id: 'tt:${current.id}'.hashCode & 0x7fffffff,
        title: worsened
            ? 'Potovalni čas se slabša'
            : 'Potovalni čas se izboljšuje',
        body: [
          current.route,
          current.actualText,
          if (current.hasDelay) '+${current.delayText}' else 'tekoče',
        ].join(' · '),
      );
    }
    _lastTravelAlertById.removeWhere(
      (id, _) =>
          !_watchedTravelTimes.contains(id) ||
          !_travelTimesById.containsKey(id),
    );
    _lastTravelAlertAt.removeWhere(
      (id, _) => !_watchedTravelTimes.contains(id),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _eventsSource?.removeListener(_onEventsChanged);
    _travelSource?.removeListener(_onTravelTimesChanged);
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
