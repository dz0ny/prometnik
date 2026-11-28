import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/burja_station.dart';
import '../models/drsi_station.dart';
import '../models/traffic_event.dart';
import '../models/travel_time.dart';
import 'road_graph.dart' show distanceMeters;

/// What a warning on a route is about.
enum RouteWarningKind {
  closure,
  jam,
  roadworks,
  event,
  roadWeather,
  wind,
  delay,
}

/// Something on a saved route worth knowing before driving it.
@immutable
class RouteWarning {
  /// Stable id, so the same warning is notified only once.
  final String id;
  final RouteWarningKind kind;

  /// 1 = note, 2 = warning, 3 = serious (closure, ice, severe burja).
  final int severity;
  final String title;
  final String detail;

  /// Where on the map (null for corridor delays).
  final LatLng? position;

  /// Distance from the route's start, for ordering (metres).
  final double along;

  /// The event is on the other carriageway ("v smeri" the route's start).
  final bool opposite;

  const RouteWarning({
    required this.id,
    required this.kind,
    required this.severity,
    required this.title,
    required this.detail,
    required this.position,
    required this.along,
    this.opposite = false,
  });
}

/// A route polyline indexed for "how far is this point from the route".
class RouteIndex {
  final List<LatLng> points;

  /// Distance from the start to each point (metres).
  final List<double> cumulative;
  final Map<int, List<int>> _cells = {};

  RouteIndex(this.points) : cumulative = _cumulative(points) {
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      final la0 = (math.min(a.latitude, b.latitude) * 100).floor();
      final la1 = (math.max(a.latitude, b.latitude) * 100).floor();
      final lo0 = (math.min(a.longitude, b.longitude) * 100).floor();
      final lo1 = (math.max(a.longitude, b.longitude) * 100).floor();
      for (var y = la0; y <= la1; y++) {
        for (var x = lo0; x <= lo1; x++) {
          (_cells[y * 100000 + x] ??= []).add(i);
        }
      }
    }
  }

  double get length => cumulative.isEmpty ? 0 : cumulative.last;

  static List<double> _cumulative(List<LatLng> pts) {
    final out = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      out.add(
        out.last +
            distanceMeters(
              pts[i - 1].latitude,
              pts[i - 1].longitude,
              pts[i].latitude,
              pts[i].longitude,
            ),
      );
    }
    return out;
  }

  /// Distance from [p] to the route and how far along the route that
  /// nearest spot is, or null when farther than [maxMeters].
  ({double distance, double along})? locate(LatLng p, double maxMeters) {
    final rings = (maxMeters / 700).ceil();
    final y0 = (p.latitude * 100).floor(), x0 = (p.longitude * 100).floor();
    var best = maxMeters;
    double? along;
    final seen = <int>{};
    for (var dy = -rings; dy <= rings; dy++) {
      for (var dx = -rings; dx <= rings; dx++) {
        for (final i in _cells[(y0 + dy) * 100000 + (x0 + dx)] ?? const []) {
          if (!seen.add(i)) continue;
          final (d, t) = _segment(p, points[i], points[i + 1]);
          if (d <= best) {
            best = d;
            along = cumulative[i] + t * (cumulative[i + 1] - cumulative[i]);
          }
        }
      }
    }
    return along == null ? null : (distance: best, along: along);
  }

  /// Distance from [p] to segment a→b (metres) and the position on it 0..1.
  static (double, double) _segment(LatLng p, LatLng a, LatLng b) {
    final mLat = 111320.0;
    final mLon = 111320.0 * math.cos(p.latitude * math.pi / 180);
    final ax = (a.longitude - p.longitude) * mLon;
    final ay = (a.latitude - p.latitude) * mLat;
    final bx = (b.longitude - p.longitude) * mLon;
    final by = (b.latitude - p.latitude) * mLat;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final x = ax + t * dx, y = ay + t * dy;
    return (math.sqrt(x * x + y * y), t);
  }

  /// Whether the route passes through the box (grown by [margin] metres).
  bool crossesBox(LatLng sw, LatLng ne, {double margin = 100}) {
    final dLat = margin / 111320.0;
    final dLon = margin / (111320.0 * math.cos(sw.latitude * math.pi / 180));
    for (final p in points) {
      if (p.latitude >= sw.latitude - dLat &&
          p.latitude <= ne.latitude + dLat &&
          p.longitude >= sw.longitude - dLon &&
          p.longitude <= ne.longitude + dLon) {
        return true;
      }
    }
    return false;
  }
}

/// A DARS travel-time corridor ("LJ - KP") with its computed geometry.
@immutable
class Corridor {
  /// Feed titles for the two directions: [forward] follows [points].
  final String forward;
  final String backward;
  final List<LatLng> points;
  const Corridor(this.forward, this.backward, this.points);
}

/// How far an event's spot may be from the route to count as on it.
const double eventRadius = 150;

/// Road stations stand beside the road; a little more slack.
const double stationRadius = 400;

/// Burja is measured at a few spots for whole road sections.
const double windRadius = 3000;

/// Minimum length of a corridor the route must drive for its delay to apply.
const double corridorMinOverlap = 5000;

/// Warnings for a route from the current feeds, most serious first, then in
/// driving order. Pure: the caller passes the feeds and the time.
List<RouteWarning> routeWarnings(
  RouteIndex route, {
  required List<TrafficEvent> events,
  required List<DrsiStation> roadStations,
  required List<BurjaStation> wind,
  required List<TravelTime> travelTimes,
  required List<Corridor> corridors,
  required Set<String> roadRefs,
  required DateTime now,
  String fromName = '',
  String toName = '',
}) {
  final out = <RouteWarning>[];

  for (final e in events) {
    if (e.id.isEmpty || !e.isActive(now)) continue;
    if (e.isBorderCrossing && !e.isJam) continue;
    var hit = e.hasPosition ? route.locate(e.position, eventRadius) : null;
    // Closures and roadworks often only give an area: count it when the
    // route crosses the area on the event's own road.
    if (hit == null &&
        e.hasArea &&
        _onRoads(e.road, roadRefs) &&
        route.crossesBox(e.areaSouthWest!, e.areaNorthEast!)) {
      hit = e.hasPosition
          ? route.locate(e.position, 20000)
          : (distance: 0, along: 0);
    }
    if (hit == null) continue;
    final opposite = isOppositeDirection(
      '${e.title} ${e.description}',
      from: fromName,
      to: toName,
    );
    // A closed rest area is flagged as a closure but the road is open.
    final restArea = _contains('${e.title} ${e.description}', 'počivališč');
    final closed = e.isRoadClosed && !restArea;
    var severity = closed ? 3 : (e.isJam ? 2 : 1);
    if (opposite) severity = 1;
    final delay = e.delaySeconds > 60
        ? ' · +${(e.delaySeconds / 60).round()} min'
        : '';
    final what = e.title.isNotEmpty ? e.title : e.cause;
    final cause = e.cause.isNotEmpty && !_contains(what, e.cause)
        ? ' (${e.cause})'
        : '';
    out.add(
      RouteWarning(
        id: 'ev:${e.id}',
        kind: closed
            ? RouteWarningKind.closure
            : e.isJam
            ? RouteWarningKind.jam
            : e.isRoadworks
            ? RouteWarningKind.roadworks
            : RouteWarningKind.event,
        severity: severity,
        title:
            ['$what$cause', if (e.road.isNotEmpty) e.road].join(' · ') + delay,
        detail: [
          if (opposite) 'V nasprotni smeri.',
          e.description.isNotEmpty ? e.description : e.title,
        ].join(' '),
        position: e.hasPosition ? e.position : null,
        along: hit.along,
        opposite: opposite,
      ),
    );
  }

  for (final s in roadStations) {
    if (s.outage) continue;
    final risk = s.risk;
    if (risk == RoadRisk.ok) continue;
    final hit = route.locate(s.position, stationRadius);
    if (hit == null) continue;
    final temp = s.roadTemp == null
        ? ''
        : ' · cestišče ${s.roadTemp!.toStringAsFixed(1).replaceAll('.', ',')} °C';
    out.add(
      RouteWarning(
        id: 'rw:${s.id}:${risk.name}',
        kind: RouteWarningKind.roadWeather,
        severity: switch (risk) {
          RoadRisk.ice => 3,
          RoadRisk.slippery => 2,
          _ => 1,
        },
        title: switch (risk) {
          RoadRisk.ice => 'Poledica · ${s.name}',
          RoadRisk.slippery => 'Spolzko cestišče · ${s.name}',
          _ => 'Previdno, mrzlo cestišče · ${s.name}',
        },
        detail: [if (s.roadState.isNotEmpty) s.roadState].join() + temp,
        position: s.position,
        along: hit.along,
      ),
    );
  }

  for (final b in wind) {
    final level = b.level;
    if (level == 0) continue;
    final hit = route.locate(b.position, windRadius);
    if (hit == null) continue;
    out.add(
      RouteWarning(
        id: 'wd:${b.id}:$level',
        kind: RouteWarningKind.wind,
        severity: level,
        title: 'Burja ${b.gust.round()} km/h · ${b.title}',
        detail: switch (level) {
          3 => 'Zapore ceste so možne.',
          2 => 'Omejitve za tovornjake in počitniške prikolice so verjetne.',
          _ => 'Pozor pri vleki prikolic in lahkih vozil.',
        },
        position: b.position,
        along: hit.along,
      ),
    );
  }

  final byTitle = {for (final t in travelTimes) t.route.trim(): t};
  for (final c in corridors) {
    final dir = corridorDirection(route, c);
    if (dir == null) continue;
    final t = byTitle[dir ? c.forward : c.backward];
    if (t == null || !(t.isClosed || t.hasDelay)) continue;
    out.add(
      RouteWarning(
        id: 'tt:${t.route}:${t.status.name}',
        kind: RouteWarningKind.delay,
        severity: t.isClosed ? 3 : (t.status == TravelStatus.congested ? 2 : 1),
        title: t.isClosed
            ? 'Zaprto · ${t.route}'
            : 'Zamuda +${t.delayText} · ${t.route}',
        detail: 'Potovalni čas ${t.actualText}.',
        position: null,
        along: 0,
      ),
    );
  }

  out.sort((a, b) {
    final s = b.severity.compareTo(a.severity);
    return s != 0 ? s : a.along.compareTo(b.along);
  });
  return out;
}

bool _contains(String a, String b) => a.toLowerCase().contains(b.toLowerCase());

/// Whether an event text saying "v smeri X" points back to where the route
/// starts (the other carriageway): X shares its stem with [from] and not
/// with [to]. Without a "v smeri" or a clear match, false.
bool isOppositeDirection(
  String text, {
  required String from,
  required String to,
}) {
  final m = RegExp(r'v smeri ([A-Za-zČŠŽčšžĆćĐđ]+)').firstMatch(text);
  if (m == null) return false;
  String stem(String w) {
    final l = w.trim().toLowerCase();
    return l.length <= 4 ? l : l.substring(0, 4);
  }

  final dir = stem(m.group(1)!);
  bool matches(String place) => place
      .split(RegExp(r'[\s/,-]+'))
      .where((w) => w.length >= 3)
      .any((w) => stem(w) == dir);
  return matches(from) && !matches(to);
}

bool _onRoads(String eventRoad, Set<String> routeRefs) {
  final m = RegExp(r'\b([AH]\d+|\d{1,4})\b').firstMatch(eventRoad);
  if (m == null) return false;
  final ref = m.group(1)!;
  return routeRefs.any((r) => r.split(';').contains(ref));
}

/// Whether the route drives corridor [c] forward (true), backward (false),
/// or not enough of it (null).
bool? corridorDirection(RouteIndex route, Corridor c) {
  if (c.points.length < 2) return null;
  final corridor = RouteIndex(c.points);
  double? firstOnCorridor, lastOnCorridor;
  var shared = 0.0;
  for (var i = 0; i + 1 < route.points.length; i++) {
    final a = corridor.locate(route.points[i], 150);
    final b = corridor.locate(route.points[i + 1], 150);
    if (a == null || b == null) continue;
    shared += route.cumulative[i + 1] - route.cumulative[i];
    firstOnCorridor ??= a.along;
    lastOnCorridor = b.along;
  }
  if (shared < corridorMinOverlap) return null;
  return lastOnCorridor! >= firstOnCorridor!;
}
