import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'roads_service.dart';

class RoadPreviewSimplifier {
  RoadPreviewSimplifier._();

  static const double defaultToleranceMeters = 180;
  static final Map<String, Future<List<RoadLine>>> _roadsInCache = {};
  static final Map<String, Future<List<RoadLine>>> _roadsByRefsInCache = {};

  static Future<List<RoadLine>> roadsIn(
    double w,
    double s,
    double e,
    double n, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    final key = [
      'area',
      _coord(w),
      _coord(s),
      _coord(e),
      _coord(n),
      toleranceMeters.round(),
    ].join(':');
    return _cached(_roadsInCache, key, () async {
      final roads = await RoadsService.instance.roadsIn(w, s, e, n);
      return simplifyRoads(roads, toleranceMeters: toleranceMeters);
    });
  }

  static Future<List<RoadLine>> roadsByRefsIn(
    Set<String> refs,
    double w,
    double s,
    double e,
    double n, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    final sortedRefs = refs.toList()..sort();
    final key = [
      'refs',
      sortedRefs.join(','),
      _coord(w),
      _coord(s),
      _coord(e),
      _coord(n),
      toleranceMeters.round(),
    ].join(':');
    return _cached(_roadsByRefsInCache, key, () async {
      final roads = await RoadsService.instance.roadsByRefsIn(refs, w, s, e, n);
      return simplifyRoads(roads, toleranceMeters: toleranceMeters);
    });
  }

  static const int _maxCacheEntries = 200;

  /// Memoise [load] under [key]; failures are evicted so they can be retried,
  /// and the cache is bounded (oldest entry dropped first).
  static Future<List<RoadLine>> _cached(
    Map<String, Future<List<RoadLine>>> cache,
    String key,
    Future<List<RoadLine>> Function() load,
  ) {
    final hit = cache.remove(key);
    if (hit != null) return cache[key] = hit; // re-insert as most recent
    if (cache.length >= _maxCacheEntries) cache.remove(cache.keys.first);
    final future = load();
    cache[key] = future;
    future.catchError((Object _) {
      if (identical(cache[key], future)) cache.remove(key);
      return const <RoadLine>[];
    });
    return future;
  }

  static List<RoadLine> simplifyRoads(
    List<RoadLine> roads, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    return [
      for (final road in roads)
        RoadLine(
          road.ref,
          road.name,
          simplifyPoints(road.points, toleranceMeters: toleranceMeters),
        ),
    ];
  }

  static List<LatLng> simplifyPoints(
    List<LatLng> points, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    if (points.length <= 2) return points;
    final keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;
    _simplifyRange(points, 0, points.length - 1, toleranceMeters, keep);
    return [
      for (var i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ];
  }

  static void _simplifyRange(
    List<LatLng> points,
    int first,
    int last,
    double toleranceMeters,
    List<bool> keep,
  ) {
    if (last <= first + 1) return;
    var maxDistance = 0.0;
    var index = first;
    for (var i = first + 1; i < last; i++) {
      final distance = _pointSegmentDistance(
        points[i],
        points[first],
        points[last],
      );
      if (distance > maxDistance) {
        index = i;
        maxDistance = distance;
      }
    }
    if (maxDistance <= toleranceMeters) return;
    keep[index] = true;
    _simplifyRange(points, first, index, toleranceMeters, keep);
    _simplifyRange(points, index, last, toleranceMeters, keep);
  }

  static double _pointSegmentDistance(LatLng point, LatLng start, LatLng end) {
    const metersPerLat = 111320.0;
    final metersPerLon = 111320.0 * cos(point.latitude * pi / 180);
    final px = point.longitude * metersPerLon;
    final py = point.latitude * metersPerLat;
    final ax = start.longitude * metersPerLon;
    final ay = start.latitude * metersPerLat;
    final bx = end.longitude * metersPerLon;
    final by = end.latitude * metersPerLat;
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final ex = px - cx;
    final ey = py - cy;
    return sqrt(ex * ex + ey * ey);
  }

  static int _coord(double value) => (value * 1000000).round();
}
