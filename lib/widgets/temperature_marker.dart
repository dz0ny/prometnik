import 'package:flutter/material.dart';

import '../models/drsi_station.dart';
import '../models/weather_station.dart';
import '../theme/app_theme.dart';
import 'drsi_sheet.dart' show drsiRiskColor;
import 'webcam_thumbnail.dart';

// ── Map pin system ───────────────────────────────────────────────────────
// Every map point (weather station, DRSI road station, combined pin, camera,
// camera cluster) shares one visual language: a white-rimmed capsule with a
// soft shadow, coloured segments tinted by temperature and a small round
// badge icon telling air / road / camera apart. Cameras without a reading
// are round badges in the same style.

/// Shared look of the map pins.
abstract final class MapPinStyle {
  /// Outer height of a capsule (rim included).
  static const double pillHeight = 26;

  /// White rim around pins.
  static const double rim = 1.5;

  /// Diameter of the round badge inside a segment.
  static const double badgeSize = 18;

  /// Diameter of a stand-alone camera badge.
  static const double cameraSize = 26;

  /// Pointer tail under a capsule (drawn 2 px under the capsule).
  static const Size tailSize = Size(12, 7);

  /// Height of a capsule plus its tail.
  static const double pinHeight = pillHeight + 5;

  /// Neutral fill for cameras and readings without a temperature.
  static const Color cameraColor = Color(0xFF3A4B5E);

  static const List<BoxShadow> shadow = [
    BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x26000000), blurRadius: 1.5, offset: Offset(0, 1)),
  ];

  /// Text/icon colour that reads on [bg].
  static Color foregroundOn(Color bg) =>
      bg.computeLuminance() < 0.45 ? Colors.white : const Color(0xDD000000);

  static Color lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// Rounded whole degrees, without a "-0" for small negatives.
  static String degrees(double t) {
    final r = t.round();
    return '${r == 0 ? 0 : r}°';
  }
}

/// One coloured part of a [MapPill].
@immutable
class MapPinSegment {
  /// Segment fill (usually [AppTheme.temperatureColor]).
  final Color color;

  /// Badge icon: air thermometer, road, camera…
  final IconData icon;

  /// Value next to the badge; null for a badge-only segment.
  final String? text;

  /// Fills the badge instead of the default white disc (e.g. a DRSI ice
  /// risk), with a white icon on top.
  final Color? badgeColor;

  const MapPinSegment({
    required this.color,
    required this.icon,
    this.text,
    this.badgeColor,
  });

  /// Rough rendered width, for sizing the Marker box (hit area/culling).
  double get estimatedWidth => text == null
      ? 3.5 + MapPinStyle.badgeSize + 3.5
      : 3.5 + MapPinStyle.badgeSize + 4 + 8.5 * text!.length + 8;
}

/// The capsule pin: [segments] side by side inside a white rim, optionally
/// with a pointer [tail] whose tip marks the coordinate.
class MapPill extends StatelessWidget {
  final List<MapPinSegment> segments;
  final bool tail;

  const MapPill({super.key, required this.segments, this.tail = true});

  /// Rough rendered width of a pill with [segments] (rim included).
  static double estimateWidth(List<MapPinSegment> segments) {
    var w = MapPinStyle.rim * 2;
    for (final s in segments) {
      w += s.estimatedWidth;
    }
    return w;
  }

  @override
  Widget build(BuildContext context) {
    const inner = MapPinStyle.pillHeight - MapPinStyle.rim * 2;
    final capsule = DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(
          Radius.circular(MapPinStyle.pillHeight / 2),
        ),
        boxShadow: MapPinStyle.shadow,
      ),
      // The coloured segments are clipped *inside* the white rim (instead of
      // stroking a border over them), which leaves no colour fringe.
      child: Padding(
        padding: const EdgeInsets.all(MapPinStyle.rim),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(inner / 2)),
          child: SizedBox(
            height: inner,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, s) in segments.indexed) ...[
                  if (i > 0)
                    const SizedBox(
                      width: 1,
                      child: ColoredBox(color: Color(0xCCFFFFFF)),
                    ),
                  _Segment(segment: s, last: i == segments.length - 1),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    // Pins are map glyphs with a fixed height: let the value grow a little
    // with the text size, but never spill out of the capsule.
    if (!tail) {
      return MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: capsule,
      );
    }
    final pin = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        capsule,
        // Drawn slightly under the capsule to hide the seam.
        Transform.translate(
          offset: const Offset(0, -2),
          child: CustomPaint(
            size: MapPinStyle.tailSize,
            // Under a multi-colour capsule the tail is white, so it never
            // clashes with the segment above it.
            painter: _PointerPainter(
              color: segments.length == 1
                  ? segments.single.color
                  : Colors.white,
            ),
          ),
        ),
      ],
    );
    return MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: pin);
  }
}

class _Segment extends StatelessWidget {
  final MapPinSegment segment;
  final bool last;

  const _Segment({required this.segment, required this.last});

  @override
  Widget build(BuildContext context) {
    final s = segment;
    final fg = MapPinStyle.foregroundOn(s.color);
    final badgeBg = s.badgeColor ?? Colors.white.withValues(alpha: 0.95);
    final badgeFg = s.badgeColor != null
        ? MapPinStyle.foregroundOn(s.badgeColor!)
        : s.color.computeLuminance() > 0.6
        ? const Color(0xDD000000)
        : s.color;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MapPinStyle.lighten(s.color, 0.08), s.color],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          3.5,
          0,
          s.text == null ? 3.5 : (last ? 8 : 6),
          0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: MapPinStyle.badgeSize,
              height: MapPinStyle.badgeSize,
              decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
              child: Icon(s.icon, size: 12, color: badgeFg),
            ),
            if (s.text != null) ...[
              const SizedBox(width: 4),
              Text(
                s.text!,
                maxLines: 1,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A round camera badge in the pin style (no reading, just a camera).
class MapCameraBadge extends StatelessWidget {
  final double size;

  const MapCameraBadge({super.key, this.size = MapPinStyle.cameraSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            MapPinStyle.lighten(MapPinStyle.cameraColor, 0.08),
            MapPinStyle.cameraColor,
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: MapPinStyle.rim),
        boxShadow: MapPinStyle.shadow,
      ),
      child: Icon(Icons.videocam, size: size * 0.52, color: Colors.white),
    );
  }
}

/// Several cameras merged at a low zoom: a camera capsule with the count.
class MapClusterBadge extends StatelessWidget {
  final int count;

  const MapClusterBadge({super.key, required this.count});

  /// Rough rendered width for [count], for sizing the Marker box.
  static double estimateWidth(int count) => MapPill.estimateWidth([
    MapPinSegment(
      color: MapPinStyle.cameraColor,
      icon: Icons.videocam,
      text: '$count',
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    return MapPill(
      tail: false,
      segments: [
        MapPinSegment(
          color: MapPinStyle.cameraColor,
          icon: Icons.videocam,
          text: '$count',
        ),
      ],
    );
  }
}

/// Fades and scales [child] in the first time a pin with [id] mounts.
///
/// [seen] is owned by the marker layer: flutter_map culls off-screen
/// markers, so a pin panned back into view re-mounts, and must not replay
/// the animation. Only transform and opacity change, never layout.
class MapPopIn extends StatefulWidget {
  final Object id;
  final Set<Object> seen;
  final Alignment alignment;
  final Widget child;

  const MapPopIn({
    super.key,
    required this.id,
    required this.seen,
    this.alignment = Alignment.center,
    required this.child,
  });

  @override
  State<MapPopIn> createState() => _MapPopInState();
}

class _MapPopInState extends State<MapPopIn> {
  late final bool _animate = widget.seen.add(widget.id);

  @override
  Widget build(BuildContext context) {
    if (!_animate || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return widget.child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      child: widget.child,
      // Same widget structure at every t (also once done): swapping in the
      // bare child would remount it and reload its webcam frame. At t = 1
      // the opacity paints straight through and the scale is identity.
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.55 + 0.45 * t,
            alignment: widget.alignment,
            child: child,
          ),
        );
      },
    );
  }
}

/// A map pin that shows a station's air temperature (and, when a DRSI road
/// station shares the spot, its road temperature) in a [MapPill] whose
/// pointer tip sits on the exact location. Camera-only stations without a
/// road reading render as a [MapCameraBadge].
///
/// Place the Marker with `alignment: Alignment.topCenter` so the box sits
/// above the point and the pointer tip at its bottom centre.
class TemperatureMarker extends StatelessWidget {
  final WeatherStation station;
  final VoidCallback onTap;

  /// When set (zoomed in), a live webcam frame sits above the pill.
  final String? thumbnailUrl;

  /// Size of that frame; the Marker must grow by [ThumbnailSize.extent].
  final ThumbnailSize thumbnailSize;

  /// A DRSI road station at the same spot: its road temperature joins the
  /// pill as a second segment, so one pin (and one tap) covers both.
  final DrsiStation? road;

  /// Marker width for a pin with/without a road segment.
  static double pinWidth({required bool hasWeather, required bool hasRoad}) =>
      (hasWeather ? 68 : 32) + (hasRoad ? 60 : 0);

  const TemperatureMarker({
    super.key,
    required this.station,
    required this.onTap,
    this.thumbnailUrl,
    this.thumbnailSize = ThumbnailSize.small,
    this.road,
  });

  /// The segment for an air temperature [temp] (camera badge when null).
  static MapPinSegment airSegment(double? temp) => temp == null
      ? const MapPinSegment(
          color: MapPinStyle.cameraColor,
          icon: Icons.videocam,
        )
      : MapPinSegment(
          color: AppTheme.temperatureColor(temp),
          icon: Icons.thermostat,
          text: MapPinStyle.degrees(temp),
        );

  /// The segment for a DRSI road station: tinted by road temperature, with
  /// the ice risk carried by the badge (risk colour and a snowflake).
  static MapPinSegment roadSegment(DrsiStation road) {
    final t = road.roadTemp;
    final risky = road.risk != RoadRisk.ok;
    return MapPinSegment(
      color: t == null ? MapPinStyle.cameraColor : AppTheme.temperatureColor(t),
      icon: risky ? Icons.ac_unit : Icons.add_road,
      text: t == null ? '–' : MapPinStyle.degrees(t),
      badgeColor: risky ? drsiRiskColor(road.risk) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final temp = station.temperatureC;
    final isCamera = temp == null;
    final name = station.name.trim();
    final road = this.road;
    final roadTemp = road?.roadTemp;
    final semanticLabel = [
      isCamera
          ? 'Kamera ${name.isEmpty ? '' : name}'.trim()
          : '${name.isEmpty ? 'Vremenska postaja' : name}, ${temp.round()} °C',
      if (road != null)
        'cesta ${roadTemp == null ? 'ni podatka' : '${roadTemp.round()} °C'}',
    ].join(', ');

    final Widget pin = isCamera && road == null
        ? const Padding(
            padding: EdgeInsets.only(bottom: 2),
            child: MapCameraBadge(),
          )
        : MapPill(
            segments: [airSegment(temp), if (road != null) roadSegment(road)],
          );

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // Let the pill size to its content; the surrounding Marker box is only
        // used for positioning/culling, so painting slightly outside it is fine.
        // This avoids sub-pixel RenderFlex overflow on wider (2-digit) labels.
        // minHeight 0: the pin hugs the bottom of the box, so the pointer
        // tip sits on the coordinate.
        child: OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (thumbnailUrl != null) ...[
                WebcamThumbnail.sized(thumbnailUrl!, thumbnailSize),
                const SizedBox(height: WebcamThumbnail.gap),
              ],
              pin,
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a downward-pointing triangle with a white outline to match the pill.
class _PointerPainter extends CustomPainter {
  final Color color;

  const _PointerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawShadow(path, Colors.black38, 2, false);
    canvas.drawPath(path, Paint()..color = color);

    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = MapPinStyle.rim
      ..strokeJoin = StrokeJoin.round;
    // Only stroke the two slanted edges (the top edge is hidden by the pill).
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0),
      border,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.color != color;
}
