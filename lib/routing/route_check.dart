import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/burja_station.dart';
import '../models/drsi_station.dart';
import '../models/traffic_event.dart';
import '../models/travel_time.dart';
import '../providers/routes_provider.dart' show savedRoutesKey;
import '../services/burja_service.dart';
import '../services/drsi_service.dart';
import '../services/events_service.dart';
import '../services/notifications_service.dart';
import '../services/prefs.dart';
import '../services/travel_times_service.dart';
import 'corridors.dart';
import 'road_graph.dart';
import 'route_warnings.dart';
import 'saved_route.dart';

/// Background task id (also in Info.plist `BGTaskSchedulerPermittedIdentifiers`
/// and AppDelegate).
const routeCheckTask = 'dev.dz0ny.promet.routeCheck';

/// How long before a departure the route is watched.
const departureWindow = Duration(minutes: 60);

const _sentKey = 'routes.notified';

/// A notification to show for a route.
@immutable
class RouteNotice {
  /// Remembered so it is shown once ("route@departure|what").
  final String key;
  final String title;
  final String body;
  const RouteNotice(this.key, this.title, this.body);
}

/// The departure of [r] within [departureWindow] from [now], if any.
DateTime? upcomingDeparture(SavedRoute r, DateTime now) {
  final dep = r.nextDeparture(now);
  if (dep == null || dep.difference(now) > departureWindow) return null;
  return dep;
}

/// What to notify for routes departing soon: one summary per departure
/// when there is anything on the route, then each new serious warning
/// (closure, jam, ice) until departure. Pure; [sent] holds shown keys.
List<RouteNotice> routeNotices(
  List<SavedRoute> routes,
  Map<String, List<RouteWarning>> warnings,
  DateTime now,
  Set<String> sent,
) {
  final out = <RouteNotice>[];
  for (final r in routes) {
    final dep = upcomingDeparture(r, now);
    if (dep == null) continue;
    final list = [
      for (final w in warnings[r.id] ?? const <RouteWarning>[])
        if (!w.opposite) w,
    ];
    if (list.isEmpty) continue;
    final depKey = '${r.id}@${dep.toIso8601String()}';
    final hh =
        '${dep.hour.toString().padLeft(2, '0')}:'
        '${dep.minute.toString().padLeft(2, '0')}';
    if (!sent.contains('$depKey|sum')) {
      out.add(
        RouteNotice(
          '$depKey|sum',
          '${r.name}: ${warningCount(list.length)} pred odhodom ob $hh',
          list.take(3).map((w) => w.title).join('\n'),
        ),
      );
      // The summary covers what is there now.
      for (final w in list) {
        out.add(RouteNotice('$depKey|${w.id}', '', ''));
      }
      continue;
    }
    for (final w in list) {
      if (w.severity < 2 || sent.contains('$depKey|${w.id}')) continue;
      out.add(
        RouteNotice('$depKey|${w.id}', '${r.name}: ${w.title}', w.detail),
      );
    }
  }
  return out;
}

/// "1 opozorilo", "2 opozorili", "3 opozorila", "5 opozoril".
String warningCount(int n) {
  final m = n % 100;
  final word = m == 1
      ? 'opozorilo'
      : m == 2
      ? 'opozorili'
      : (m == 3 || m == 4)
      ? 'opozorila'
      : 'opozoril';
  return '$n $word';
}

/// Checks the saved routes departing soon and notifies. Runs in the
/// background task and when the app opens; does nothing (no network) when
/// no route departs within [departureWindow].
Future<void> runRouteCheck({DateTime? at}) async {
  final now = at ?? DateTime.now();
  final routes = SavedRoute.decodeList(Prefs.getString(savedRoutesKey));
  final due = [
    for (final r in routes)
      if (upcomingDeparture(r, now) != null) r,
  ];
  if (due.isEmpty) return;

  Future<List<T>> safe<T>(Future<List<T>> f) =>
      f.timeout(const Duration(seconds: 20)).catchError((Object e) {
        debugPrint('route check: feed failed: $e');
        return <T>[];
      });
  final results = await Future.wait([
    safe<TrafficEvent>(EventsService().fetchEvents()),
    safe<DrsiStation>(DrsiService().fetch()),
    safe<BurjaStation>(BurjaService().fetch()),
    safe<TravelTime>(TravelTimesService().fetchTravelTimes()),
  ]);
  final corridors = await _corridors();
  final warnings = {
    for (final r in due)
      r.id: routeWarnings(
        RouteIndex(r.points),
        events: results[0] as List<TrafficEvent>,
        roadStations: results[1] as List<DrsiStation>,
        wind: results[2] as List<BurjaStation>,
        travelTimes: results[3] as List<TravelTime>,
        corridors: corridors,
        roadRefs: r.roadRefs.toSet(),
        now: now,
        fromName: r.places.first.name,
        toName: r.places.last.name,
      ),
  };

  final sent = Prefs.getStringList(_sentKey, const []).toSet();
  final notices = routeNotices(due, warnings, now, sent);
  if (notices.isEmpty) return;
  await NotificationsService.instance.init();
  for (final n in notices) {
    sent.add(n.key);
    if (n.title.isEmpty) continue;
    await NotificationsService.instance.show(
      id: 'route:${n.key}'.hashCode & 0x7fffffff,
      title: n.title,
      body: n.body,
    );
  }
  // Forget departures older than two days.
  final cutoff = now.subtract(const Duration(days: 2));
  sent.removeWhere((k) {
    final at = DateTime.tryParse(k.split('@').last.split('|').first);
    return at == null || at.isBefore(cutoff);
  });
  Prefs.setStringList(_sentKey, sent.toList());
}

/// The travel-time corridors, routed on the bundled roads (off the main
/// isolate); empty when the roads can't be loaded.
Future<List<Corridor>> _corridors() async {
  try {
    final raw = await rootBundle.loadString('assets/roads.json');
    return await compute(_buildCorridors, raw);
  } on Exception catch (e) {
    debugPrint('route check: corridors failed: $e');
    return const [];
  }
}

List<Corridor> _buildCorridors(String raw) {
  final list = jsonDecode(raw) as List;
  final refs = <String>[];
  final coords = <Float64List>[];
  for (final item in list) {
    final l = item as List;
    refs.add(l[0] as String);
    coords.add(
      Float64List.fromList([
        for (final v in l[2] as List) (v as num).toDouble(),
      ]),
    );
  }
  return buildCorridors(RoadGraph.build(refs, coords));
}
