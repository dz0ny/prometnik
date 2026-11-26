import 'package:flutter/material.dart';

import '../models/weather_station.dart';
import '../theme/app_theme.dart';
import 'webcam_thumbnail.dart';
import '../models/drsi_station.dart';
import 'drsi_sheet.dart' show drsiRiskColor;

/// A map pin that shows a station's temperature in a coloured label with a
/// downward pointer anchored to the exact location. Camera-only stations
/// (no reading) render as a compact camera pin.
///
/// The marker should be placed with `alignment: Alignment.bottomCenter` so the
/// pointer tip sits on the coordinate.
class TemperatureMarker extends StatelessWidget {
  final WeatherStation station;
  final VoidCallback onTap;

  /// When set (zoomed in), a live webcam frame sits above the pill.
  final String? thumbnailUrl;

  /// Size of that frame; the Marker must grow by [ThumbnailSize.extent].
  final ThumbnailSize thumbnailSize;

  /// A DRSI road station at the same spot: its road temperature joins the
  /// pill as a second segment tinted by ice risk, so one pin (and one tap)
  /// covers both.
  final DrsiStation? road;

  /// Marker width for a pin with/without a road segment.
  static double pinWidth({required bool hasWeather, required bool hasRoad}) =>
      (hasWeather ? 60 : 34) + (hasRoad ? 50 : 0);

  const TemperatureMarker({
    super.key,
    required this.station,
    required this.onTap,
    this.thumbnailUrl,
    this.thumbnailSize = ThumbnailSize.small,
    this.road,
  });

  @override
  Widget build(BuildContext context) {
    final temp = station.temperatureC;
    final isCamera = temp == null;
    final color = isCamera
        ? const Color(0xFF2D3E55)
        : AppTheme.temperatureColor(temp);
    // Pick a readable text/icon colour for the chosen background.
    final fg = isCamera || color.computeLuminance() < 0.45
        ? Colors.white
        : Colors.black87;

    final name = station.name.trim();
    final road = this.road;
    final roadTemp = road?.roadTemp;
    final roadColor = road == null ? null : drsiRiskColor(road.risk);
    final roadFg = roadColor == null || roadColor.computeLuminance() < 0.45
        ? Colors.white
        : Colors.black87;
    final semanticLabel = [
      isCamera
          ? 'Kamera ${name.isEmpty ? '' : name}'.trim()
          : '${name.isEmpty ? 'Vremenska postaja' : name}, ${temp.round()} °C',
      if (road != null)
        'cesta ${roadTemp == null ? 'ni podatka' : '${roadTemp.round()} °C'}',
    ].join(', ');

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
        child: OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (thumbnailUrl != null) ...[
                WebcamThumbnail.sized(thumbnailUrl!, thumbnailSize),
                const SizedBox(height: WebcamThumbnail.gap),
              ],
              // One capsule: air temperature (or camera) and, when a road
              // station shares the spot, its road temperature.
              // White capsule with the coloured segments inset by the border
              // width: clipping the colours *inside* the white (instead of
              // stroking a border over them) leaves no colour fringe.
              Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.5),
                  child: IntrinsicHeight(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _segment(
                          gradient: [_lighten(color, 0.10), color],
                          icon: isCamera ? Icons.videocam : Icons.thermostat,
                          text: isCamera ? null : '${temp.round()}°',
                          fg: fg,
                          left: true,
                          right: road == null,
                        ),
                        if (road != null && roadColor != null)
                          _segment(
                            gradient: [_lighten(roadColor, 0.08), roadColor],
                            icon: road.risk == RoadRisk.ok
                                ? Icons.add_road
                                : Icons.ac_unit,
                            text: roadTemp == null
                                ? '–'
                                : '${roadTemp.round() == 0 ? 0 : roadTemp.round()}°',
                            fg: roadFg,
                            left: false,
                            right: true,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Pointer tail, drawn slightly under the pill to hide the seam.
              Transform.translate(
                offset: const Offset(0, -2),
                child: CustomPaint(
                  size: const Size(14, 8),
                  // Under a two-colour capsule the tail is white, so it never
                  // clashes with the segment above it.
                  painter: _PointerPainter(
                    color: road == null ? color : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _segment({
    required List<Color> gradient,
    required IconData icon,
    required String? text,
    required Color fg,
    required bool left,
    required bool right,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradient,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(left ? 8 : 6, 4, right ? 8 : 6, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            if (text != null) ...[
              const SizedBox(width: 2),
              Text(
                text,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
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
      ..strokeWidth = 1.5
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
