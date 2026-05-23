import 'package:flutter/material.dart';
import '../models/weather_station.dart';
import '../theme/app_theme.dart';

/// A map pin that shows a station's temperature in a coloured label with a
/// downward pointer anchored to the exact location. Camera-only stations
/// (no reading) render as a compact camera pin.
///
/// The marker should be placed with `alignment: Alignment.bottomCenter` so the
/// pointer tip sits on the coordinate.
class TemperatureMarker extends StatelessWidget {
  final WeatherStation station;
  final VoidCallback onTap;

  const TemperatureMarker({
    super.key,
    required this.station,
    required this.onTap,
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

    return GestureDetector(
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
            Container(
              padding: isCamera
                  ? const EdgeInsets.all(5)
                  : const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_lighten(color, 0.10), color],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: isCamera
                  ? Icon(Icons.videocam, size: 14, color: fg)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.thermostat, size: 13, color: fg),
                        const SizedBox(width: 2),
                        Text(
                          '${temp.round()}°',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
            ),
            // Pointer tail, drawn slightly under the pill to hide the seam.
            Transform.translate(
              offset: const Offset(0, -2),
              child: CustomPaint(
                size: const Size(14, 8),
                painter: _PointerPainter(color: color),
              ),
            ),
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
