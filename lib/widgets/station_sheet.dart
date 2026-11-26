import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/weather_station.dart';
import '../providers/weather_provider.dart';
import 'app_sheet.dart';
import 'interactive_webcam.dart';
import 'weather_details.dart';
import '../models/drsi_station.dart';
import '../providers/drsi_provider.dart';
import 'drsi_sheet.dart';

/// Opens the station detail sheet for [stationId].
void showStationSheet(BuildContext context, int stationId, {String? roadId}) {
  showAppSheet<void>(
    context,
    builder: (_) => StationSheet(stationId: stationId, roadId: roadId),
  );
}

/// Detail sheet shown when a weather/camera pin is tapped: station name and
/// update time in the pinned header, the live webcam (tap or the fullscreen
/// button = fullscreen; the refresh button or a long-press = refresh) and the
/// full weather reading below.
class StationSheet extends StatelessWidget {
  final int stationId;

  /// Id of a DRSI road station at the same spot; its road-surface data is
  /// shown in the same sheet.
  final String? roadId;

  const StationSheet({super.key, required this.stationId, this.roadId});

  @override
  Widget build(BuildContext context) {
    final station = context.select<WeatherProvider, WeatherStation?>(
      (p) => p.byId(stationId),
    );
    if (station == null) {
      return const AppSheet(
        title: 'Postaja',
        initialSize: 0.3,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Postaja ni na voljo')),
          ),
        ],
      );
    }
    final cs = Theme.of(context).colorScheme;
    final updated = station.weather?.timestamp;
    final road = roadId == null
        ? null
        : context.select<DrsiProvider, DrsiStation?>((p) {
            for (final s in p.items) {
              if (s.id == roadId) return s;
            }
            return null;
          });

    return AppSheet(
      title: station.name.isEmpty ? 'Postaja' : station.name,
      // Camera-only stations have no reading time: no subtitle at all rather
      // than "ni podatka".
      subtitle: updated == null
          ? null
          : 'Posodobljeno: ${WeatherFormat.timestamp(updated)}',
      leading: Icon(
        station.hasWeather ? Icons.thermostat : Icons.videocam,
        color: cs.primary,
      ),
      children: [
        if (station.cameraLink.isNotEmpty) ...[
          InteractiveWebcam(
            station: station,
            autoRefresh: const Duration(seconds: 60),
            showHistory: true,
            overlayTemp: station.temperatureC,
          ),
          const SizedBox(height: 16),
        ],
        if (road != null) ...[
          _sectionLabel(cs, Icons.add_road, 'Cestišče'),
          DrsiRoadSection(station: road, roadOnly: station.weather != null),
          const SizedBox(height: 18),
          if (station.weather != null)
            _sectionLabel(cs, Icons.thermostat, 'Vreme'),
        ],
        if (station.weather != null)
          WeatherDetailsView(weather: station.weather!)
        else if (road == null)
          _cameraOnlyNote(context),
      ],
    );
  }

  Widget _sectionLabel(ColorScheme cs, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraOnlyNote(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Ta postaja ima samo kamero in ne sporoča vremenskih podatkov.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
