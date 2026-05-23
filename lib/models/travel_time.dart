/// Live status of a travel-time route.
enum TravelStatus { normal, slow, congested, closed }

/// A travel-time route from the promet.si data channel `agg.potovalnicasi.v2`.
///
/// These features have no geometry — each is a named route (e.g. "LJ -
/// Karavanke") with the current travel time and the delay versus free-flow.
class TravelTime {
  final String id;

  /// Route name, e.g. "LJ - Karavanke".
  final String route;

  /// Current travel time in milliseconds.
  final int actualMs;

  /// Human-readable travel time, e.g. "38 min".
  final String actualText;

  /// Extra time versus free-flow, in milliseconds.
  final int delayMs;

  /// Human-readable delay, e.g. "3 min".
  final String delayText;

  final bool isClosed;
  final TravelStatus status;

  const TravelTime({
    required this.id,
    required this.route,
    required this.actualMs,
    required this.actualText,
    required this.delayMs,
    required this.delayText,
    required this.isClosed,
    required this.status,
  });

  /// Whether the delay is significant enough to surface (> ~1 min).
  bool get hasDelay => !isClosed && delayMs > 60000;

  factory TravelTime.fromFeature(Map<String, dynamic> feature) {
    final props = (feature['properties'] as Map?)?.cast<String, dynamic>() ?? {};

    int toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    String toStr(dynamic v) => (v as String?)?.trim() ?? '';
    bool toBool(dynamic v) => v == true || v == 'true' || v == 1;

    final closed = toBool(props['IsClosed']);
    final delayMs = toInt(props['Delay']);
    final rawStatus = toStr(props['Status']).toLowerCase();

    // Lenient colouring: small delays stay "normal" (green). Only sizeable
    // delays escalate to amber/orange.
    TravelStatus status;
    if (closed) {
      status = TravelStatus.closed;
    } else if (delayMs >= 1500000 ||
        rawStatus.contains('zast') ||
        rawStatus.contains('congest') ||
        rawStatus.contains('heavy')) {
      status = TravelStatus.congested; // ~25 min+ or explicit congestion
    } else if (delayMs >= 600000) {
      status = TravelStatus.slow; // ~10 min+
    } else {
      status = TravelStatus.normal;
    }

    return TravelTime(
      id: toStr(props['Id']),
      route: toStr(props['Title']),
      actualMs: toInt(props['Actual']),
      actualText: toStr(props['ActualDescription']),
      delayMs: delayMs,
      delayText: toStr(props['DelayDescription']),
      isClosed: closed,
      status: status,
    );
  }
}
