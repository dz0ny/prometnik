import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/weather_station.dart';
import '../theme/app_theme.dart';

/// Formatting helpers for weather values, shared across screens.
class WeatherFormat {
  WeatherFormat._();

  static String temp(double? c) =>
      c == null ? '–' : '${c.toStringAsFixed(1)} °C';

  static String wind(WeatherReading w) {
    if (w.windSpeedKmh == null) return '–';
    final dir = (w.windDirection?.isNotEmpty ?? false) ? ' ${w.windDirection}' : '';
    final gust = w.windGustKmh != null
        ? ' (sunki ${w.windGustKmh!.round()} km/h)'
        : '';
    return '${w.windSpeedKmh!.round()} km/h$dir$gust';
  }

  static String humidity(int? p) => p == null ? '–' : '$p %';
  static String pressure(int? h) => h == null ? '–' : '$h hPa';
  static String rain(double? mm) =>
      mm == null ? '–' : '${mm.toStringAsFixed(1)} mm';
  static String dew(double? c) =>
      c == null ? '–' : '${c.toStringAsFixed(1)} °C';

  static String minMax(WeatherReading w) {
    final lo = w.minOutdoorTemperatureC;
    final hi = w.maxOutdoorTemperatureC;
    if (lo == null && hi == null) return '–';
    final loS = lo == null ? '–' : '${lo.toStringAsFixed(1)}°';
    final hiS = hi == null ? '–' : '${hi.toStringAsFixed(1)}°';
    return '$loS / $hiS';
  }

  static String timestamp(DateTime? ts) {
    if (ts == null) return 'ni podatka';
    return DateFormat('d. M. yyyy HH:mm').format(ts);
  }

  /// Compass bearing in degrees for a cardinal direction string (e.g. "NNE"),
  /// or null if unknown. North = 0°, clockwise.
  static double? bearing(String? dir) {
    if (dir == null) return null;
    const map = {
      'N': 0.0, 'NNE': 22.5, 'NE': 45.0, 'ENE': 67.5,
      'E': 90.0, 'ESE': 112.5, 'SE': 135.0, 'SSE': 157.5,
      'S': 180.0, 'SSW': 202.5, 'SW': 225.0, 'WSW': 247.5,
      'W': 270.0, 'WNW': 292.5, 'NW': 315.0, 'NNW': 337.5,
    };
    return map[dir.trim().toUpperCase()];
  }
}

/// A modern weather panel: temperature hero, wind compass, and a grid of stat
/// tiles. Used by both the marker sheet and the station detail screen.
class WeatherDetailsView extends StatelessWidget {
  final WeatherReading weather;

  const WeatherDetailsView({super.key, required this.weather});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TemperatureHero(weather: weather),
        const SizedBox(height: 12),
        if (weather.windSpeedKmh != null) ...[
          _WindTile(weather: weather),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final tileWidth = (constraints.maxWidth - gap) / 2;
            final tiles = <Widget>[
              _StatTile(
                icon: Icons.water_drop_outlined,
                label: 'Vlažnost',
                value: WeatherFormat.humidity(weather.humidityPercentage),
              ),
              _StatTile(
                icon: Icons.compress,
                label: 'Tlak',
                value: WeatherFormat.pressure(weather.pressureHpa),
              ),
              _StatTile(
                icon: Icons.umbrella_outlined,
                label: 'Padavine',
                value: WeatherFormat.rain(weather.dailyRainMm),
              ),
              _StatTile(
                icon: Icons.opacity,
                label: 'Rosišče',
                value: WeatherFormat.dew(weather.dewPointC),
              ),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final t in tiles) SizedBox(width: tileWidth, child: t),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TemperatureHero extends StatelessWidget {
  final WeatherReading weather;

  const _TemperatureHero({required this.weather});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = weather.outdoorTemperatureC;
    final color = AppTheme.temperatureColor(t);
    final whole = t == null ? '–' : t.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.32),
            color.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Temperatura',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      whole,
                      style: const TextStyle(
                        fontSize: 46,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6, left: 2),
                      child: Text(
                        '°C',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MiniStat(
                icon: Icons.arrow_upward,
                value: weather.maxOutdoorTemperatureC == null
                    ? '–'
                    : '${weather.maxOutdoorTemperatureC!.toStringAsFixed(1)}°',
                tint: const Color(0xFFFB8C00),
              ),
              const SizedBox(height: 8),
              _MiniStat(
                icon: Icons.arrow_downward,
                value: weather.minOutdoorTemperatureC == null
                    ? '–'
                    : '${weather.minOutdoorTemperatureC!.toStringAsFixed(1)}°',
                tint: const Color(0xFF5DA9E9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color tint;

  const _MiniStat({required this.icon, required this.value, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: tint),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _WindTile extends StatelessWidget {
  final WeatherReading weather;

  const _WindTile({required this.weather});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bearing = WeatherFormat.bearing(weather.windDirection);
    final speed = weather.windSpeedKmh?.round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _tileDecoration(cs),
      child: Row(
        children: [
          _WindCompass(bearing: bearing, size: 58, color: cs.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Veter',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      speed == null ? '–' : '$speed',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'km/h',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    if (weather.windDirection?.isNotEmpty ?? false) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          weather.windDirection!,
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (weather.windGustKmh != null)
                  Text(
                    'sunki do ${weather.windGustKmh!.round()} km/h',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small compass dial with an arrow pointing in the wind's bearing.
class _WindCompass extends StatelessWidget {
  final double? bearing;
  final double size;
  final Color color;

  const _WindCompass({
    required this.bearing,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surface.withValues(alpha: 0.6),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 4,
            child: Text(
              'S',
              style: TextStyle(
                fontSize: 9,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (bearing == null)
            Icon(Icons.air, size: size * 0.4, color: cs.onSurfaceVariant)
          else
            Transform.rotate(
              angle: bearing! * math.pi / 180,
              child: Icon(Icons.navigation, size: size * 0.5, color: color),
            ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _tileDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _tileDecoration(ColorScheme cs) => BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
    );
