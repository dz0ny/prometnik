import 'package:latlong2/latlong.dart';

/// A DARS traffic camera from the promet.si data channel `agg.kamere.v2`.
class TrafficCamera {
  final String id;
  final String title;
  final String description;
  final String region;

  /// Live JPEG snapshot URL (kamere.dars.si).
  final String imageUrl;

  final LatLng position;

  const TrafficCamera({
    required this.id,
    required this.title,
    required this.description,
    required this.region,
    required this.imageUrl,
    required this.position,
  });

  /// Cache-busting image URL so each refresh fetches a fresh frame.
  String imageUrlWithBuster(int epochMillis) {
    if (imageUrl.isEmpty) return imageUrl;
    final sep = imageUrl.contains('?') ? '&' : '?';
    return '$imageUrl${sep}t=$epochMillis';
  }

  factory TrafficCamera.fromFeature(Map<String, dynamic> feature) {
    final props = (feature['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    final geom = (feature['geometry'] as Map?)?.cast<String, dynamic>() ?? {};

    LatLng parsePoint(Map<String, dynamic> g) {
      final c = g['coordinates'];
      if (c is List && c.length >= 2) {
        return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
      }
      return const LatLng(46.1512, 14.9955);
    }

    String s(dynamic v) => (v as String?)?.trim() ?? '';

    return TrafficCamera(
      id: s(props['Id']),
      title: s(props['Title']),
      description: s(props['Description']),
      region: s(props['Region']),
      imageUrl: s(props['Image']),
      position: parsePoint(geom),
    );
  }
}
