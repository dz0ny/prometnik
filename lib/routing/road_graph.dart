import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

/// A routable graph of the bundled OSM road lines (`assets/roads.json`).
///
/// Every vertex of a line is a node; lines that share a vertex (junctions)
/// are connected. Edges are stored compactly (CSR) and weighted by travel
/// time from the road class. There is no one-way data: both directions of
/// every edge are open, which is fine for finding warnings along a route.
class RoadGraph {
  final Float64List lat;
  final Float64List lon;

  /// Edges of node `n` are `adjStart[n] .. adjStart[n + 1] - 1`.
  final Int32List adjStart;
  final Int32List adjTo;

  /// Travel time in seconds and length in metres per edge.
  final Float32List adjSeconds;
  final Float32List adjMeters;

  /// Index into [refs] of the road each edge belongs to.
  final Int32List adjRef;
  final List<String> refs;

  /// Nodes per 0.01° grid cell, for snapping a point to the nearest road.
  final Map<int, List<int>> _grid;

  RoadGraph._(
    this.lat,
    this.lon,
    this.adjStart,
    this.adjTo,
    this.adjSeconds,
    this.adjMeters,
    this.adjRef,
    this.refs,
    this._grid,
  );

  int get nodeCount => lat.length;

  /// Builds the graph from road lines: [coords] are flat `lon, lat, …` lists
  /// and [lineRefs] their road numbers ("A1", "409", "" for unnumbered).
  factory RoadGraph.build(List<String> lineRefs, List<Float64List> coords) {
    final ids = <int, int>{};
    final lats = <double>[];
    final lons = <double>[];
    // Vertices closer than ~1 m are the same junction.
    int node(double lo, double la) {
      final key = (lo * 1e5).round() * 100000000 + (la * 1e5).round();
      return ids.putIfAbsent(key, () {
        lats.add(la);
        lons.add(lo);
        return lats.length - 1;
      });
    }

    final from = <int>[];
    final to = <int>[];
    final secs = <double>[];
    final meters = <double>[];
    final refIdx = <int>[];
    final refList = <String>[];
    final refIds = <String, int>{};
    for (var i = 0; i < coords.length; i++) {
      final c = coords[i];
      if (c.length < 4) continue;
      final ref = lineRefs[i];
      final r = refIds.putIfAbsent(ref, () {
        refList.add(ref);
        return refList.length - 1;
      });
      final speed = speedKmh(ref) / 3.6;
      var prev = node(c[0], c[1]);
      for (var j = 2; j + 1 < c.length; j += 2) {
        final cur = node(c[j], c[j + 1]);
        if (cur == prev) continue;
        final m = distanceMeters(lats[prev], lons[prev], lats[cur], lons[cur]);
        for (final (a, b) in [(prev, cur), (cur, prev)]) {
          from.add(a);
          to.add(b);
          secs.add(m / speed);
          meters.add(m);
          refIdx.add(r);
        }
        prev = cur;
      }
    }

    final n = lats.length;
    final start = Int32List(n + 1);
    for (final f in from) {
      start[f + 1]++;
    }
    for (var i = 0; i < n; i++) {
      start[i + 1] += start[i];
    }
    final fill = Int32List.fromList(start.sublist(0, n));
    final e = from.length;
    final adjTo = Int32List(e);
    final adjSec = Float32List(e);
    final adjM = Float32List(e);
    final adjR = Int32List(e);
    for (var k = 0; k < e; k++) {
      final slot = fill[from[k]]++;
      adjTo[slot] = to[k];
      adjSec[slot] = secs[k];
      adjM[slot] = meters[k];
      adjR[slot] = refIdx[k];
    }

    final grid = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      (grid[_cell(lats[i], lons[i])] ??= []).add(i);
    }
    return RoadGraph._(
      Float64List.fromList(lats),
      Float64List.fromList(lons),
      start,
      adjTo,
      adjSec,
      adjM,
      adjR,
      refList,
      grid,
    );
  }

  static int _cell(double la, double lo) =>
      (la * 100).floor() * 100000 + (lo * 100).floor();

  /// Assumed driving speed by Slovenian road number: motorways and
  /// expressways fastest, then main (G), regional (R1–R3) roads, and
  /// unnumbered links (ramps, streets) slowest.
  static double speedKmh(String ref) {
    final r = ref.trim().toUpperCase();
    if (r.isEmpty) return 35;
    if (r.startsWith('A')) return 120;
    if (r.startsWith('H')) return 95;
    final digits = int.tryParse(r.replaceAll(RegExp(r'[^0-9]'), ''));
    if (digits == null) return 50;
    if (digits < 200) return 80; // G1, G2 main roads (1–199)
    if (digits < 400) return 70; // R1
    if (digits < 600) return 60; // R2
    return 50; // R3 and local roads
  }

  /// The node nearest [p] within [maxMeters], or null.
  int? nearestNode(LatLng p, {double maxMeters = 3000}) {
    final rings = (maxMeters / 700).ceil();
    final la = (p.latitude * 100).floor();
    final lo = (p.longitude * 100).floor();
    int? best;
    var bestD = maxMeters;
    for (var dy = -rings; dy <= rings; dy++) {
      for (var dx = -rings; dx <= rings; dx++) {
        final nodes = _grid[(la + dy) * 100000 + (lo + dx)];
        if (nodes == null) continue;
        for (final n in nodes) {
          final d = distanceMeters(p.latitude, p.longitude, lat[n], lon[n]);
          if (d < bestD) {
            bestD = d;
            best = n;
          }
        }
      }
    }
    return best;
  }

  /// Fastest path [from] → [to] (A*); null when they aren't connected.
  /// [penalty] multiplies the time of the given edges (alternatives).
  List<int>? shortestPath(int from, int to, {Map<int, double>? penalty}) {
    if (from == to) return [from];
    final n = nodeCount;
    final g = Float64List(n)..fillRange(0, n, double.infinity);
    final prev = Int32List(n)..fillRange(0, n, -1);
    final closed = Uint8List(n);
    const vmax = 120 / 3.6;
    double h(int a) => distanceMeters(lat[a], lon[a], lat[to], lon[to]) / vmax;
    final heap = _Heap();
    g[from] = 0;
    heap.push(from, h(from));
    while (heap.isNotEmpty) {
      final u = heap.pop();
      if (closed[u] == 1) continue;
      if (u == to) break;
      closed[u] = 1;
      for (var k = adjStart[u]; k < adjStart[u + 1]; k++) {
        final v = adjTo[k];
        if (closed[v] == 1) continue;
        final w = adjSeconds[k] * (penalty?[k] ?? 1);
        final ng = g[u] + w;
        if (ng < g[v]) {
          g[v] = ng;
          prev[v] = u;
          heap.push(v, ng + h(v));
        }
      }
    }
    if (prev[to] == -1) return null;
    final path = <int>[to];
    for (var c = to; c != from; c = prev[c]) {
      path.add(prev[c]);
    }
    return path.reversed.toList();
  }

  /// The edge index from [a] to [b], or -1.
  int edge(int a, int b) {
    for (var k = adjStart[a]; k < adjStart[a + 1]; k++) {
      if (adjTo[k] == b) return k;
    }
    return -1;
  }

  /// Route through [stops] (start, vias, end) plus up to [alternatives]
  /// further routes that avoid most of the first. Empty when unreachable.
  List<RoadRoute> routes(List<LatLng> stops, {int alternatives = 2}) {
    final nodes = <int>[];
    for (final s in stops) {
      final n = nearestNode(s);
      if (n == null) return const [];
      nodes.add(n);
    }
    final out = <RoadRoute>[];
    final penalty = <int, double>{};
    for (var attempt = 0; attempt <= alternatives * 2; attempt++) {
      final path = <int>[];
      for (var i = 0; i + 1 < nodes.length; i++) {
        final leg = shortestPath(nodes[i], nodes[i + 1], penalty: penalty);
        if (leg == null) return out;
        path.addAll(path.isEmpty ? leg : leg.skip(1));
      }
      final route = _toRoute(path);
      // Keep only routes that differ enough from the ones found already.
      if (out.every((r) => route.overlap(r) < 0.8)) out.add(route);
      if (out.length > alternatives) break;
      for (final e in route.edges) {
        penalty[e] = (penalty[e] ?? 1) * 1.6;
        final back = edge(adjTo[e], _edgeFrom(e));
        if (back >= 0) penalty[back] = (penalty[back] ?? 1) * 1.6;
      }
    }
    return out;
  }

  int _edgeFrom(int e) {
    // Binary search the CSR start array for the edge's source node.
    var lo = 0, hi = nodeCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (adjStart[mid] <= e) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  RoadRoute _toRoute(List<int> path) {
    final edges = <int>[];
    var meters = 0.0, seconds = 0.0;
    final refs = <String>[];
    for (var i = 0; i + 1 < path.length; i++) {
      final e = edge(path[i], path[i + 1]);
      if (e < 0) continue;
      edges.add(e);
      meters += adjMeters[e];
      seconds += adjSeconds[e];
      final r = this.refs[adjRef[e]];
      if (r.isNotEmpty && (refs.isEmpty || refs.last != r)) refs.add(r);
    }
    return RoadRoute(
      points: [for (final n in path) LatLng(lat[n], lon[n])],
      edges: edges,
      meters: meters,
      seconds: seconds,
      roadRefs: refs,
    );
  }
}

/// One computed route.
class RoadRoute {
  final List<LatLng> points;

  /// Graph edges used, for telling alternatives apart.
  final List<int> edges;
  final double meters;
  final double seconds;

  /// Road numbers in driving order, without repeats ("A1", "409", …).
  final List<String> roadRefs;

  const RoadRoute({
    required this.points,
    required this.edges,
    required this.meters,
    required this.seconds,
    required this.roadRefs,
  });

  /// Share of this route's edges (by count) also in [other], ignoring
  /// direction.
  double overlap(RoadRoute other) {
    if (edges.isEmpty) return 1;
    final mine = {for (var i = 0; i + 1 < points.length; i++) _seg(i)};
    final theirs = {
      for (var i = 0; i + 1 < other.points.length; i++) other._seg(i),
    };
    return mine.intersection(theirs).length / mine.length;
  }

  String _seg(int i) {
    final a = points[i], b = points[i + 1];
    final x =
        '${a.latitude.toStringAsFixed(5)},${a.longitude.toStringAsFixed(5)}';
    final y =
        '${b.latitude.toStringAsFixed(5)},${b.longitude.toStringAsFixed(5)}';
    return x.compareTo(y) < 0 ? '$x|$y' : '$y|$x';
  }
}

/// Great-circle distance in metres (haversine).
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = p2 - p1, dl = (lon2 - lon1) * math.pi / 180;
  final a =
      math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// A binary min-heap of (node, priority).
class _Heap {
  final _nodes = <int>[];
  final _prio = <double>[];

  bool get isNotEmpty => _nodes.isNotEmpty;

  void push(int n, double p) {
    _nodes.add(n);
    _prio.add(p);
    var i = _nodes.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_prio[parent] <= _prio[i]) break;
      _swap(i, parent);
      i = parent;
    }
  }

  int pop() {
    final top = _nodes.first;
    final lastN = _nodes.removeLast();
    final lastP = _prio.removeLast();
    if (_nodes.isNotEmpty) {
      _nodes[0] = lastN;
      _prio[0] = lastP;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _nodes.length && _prio[l] < _prio[m]) m = l;
        if (r < _nodes.length && _prio[r] < _prio[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final n = _nodes[a];
    _nodes[a] = _nodes[b];
    _nodes[b] = n;
    final p = _prio[a];
    _prio[a] = _prio[b];
    _prio[b] = p;
  }
}
