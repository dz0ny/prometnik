import 'package:latlong2/latlong.dart';

/// Severity classes for a traffic event, used to colour markers/tiles.
enum EventSeverity { closed, jam, roadworks, other }

/// Managing authority / data source of an event (from `NoticeText`).
enum EventSource { drsi, dars, other }

/// A traffic event / incident from the public promet.si data channel
/// `agg.dogodki.v2` (a GeoJSON FeatureCollection of Point features).
class TrafficEvent {
  final String id;
  final LatLng position;

  final String title;
  final String description;

  /// Road designation, e.g. "A1-E57", "R3-671".
  final String road;

  /// Road class code from `Kategorija` (A1/A2/A5, G2, R1/R3/RT, LC/LG/LZ/LK, NK).
  final String category;

  /// Short cause, e.g. "dela", "popolna zapora", "zastoj".
  final String cause;

  /// Road designation without the Euroroute suffix, e.g. "A1-E57" → "A1",
  /// "R3-651" → "R3-651". Used for watched-road matching.
  String get roadDesignation =>
      road.replaceFirst(RegExp(r'-E\d+.*$'), '').trim();

  /// Raw icon name from the feed (e.g. "zaprta.png", "nesreca.png"), used to
  /// pick a cause-specific icon.
  final String iconName;

  /// Small badge text shown by the source app, e.g. "Od 22.5.".
  final String sideContent;

  final bool isRoadClosed;
  final bool isJam; // IsZastoj
  final bool isRoadworks; // IsDelo
  final bool isBorderCrossing; // isMejniPrehod

  /// Queue length in metres (0 when none).
  final int queueLength;

  /// Estimated delay in seconds (0 when none).
  final int delaySeconds;

  /// Lower number = higher priority (1 highest).
  final int priority;

  final DateTime? validFrom;
  final DateTime? validTo;
  final DateTime? updated;
  final DateTime? estimatedEnd;

  /// Data owner attribution, e.g. "Direkcija RS za infrastrukturo".
  final String noticeText;

  /// Optional external link for more info (may be empty).
  final String infoUrl;

  /// Affected-area bounding box (from `ServiceArea.bbox`), or null. The open
  /// feed only provides this extent — not the precise route polyline (that is
  /// computed by a separate routing service).
  final LatLng? areaSouthWest;
  final LatLng? areaNorthEast;

  bool get hasArea => areaSouthWest != null && areaNorthEast != null;

  const TrafficEvent({
    required this.id,
    required this.position,
    required this.title,
    required this.description,
    required this.road,
    required this.category,
    required this.cause,
    required this.iconName,
    required this.sideContent,
    required this.isRoadClosed,
    required this.isJam,
    required this.isRoadworks,
    required this.isBorderCrossing,
    required this.queueLength,
    required this.delaySeconds,
    required this.priority,
    required this.validFrom,
    required this.validTo,
    required this.updated,
    required this.estimatedEnd,
    required this.noticeText,
    required this.infoUrl,
    required this.areaSouthWest,
    required this.areaNorthEast,
  });

  EventSeverity get severity {
    if (isRoadClosed) return EventSeverity.closed;
    if (isJam) return EventSeverity.jam;
    if (isRoadworks) return EventSeverity.roadworks;
    return EventSeverity.other;
  }

  /// Managing authority, derived from [noticeText]:
  /// DARS (motorways/expressways), DRSI (state roads), or other (municipal).
  EventSource get source {
    final t = noticeText.toLowerCase();
    if (t.contains('dars')) return EventSource.dars;
    if (t.contains('direkcij')) return EventSource.drsi;
    return EventSource.other;
  }

  /// Whether the event is active at [now] (defaults to current time). Events
  /// without a validity window are treated as active.
  bool isActive([DateTime? now]) {
    final t = now ?? DateTime.now();
    if (validFrom != null && t.isBefore(validFrom!)) return false;
    if (validTo != null && t.isAfter(validTo!)) return false;
    return true;
  }

  /// Build from a single GeoJSON `Feature` of the `agg.dogodki.v2` collection.
  factory TrafficEvent.fromFeature(Map<String, dynamic> feature) {
    final props = (feature['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    final geom = (feature['geometry'] as Map?)?.cast<String, dynamic>() ?? {};

    LatLng parsePoint(Map<String, dynamic> g) {
      final coords = g['coordinates'];
      // GeoJSON Point coordinates are [lon, lat].
      if (coords is List && coords.length >= 2) {
        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        return LatLng(lat, lon);
      }
      return const LatLng(46.1512, 14.9955); // Slovenia centre fallback
    }

    bool toBool(dynamic v) => v == true || v == 'true' || v == 1;
    int toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    String toStr(dynamic v) => (v as String?)?.trim() ?? '';
    DateTime? toDate(dynamic v) =>
        (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

    // ServiceArea.bbox is [minLon, minLat, maxLon, maxLat].
    LatLng? areaSW, areaNE;
    final sa = props['ServiceArea'];
    if (sa is Map && sa['bbox'] is List && (sa['bbox'] as List).length == 4) {
      final bb = (sa['bbox'] as List).map((e) => (e as num).toDouble()).toList();
      if (bb[2] > bb[0] && bb[3] > bb[1]) {
        areaSW = LatLng(bb[1], bb[0]);
        areaNE = LatLng(bb[3], bb[2]);
      }
    }

    return TrafficEvent(
      id: toStr(props['Id']),
      position: parsePoint(geom),
      title: toStr(props['Title']),
      description: toStr(props['Description']),
      road: toStr(props['Cesta']),
      category: toStr(props['Kategorija']),
      cause: toStr(props['VzrokShortName']),
      iconName: toStr(props['Icon']),
      sideContent: toStr(props['SideContent']),
      isRoadClosed: toBool(props['IsRoadClosed']),
      isJam: toBool(props['IsZastoj']),
      isRoadworks: toBool(props['IsDelo']),
      isBorderCrossing: toBool(props['isMejniPrehod']),
      queueLength: toInt(props['QueueLength']),
      delaySeconds: toInt(props['DelaySeconds']),
      priority: toInt(props['PrioritetaVal']),
      validFrom: toDate(props['VeljavnostOd']),
      validTo: toDate(props['VeljavnostDo']),
      updated: toDate(props['Updated']),
      estimatedEnd: toDate(props['PredvidenKonec']),
      noticeText: toStr(props['NoticeText']),
      infoUrl: toStr(props['AdditionalInfoUrl']),
      areaSouthWest: areaSW,
      areaNorthEast: areaNE,
    );
  }
}
