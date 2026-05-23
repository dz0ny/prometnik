import 'package:latlong2/latlong.dart';

/// A crosswind (burja) measurement point from promet.si `agg.burja.v2`.
class BurjaStation {
  final String id;
  final String title;
  final String description;
  final LatLng position;

  /// Sustained wind and gust speed in km/h.
  final double wind;
  final double gust;

  const BurjaStation({
    required this.id,
    required this.title,
    required this.description,
    required this.position,
    required this.wind,
    required this.gust,
  });

  /// Severity level 0–3 based on gust speed (km/h), aligned with the typical
  /// burja escalation (caravans → trailers → trucks → closure).
  int get level {
    if (gust >= 110) return 3; // severe — closures likely
    if (gust >= 80) return 2; // strong — trucks/caravans restricted
    if (gust >= 50) return 1; // moderate — caravans warned
    return 0; // calm
  }

  factory BurjaStation.fromFeature(Map<String, dynamic> feature) {
    final p = (feature['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    final g = (feature['geometry'] as Map?)?.cast<String, dynamic>() ?? {};

    LatLng point() {
      final c = g['coordinates'];
      if (c is List && c.length >= 2) {
        return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
      }
      return const LatLng(46.1512, 14.9955);
    }

    String s(dynamic v) => (v as String?)?.trim() ?? '';
    double d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

    return BurjaStation(
      id: s(p['Id']),
      title: s(p['Title']),
      description: s(p['Description']),
      position: point(),
      wind: d(p['veter']),
      gust: d(p['sunki']),
    );
  }
}
