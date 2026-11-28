import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/drsi_station.dart';
import '../models/weather_station.dart';
import '../providers/drsi_provider.dart';
import '../providers/weather_provider.dart';
import '../services/weather_history_service.dart';
import 'app_sheet.dart';
import 'drsi_sheet.dart' show drsiRiskColor;
import 'interactive_webcam.dart';
import 'station_overview.dart';
import 'weather_details.dart';

/// Opens the station detail sheet for [stationId]. Without [roadId] the
/// nearest DRSI road station (if any) is shown alongside when [pairRoad].
void showStationSheet(
  BuildContext context,
  int stationId, {
  String? roadId,
  bool pairRoad = false,
}) {
  showAppSheet<void>(
    context,
    builder: (_) =>
        StationSheet(stationId: stationId, roadId: roadId, pairRoad: pairRoad),
  );
}

/// The DRSI road station within [meters] of [at] (the map pairs pins within
/// the same distance), nearest first; null if none.
DrsiStation? nearestRoadStation(
  LatLng at,
  List<DrsiStation> roads, {
  double meters = 400,
}) {
  const distance = Distance();
  DrsiStation? best;
  var bestD = meters;
  for (final r in roads) {
    // Cheap reject before the exact distance.
    if ((r.position.latitude - at.latitude).abs() > 0.01) continue;
    final d = distance(at, r.position);
    if (d <= bestD) {
      bestD = d;
      best = r;
    }
  }
  return best;
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
class StationSheet extends ConsumerStatefulWidget {
  /// The weather station; null for a lone DRSI road station ([roadId]).
  final int? stationId;

  /// Id of a DRSI road station at the same spot; its road-surface data is
  /// shown in the same sheet.
  final String? roadId;

  /// Without [roadId], look up the nearest road station (lists, which have
  /// no map pairing).
  final bool pairRoad;

  const StationSheet({
    super.key,
    this.stationId,
    this.roadId,
    this.pairRoad = false,
  }) : assert(stationId != null || roadId != null);

  @override
  ConsumerState<StationSheet> createState() => _StationSheetState();
}

class _StationSheetState extends ConsumerState<StationSheet> {
  /// Hour of the picked camera snapshot (null = live) and the stored hourly
  /// readings, so the caption and readings match the picture.
  DateTime? _snapshotAt;
  List<WeatherPoint> _history = const [];

  int? get stationId => widget.stationId;
  String? get roadId => widget.roadId;

  @override
  void initState() {
    super.initState();
    final id = stationId;
    if (id == null) return;
    final svc = WeatherHistoryService.instance;
    _history = svc.cached(id) ?? const [];
    // fetch() never throws: it returns an empty series on failure.
    unawaited(
      svc.fetch(id).then((points) {
        if (mounted) setState(() => _history = points);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = stationId;
    final weatherStation = id == null
        ? null
        : ref.watch(weatherProvider.select((s) => s.byId(id)));
    final road = roadId != null
        ? ref.watch(
            drsiProvider.select<DrsiStation?>((p) {
              for (final s in p.items) {
                if (s.id == roadId) return s;
              }
              return null;
            }),
          )
        : widget.pairRoad && weatherStation != null
        ? ref.watch(
            drsiProvider.select(
              (p) => nearestRoadStation(weatherStation.position, p.items),
            ),
          )
        : null;
    final station = id != null
        ? weatherStation
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
    final snapshotAt = roadOnly ? null : _snapshotAt;
    final reading = readingForSnapshot(station.weather, _history, snapshotAt);
    final subtitle = snapshotAt != null
        ? 'Podatki ob ${WeatherFormat.hour(snapshotAt)}'
        : updated == null
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
            title: name,
            urlFor: station.cameraUrlWithBuster,
            autoRefresh: const Duration(seconds: 60),
            // The worker keeps 24-hour history for weather-station cameras.
            showHistory: !roadOnly,
            onSnapshotChanged: (at) => setState(() => _snapshotAt = at),
            fit: BoxFit.cover,
            borderRadius: 24,
            overlayName: name,
            overlayTemp: roadOnly
                ? road?.roadTemp
                : reading?.outdoorTemperatureC,
          ),
          const SizedBox(height: 12),
        ],
        if (station.weather != null || road != null)
          StationOverview(station: station, road: road, snapshotAt: snapshotAt)
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
