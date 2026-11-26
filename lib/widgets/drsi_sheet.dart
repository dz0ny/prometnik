import 'package:flutter/material.dart';

import '../models/drsi_station.dart';
import '../theme/app_theme.dart';
import 'app_sheet.dart';
import 'weather_details.dart' show WeatherFormat;
import 'live_webcam_image.dart';

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

void showDrsiSheet(BuildContext context, DrsiStation station) {
  showAppSheet<void>(context, builder: (_) => _DrsiSheet(station: station));
}

/// Map pin: road surface temperature on a pill tinted by [RoadRisk].
class DrsiMarker extends StatelessWidget {
  final DrsiStation station;
  final VoidCallback onTap;

  const DrsiMarker({super.key, required this.station, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final risk = station.risk;
    final bg = drsiRiskColor(risk);
    final fg = bg.computeLuminance() < 0.45 ? Colors.white : Colors.black;
    final t = station.roadTemp;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // Size to content (like TemperatureMarker) instead of overflowing the
      // fixed Marker box with large text or wide labels.
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                risk == RoadRisk.ok ? Icons.add_road : Icons.ac_unit,
                size: 13,
                color: fg,
              ),
              const SizedBox(width: 3),
              Text(
                t == null ? '–' : '${_wholeDegrees(t)}°',
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrsiSheet extends StatelessWidget {
  final DrsiStation station;

  const _DrsiSheet({required this.station});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final risk = station.risk;
    final color = drsiRiskColor(risk);
    final at = station.measuredAt;
    final camUrl = station.cameraUrlWithBuster(
      DateTime.now().millisecondsSinceEpoch ~/ 60000,
    );

    return AppSheet(
      title: station.name.isEmpty ? 'Cestna postaja' : station.name,
      subtitle: [
        'Cestna postaja DRSI',
        if (at != null) WeatherFormat.timestamp(at),
      ].join(' · '),
      leading: Icon(Icons.add_road, color: color),
      children: [
        DrsiRoadSection(station: station),
        if (camUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: LiveWebcamImage(
                  url: camUrl,
                  fit: BoxFit.contain,
                  placeholder: (_) =>
                      const Center(child: CircularProgressIndicator.adaptive()),
                  errorWidget: (_) => const Center(
                    child: Icon(Icons.videocam_off, color: Colors.white54),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Vir: Direkcija RS za infrastrukturo (CVIS)',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
      ],
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
