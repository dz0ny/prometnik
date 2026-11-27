import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/drsi_station.dart';
import '../models/weather_station.dart';
import '../providers/drsi_provider.dart';
import '../providers/weather_provider.dart';
import 'app_sheet.dart';
import 'drsi_sheet.dart' show drsiRiskColor;
import 'interactive_webcam.dart';
import 'station_overview.dart';
import 'weather_details.dart';

/// Opens the station detail sheet for [stationId].
void showStationSheet(BuildContext context, int stationId, {String? roadId}) {
  showAppSheet<void>(
    context,
    builder: (_) => StationSheet(stationId: stationId, roadId: roadId),
  );
}

/// Opens the same sheet for a DRSI road station with no weather station
/// next to it.
void showRoadStationSheet(BuildContext context, DrsiStation road) {
  showAppSheet<void>(context, builder: (_) => StationSheet(roadId: road.id));
}

/// Detail sheet shown when a weather/camera pin is tapped. With a camera the
/// live frame is a full-width hero at the top with the place name and the
/// current temperature (air, or road for a lone road station) over its
/// bottom; tap or the fullscreen button = fullscreen, the refresh button or a
/// long-press = refresh. The slim pinned header keeps the update time and the
/// close button; without a camera the header carries the name. The full
/// reading follows below.
class StationSheet extends ConsumerWidget {
  /// The weather station; null for a lone DRSI road station ([roadId]).
  final int? stationId;

  /// Id of a DRSI road station at the same spot; its road-surface data is
  /// shown in the same sheet.
  final String? roadId;

  const StationSheet({super.key, this.stationId, this.roadId})
    : assert(stationId != null || roadId != null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final road = roadId == null
        ? null
        : ref.watch(
            drsiProvider.select<DrsiStation?>((p) {
              for (final s in p.items) {
                if (s.id == roadId) return s;
              }
              return null;
            }),
          );
    final id = stationId;
    final station = id != null
        ? ref.watch(weatherProvider.select((s) => s.byId(id)))
        : road == null
        ? null
        // A lone road station: its camera and no air reading.
        : WeatherStation(
            stationId: -1,
            name: road.name,
            position: road.position,
            cameraLink: road.webcamUrl,
            weather: null,
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
    final roadOnly = id == null;
    final updated = roadOnly ? road?.measuredAt : station.weather?.timestamp;
    final name = station.name.isEmpty ? 'Postaja' : station.name;
    final hasCamera = station.cameraLink.isNotEmpty;
    // Camera-only stations have no reading time: no subtitle at all rather
    // than "ni podatka".
    final subtitle = updated == null
        ? null
        : 'Posodobljeno: ${WeatherFormat.timestamp(updated)}';

    return AppSheet(
      // The hero image carries the name; the header stays slim.
      title: hasCamera ? null : name,
      subtitle: subtitle,
      leading: hasCamera
          ? null
          : roadOnly
          ? Icon(Icons.add_road, color: drsiRiskColor(road!.risk))
          : Icon(
              station.hasWeather ? Icons.thermostat : Icons.videocam,
              color: cs.primary,
            ),
      children: [
        if (hasCamera) ...[
          InteractiveWebcam(
            station: station,
            autoRefresh: const Duration(seconds: 60),
            // The worker keeps 24-hour history for weather-station cameras.
            showHistory: !roadOnly,
            fit: BoxFit.cover,
            borderRadius: 24,
            overlayName: name,
            overlayTemp: roadOnly
                ? road?.roadTemp
                : station.weather?.outdoorTemperatureC,
          ),
          const SizedBox(height: 12),
        ],
        if (station.weather != null || road != null)
          StationOverview(station: station, road: road)
        else
          _cameraOnlyNote(context),
      ],
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
