import 'package:flutter/material.dart';

import '../models/drsi_station.dart';
import '../theme/app_theme.dart';
import 'temperature_marker.dart' show MapPill, TemperatureMarker;
import 'weather_details.dart' show WeatherFormat;

const _riskColors = <RoadRisk, Color>{
  RoadRisk.ok: Color(0xFF43A047),
  RoadRisk.caution: Color(0xFFFFB300),
  RoadRisk.slippery: Color(0xFFFB8C00),
  RoadRisk.ice: Color(0xFFE53935),
};

const _riskLabels = <RoadRisk, String>{
  RoadRisk.ok: 'Brez posebnosti',
  RoadRisk.caution: 'Previdno',
  RoadRisk.slippery: 'Nevarnost poledice',
  RoadRisk.ice: 'Poledica',
};

const _riskAdvice = <RoadRisk, String>{
  RoadRisk.ok: 'Cestišče ni ledeno.',
  RoadRisk.caution: 'Mrzlo in vlažno cestišče, možna so spolzka mesta.',
  RoadRisk.slippery:
      'Mokro cestišče je pri temperaturi zmrzišča ali pod njo. Vozi previdno.',
  RoadRisk.ice: 'Na cestišču je led. Skrajna previdnost!',
};

Color drsiRiskColor(RoadRisk r) => _riskColors[r]!;
String drsiRiskLabel(RoadRisk r) => _riskLabels[r]!;
String drsiRiskAdvice(RoadRisk r) => _riskAdvice[r]!;

/// Rounded whole degrees without a "-0" for small negatives.
String _wholeDegrees(double t) {
  final r = t.round();
  return r == 0 ? '0' : '$r';
}

String _t(double? v) => WeatherFormat.temp(v);

/// Map pin for a lone DRSI road station: the shared [MapPill] with the road
/// temperature, tinted by temperature, and the ice risk on its badge.
///
/// Place the Marker with `alignment: Alignment.topCenter` so the pointer tip
/// (bottom centre of the box) sits on the coordinate.
class DrsiMarker extends StatelessWidget {
  final DrsiStation station;
  final VoidCallback onTap;

  const DrsiMarker({super.key, required this.station, required this.onTap});

  /// Marker box width.
  static const double pinWidth = 66;

  @override
  Widget build(BuildContext context) {
    final t = station.roadTemp;
    final name = station.name.trim();
    return Semantics(
      button: true,
      label: [
        name.isEmpty ? 'Cestna postaja' : name,
        'cesta ${t == null ? 'ni podatka' : '${_wholeDegrees(t)} °C'}',
        drsiRiskLabel(station.risk),
      ].join(', '),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // Size to content (like TemperatureMarker) instead of overflowing the
        // fixed Marker box with large text or wide labels.
        child: OverflowBox(
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          alignment: Alignment.bottomCenter,
          child: MapPill(segments: [TemperatureMarker.roadSegment(station)]),
        ),
      ),
    );
  }
}

/// Road-surface block of a DRSI station: the risk card plus measurement
/// tiles. With [roadOnly] the air readings (shown elsewhere, e.g. by a
/// co-located weather station) are left out.
class DrsiRoadSection extends StatelessWidget {
  final DrsiStation station;
  final bool roadOnly;

  const DrsiRoadSection({
    super.key,
    required this.station,
    this.roadOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final risk = station.risk;
    final color = drsiRiskColor(risk);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _riskLabels[risk]!,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.readableText(
                    color,
                    Theme.of(context).brightness,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (station.roadState.isNotEmpty)
                    'Cestišče: ${station.roadState}',
                  if (station.precipitation.isNotEmpty)
                    'Padavine: ${station.precipitation}',
                ].join(' · '),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                _riskAdvice[risk]!,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.3),
              ),
              if (station.alarms.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Opozorila: ${station.alarms.join(', ')}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Two columns of tiles that grow with their content (a fixed grid
        // aspect ratio clipped the values at large text sizes).
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final tileWidth = (constraints.maxWidth - gap) / 2;
            final tiles = <Widget>[
              _drsiMetric(cs, Icons.add_road, 'Cesta', _t(station.roadTemp)),
              if (!roadOnly)
                _drsiMetric(cs, Icons.thermostat, 'Zrak', _t(station.airTemp)),
              _drsiMetric(
                cs,
                Icons.ac_unit,
                'Zmrzišče',
                _t(station.freezePoint),
              ),
              if (!roadOnly)
                _drsiMetric(
                  cs,
                  Icons.water_drop,
                  'Rosišče',
                  _t(station.dewPoint),
                ),
              if (!roadOnly)
                _drsiMetric(
                  cs,
                  Icons.opacity,
                  'Vlažnost',
                  station.humidity == null
                      ? '–'
                      : '${station.humidity!.round()} %',
                ),
              if (!roadOnly)
                _drsiMetric(
                  cs,
                  Icons.air,
                  'Veter',
                  station.windKmh == null
                      ? '–'
                      : '${station.windKmh!.round()} km/h',
                  detail: station.gustKmh == null
                      ? null
                      : 'sunki ${station.gustKmh!.round()} km/h',
                ),
              if (station.waterFilmMm != null)
                _drsiMetric(
                  cs,
                  Icons.waves,
                  'Vodni film',
                  '${WeatherFormat.decimal(station.waterFilmMm!, 2)} mm',
                ),
              if (station.salinity != null)
                _drsiMetric(
                  cs,
                  Icons.grain,
                  'Slanost',
                  '${station.salinity!.round()} ${station.salinityUnit}'.trim(),
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

Widget _drsiMetric(
  ColorScheme cs,
  IconData icon,
  String label,
  String value, {
  String? detail,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        if (detail != null)
          Text(
            detail,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
      ],
    ),
  );
}
