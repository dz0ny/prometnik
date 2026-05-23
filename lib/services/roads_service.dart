import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

/// A road polyline with its OSM `ref` (road number, e.g. "A1", "651") and name.
class RoadLine {
  final String ref;
  final String name;
  final List<LatLng> points;
  const RoadLine(this.ref, this.name, this.points);
}

typedef _Parsed = (List<String> refs, List<String> names, List<Float64List>);

/// Loads bundled Slovenian road geometry (OSM via Geofabrik, ODbL) with road
/// numbers/names and returns roads within a bounding box. Used to highlight the
/// roads inside a traffic event's affected area.
///
/// `assets/roads.json` is an array of `[ref, name, [lon, lat, …]]`. Parsing
/// runs once, off the main thread.
class RoadsService {
  RoadsService._();
  static final RoadsService instance = RoadsService._();

  List<String>? _refs;
  List<String>? _names;
  List<Float64List>? _coords;
  Float64List? _west, _south, _east, _north;
  Future<void>? _loading;

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final raw = await rootBundle.loadString('assets/roads.json');
    final (refs, names, coords) = await compute(_parse, raw);
    final n = coords.length;
    final w = Float64List(n), s = Float64List(n);
    final e = Float64List(n), no = Float64List(n);
    for (var i = 0; i < n; i++) {
      final f = coords[i];
      var minLon = double.infinity, minLat = double.infinity;
      var maxLon = -double.infinity, maxLat = -double.infinity;
      for (var j = 0; j + 1 < f.length; j += 2) {
        final lon = f[j], lat = f[j + 1];
        if (lon < minLon) minLon = lon;
        if (lon > maxLon) maxLon = lon;
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
      }
      w[i] = minLon;
      s[i] = minLat;
      e[i] = maxLon;
      no[i] = maxLat;
    }
    _refs = refs;
    _names = names;
    _coords = coords;
    _west = w;
    _south = s;
    _east = e;
    _north = no;
  }

  static _Parsed _parse(String str) {
    final raw = json.decode(str) as List;
    final refs = <String>[];
    final names = <String>[];
    final coords = <Float64List>[];
    for (final item in raw) {
      final l = item as List;
      refs.add(l[0] as String);
      names.add(l[1] as String);
      coords.add(
        Float64List.fromList([for (final v in l[2] as List) (v as num).toDouble()]),
      );
    }
    return (refs, names, coords);
  }

  /// Roads whose bounding box intersects [w,s,e,n] (lon/lat degrees).
  Future<List<RoadLine>> roadsIn(
    double w,
    double s,
    double e,
    double n,
  ) async {
    await _ensureLoaded();
    final coords = _coords!;
    final out = <RoadLine>[];
    for (var i = 0; i < coords.length; i++) {
      if (_east![i] < w || _west![i] > e || _north![i] < s || _south![i] > n) {
        continue;
      }
      final f = coords[i];
      final pts = <LatLng>[];
      for (var j = 0; j + 1 < f.length; j += 2) {
        pts.add(LatLng(f[j + 1], f[j]));
      }
      out.add(RoadLine(_refs![i], _names![i], pts));
    }
    return out;
  }
}

/// Derives the OSM `ref` (road number) from a DRSI `Cesta` string, or null.
/// Examples: "A1-E57"→"A1", "A5"→"A5", "H4"→"H4", "R3-651"→"651", "RT-924"→"924".
String? eventRoadRef(String cesta) {
  if (cesta.isEmpty) return null;
  final c = cesta.toUpperCase().trim();
  if (c.startsWith('A') || c.startsWith('H')) {
    return c.split('-').first; // motorway / expressway code
  }
  final dash = c.indexOf('-');
  final rest = dash >= 0 ? c.substring(dash + 1) : c;
  final m = RegExp(r'^\d+').firstMatch(rest);
  return m?.group(0);
}

/// Whether an OSM `ref` (possibly "A1;A2") matches the event's road number.
bool roadRefMatches(String? eventRef, String osmRef) {
  if (eventRef == null || eventRef.isEmpty || osmRef.isEmpty) return false;
  for (final r in osmRef.toUpperCase().split(RegExp(r'[;,/ ]+'))) {
    if (r.trim() == eventRef) return true;
  }
  return false;
}
