import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Immutable snapshot of location, watched roads/routes and the events they
/// apply to. Derived lists are computed on read.
@immutable
class AlertsState {
  final Position? position;
  final bool locationEnabled;
  final bool requesting;
  final List<TrafficEvent> events;

  /// Watched road refs (e.g. "A1", "651").
  final Set<String> watchedRoads;
  final Set<String> watchedTravelTimes;

  /// Why the last location request (or the running position stream) failed;
  /// null while location works or before the user asked for it.
  final LocationStatus? locationProblem;

  /// True after the user declined notification permission when turning on a
  /// travel-time alert (the alert was then not turned on).
  final bool notificationsDenied;

  const AlertsState({
    this.position,
    this.locationEnabled = false,
    this.requesting = false,
    this.events = const [],
    this.watchedRoads = const {},
    this.watchedTravelTimes = const {},
    this.locationProblem,
    this.notificationsDenied = false,
  });

  bool get hasWatched => watchedRoads.isNotEmpty;
  bool isWatched(String ref) => watchedRoads.contains(ref);
  bool isTravelTimeWatched(String id) => watchedTravelTimes.contains(id);

  /// Slovenian text for [locationProblem], or null.
  String? get locationProblemMessage => locationProblem?.message;

  /// Whether opening settings can fix [locationProblem] (a plain
  /// [LocationStatus.denied] can also be retried with enableLocation).
  bool get canOpenLocationSettings =>
      locationProblem == LocationStatus.deniedForever ||
      locationProblem == LocationStatus.serviceDisabled;

  /// Active events on watched roads.
  List<TrafficEvent> get watchedEvents => [
    for (final e in events)
      if (e.isActive() && eventOnRoads(e, watchedRoads)) e,
  ];

  /// All events sorted by distance from the user (empty without a fix).
  List<NearbyEvent> get nearbyEvents {
    final p = position;
    if (p == null) return const [];
    return [
      for (final e in events)
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
  }
}

/// Whether [e] is on one of [roads] (OSM refs, possibly combined "A1;A2").
bool eventOnRoads(TrafficEvent e, Set<String> roads) {
  final ref = eventRoadRef(e.road);
  return ref != null && roads.any((w) => roadRefMatches(ref, w));
}

/// Tracks the user's location and the watched roads/routes, and fires local
/// notifications for significant events nearby or on a watched road, and for
/// changes on watched travel-time routes.
///
/// It listens to the events and travel-time feeds directly (not via a widget
/// rebuild), so alerts still fire when a poll completes in the background.
class AlertsNotifier extends Notifier<AlertsState> {
  static const _notifiedKey = 'alerts.notifiedIds';

  /// Minimum gap between two travel-time notifications for the same route.
  static const Duration _travelAlertCooldown = Duration(minutes: 10);

  bool _building = false;

  @override
  AlertsState build() {
    _building = true;
    _watchedRoads
      ..clear()
      ..addAll(Prefs.getStringList('alerts.watchedRefs', const []));
    _watchedTravelTimes
      ..clear()
      ..addAll(Prefs.getStringList('alerts.watchedTravelTimeIds', const []));
    // Remember what was already alerted so a cold start doesn't re-notify
    // every long-running closure / roadworks on watched roads.
    _notified
      ..clear()
      ..addAll(Prefs.getStringList(_notifiedKey, const []));

    ref.listen(
      eventsProvider.select((s) => s.items),
      (_, items) => updateEvents(items),
      fireImmediately: true,
    );
    ref.listen(
      travelTimesProvider.select((s) => s.items),
      (_, items) => updateTravelTimes(items),
      fireImmediately: true,
    );
    ref.onDispose(() => unawaited(_sub?.cancel()));
    // Silently resume tracking if permission was granted before.
    scheduleMicrotask(() {
      unawaited(
        bootstrap().catchError((Object e, StackTrace s) {
          debugPrint('alerts bootstrap failed: $e\n$s');
        }),
      );
    });
    _building = false;
    return _snapshot();
  }

  AlertsState _snapshot() => AlertsState(
    position: _position,
    locationEnabled: _locationEnabled,
    requesting: _requesting,
    events: _events,
    watchedRoads: Set.unmodifiable(_watchedRoads),
    watchedTravelTimes: Set.unmodifiable(_watchedTravelTimes),
    locationProblem: _locationProblem,
    notificationsDenied: _notificationsDenied,
  );

  /// Publish the current fields as a new immutable state.
  void _emit() {
    if (_building || !ref.mounted) return;
    state = _snapshot();
  }

  bool get _disposed => !ref.mounted;

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

  LocationStatus? _locationProblem;
  bool _notificationsDenied = false;
  final Set<String> _pendingTravelToggles = {};

  /// Open the system screen that fixes [locationProblem] (app settings when
  /// permission is denied, location settings when services are off). Call
  /// [enableLocation] again when the app resumes.
  Future<bool> openLocationSettings() {
    final problem = _locationProblem;
    if (problem == null) return Future.value(false);
    return LocationService.instance.openSettingsFor(problem);
  }

  /// Open the app's system settings (e.g. to allow notifications).
  Future<bool> openAppSettings() =>
      LocationService.instance.openSettingsFor(LocationStatus.deniedForever);

  void dismissLocationProblem() {
    if (_locationProblem == null) return;
    _locationProblem = null;
    _emit();
  }

  void dismissNotificationsDenied() {
    if (!_notificationsDenied) return;
    _notificationsDenied = false;
    _emit();
  }

  /// Toggle a watched road ref (used by the map picker).
  void toggleRoad(String ref) {
    if (ref.isEmpty) return;
    if (!_watchedRoads.add(ref)) _watchedRoads.remove(ref);
    _persistWatched();
  }

  /// Toggle a travel-time alert. Turning one on first asks for notification
  /// permission; if that is declined the alert stays off and
  /// [notificationsDenied] becomes true. Completes with whether [id] is
  /// watched afterwards (callers may ignore the result).
  Future<bool> toggleTravelTime(String id) async {
    if (id.isEmpty) return false;
    if (_watchedTravelTimes.remove(id)) {
      _lastTravelAlertById.remove(id);
      _persistWatchedTravelTimes();
      return false;
    }
    // A double tap while the permission prompt is up must not toggle twice.
    if (!_pendingTravelToggles.add(id)) return false;
    bool granted;
    try {
      granted = await NotificationsService.instance.requestPermission();
    } on Exception catch (e) {
      debugPrint('notification permission request failed: $e');
      granted = false;
    } finally {
      _pendingTravelToggles.remove(id);
    }
    if (_disposed) return false;
    if (!granted) {
      _notificationsDenied = true;
      _emit();
      return false;
    }
    _notificationsDenied = false;
    _watchedTravelTimes.add(id);
    final current = _travelTimesById[id];
    if (current != null) _lastTravelAlertById[id] = current;
    _persistWatchedTravelTimes();
    return true;
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
    _emit();
  }

  void _persistWatchedTravelTimes() {
    Prefs.setStringList(
      'alerts.watchedTravelTimeIds',
      _watchedTravelTimes.toList(),
    );
    _emit();
  }

  bool _onWatchedRoad(TrafficEvent e) => eventOnRoads(e, _watchedRoads);

  /// Called whenever the events list changes. Deferred to a microtask (not a
  /// post-frame callback, which never runs while the app draws no frames in
  /// the background) so we never notify in the middle of a build.
  void updateEvents(List<TrafficEvent> events) {
    _events = events;
    scheduleMicrotask(() {
      if (_disposed) return;
      _checkAlerts();
      _emit();
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
      _emit();
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
    _emit();
    try {
      final status = await LocationService.instance.requestPermission();
      if (status == LocationStatus.granted) {
        _locationProblem = null;
        // Proximity alerts need notifications, but location works without.
        final notifications = await NotificationsService.instance
            .requestPermission();
        if (notifications) _notificationsDenied = false;
        await _startTracking();
      } else {
        _locationProblem = status;
      }
    } on Exception catch (e) {
      debugPrint('enableLocation failed: $e');
      _locationEnabled = false;
    } finally {
      _requesting = false;
      _emit();
    }
  }

  /// Single-flight: bootstrap() and enableLocation() may overlap.
  Future<void> _startTracking() =>
      _starting ??= _doStartTracking().whenComplete(() {
        _starting = null;
      });

  Future<void> _doStartTracking() async {
    await _sub?.cancel();
    _sub = LocationService.instance.stream().listen(
      (pos) {
        _position = pos;
        _checkAlerts();
        _emit();
      },
      onError: (Object e) {
        // Location switched off / permission revoked while running.
        debugPrint('position stream error: $e');
        _locationEnabled = false;
        if (e is LocationServiceDisabledException) {
          _locationProblem = LocationStatus.serviceDisabled;
        } else if (e is PermissionDeniedException) {
          _locationProblem = LocationStatus.deniedForever;
        }
        unawaited(_sub?.cancel());
        _sub = null;
        _emit();
      },
    );
    _locationEnabled = true;
    _locationProblem = null;
    _position = await LocationService.instance.current() ?? _position;
    if (_disposed) return;
    _checkAlerts();
    _emit();
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
}

final alertsProvider = NotifierProvider<AlertsNotifier, AlertsState>(
  AlertsNotifier.new,
);
