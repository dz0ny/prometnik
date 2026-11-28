import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// A named place on a route (start, via or end).
@immutable
class RoutePlace {
  final String name;
  final LatLng position;
  const RoutePlace(this.name, this.position);

  Map<String, Object> toJson() => {
    'n': name,
    'la': position.latitude,
    'lo': position.longitude,
  };

  static RoutePlace? fromJson(Object? j) {
    if (j is! Map) return null;
    final la = j['la'], lo = j['lo'];
    if (la is! num || lo is! num) return null;
    return RoutePlace('${j['n'] ?? ''}', LatLng(la.toDouble(), lo.toDouble()));
  }

  @override
  bool operator ==(Object other) =>
      other is RoutePlace && other.name == name && other.position == position;

  @override
  int get hashCode => Object.hash(name, position);
}

/// A route the user saved: where it goes, the road geometry picked in the
/// editor, and when it is driven (for warnings before departure).
@immutable
class SavedRoute {
  final String id;
  final String name;

  /// Start, vias and end, in order.
  final List<RoutePlace> places;

  /// The chosen road geometry.
  final List<LatLng> points;

  /// Road numbers in driving order ("A1", "409").
  final List<String> roadRefs;
  final double meters;
  final double seconds;

  /// Weekdays it is driven (1 = Monday … 7 = Sunday); empty = no schedule.
  final Set<int> days;

  /// Departure time in minutes after midnight; null = no schedule.
  final int? departureMinutes;

  const SavedRoute({
    required this.id,
    required this.name,
    required this.places,
    required this.points,
    required this.roadRefs,
    required this.meters,
    required this.seconds,
    this.days = const {},
    this.departureMinutes,
  });

  bool get hasSchedule => days.isNotEmpty && departureMinutes != null;

  SavedRoute copyWith({
    String? name,
    Set<int>? days,
    int? Function()? departureMinutes,
  }) => SavedRoute(
    id: id,
    name: name ?? this.name,
    places: places,
    points: points,
    roadRefs: roadRefs,
    meters: meters,
    seconds: seconds,
    days: days ?? this.days,
    departureMinutes: departureMinutes != null
        ? departureMinutes()
        : this.departureMinutes,
  );

  /// The next departure at or after [now] (local time), within a week;
  /// null without a schedule.
  DateTime? nextDeparture(DateTime now) {
    final m = departureMinutes;
    if (m == null || days.isEmpty) return null;
    for (var d = 0; d < 8; d++) {
      final day = DateTime(now.year, now.month, now.day + d);
      if (!days.contains(day.weekday)) continue;
      final at = day.add(Duration(minutes: m));
      if (!at.isBefore(now)) return at;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'places': [for (final p in places) p.toJson()],
    'geo': encodePolyline(points),
    'refs': roadRefs,
    'm': meters,
    's': seconds,
    'days': days.toList()..sort(),
    'dep': departureMinutes,
  };

  static SavedRoute? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], geo = j['geo'];
    if (id is! String || geo is! String) return null;
    final places = [
      for (final p in (j['places'] as List? ?? const []))
        ?RoutePlace.fromJson(p),
    ];
    final points = decodePolyline(geo);
    if (places.length < 2 || points.length < 2) return null;
    return SavedRoute(
      id: id,
      name: '${j['name'] ?? ''}',
      places: places,
      points: points,
      roadRefs: [for (final r in (j['refs'] as List? ?? const [])) '$r'],
      meters: (j['m'] as num?)?.toDouble() ?? 0,
      seconds: (j['s'] as num?)?.toDouble() ?? 0,
      days: {
        for (final d in (j['days'] as List? ?? const []))
          if (d is int && d >= 1 && d <= 7) d,
      },
      departureMinutes: j['dep'] is int ? j['dep'] as int : null,
    );
  }

  static String encodeList(List<SavedRoute> routes) =>
      jsonEncode([for (final r in routes) r.toJson()]);

  /// Saved routes from [raw]; broken entries are skipped.
  static List<SavedRoute> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final j in list) ?SavedRoute.fromJson(j)];
    } on FormatException {
      return const [];
    }
  }
}

/// Google's encoded polyline format (precision 5): compact route storage.
String encodePolyline(List<LatLng> points) {
  final out = StringBuffer();
  var pLat = 0, pLon = 0;
  void enc(int v) {
    var s = v < 0 ? ~(v << 1) : v << 1;
    while (s >= 0x20) {
      out.writeCharCode((0x20 | (s & 0x1f)) + 63);
      s >>= 5;
    }
    out.writeCharCode(s + 63);
  }

  for (final p in points) {
    final la = (p.latitude * 1e5).round(), lo = (p.longitude * 1e5).round();
    enc(la - pLat);
    enc(lo - pLon);
    pLat = la;
    pLon = lo;
  }
  return out.toString();
}

List<LatLng> decodePolyline(String s) {
  final out = <LatLng>[];
  var i = 0, la = 0, lo = 0;
  int? dec() {
    var shift = 0, result = 0;
    while (true) {
      if (i >= s.length) return null;
      final b = s.codeUnitAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
      if (b < 0x20) break;
    }
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (i < s.length) {
    final dla = dec(), dlo = dec();
    if (dla == null || dlo == null) break;
    la += dla;
    lo += dlo;
    out.add(LatLng(la / 1e5, lo / 1e5));
  }
  return out;
}
