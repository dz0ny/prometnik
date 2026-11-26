import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/weather_station.dart';
import '../providers/weather_provider.dart';
import 'app_sheet.dart';
import 'interactive_webcam.dart';
import 'weather_details.dart';

/// Opens the station detail sheet for [stationId].
void showStationSheet(BuildContext context, int stationId) {
  showAppSheet<void>(
    context,
    builder: (_) => StationSheet(stationId: stationId),
  );
}

/// Detail sheet shown when a weather/camera pin is tapped: station name and
/// update time in the pinned header, the live webcam (tap or the fullscreen
/// button = fullscreen; the refresh button or a long-press = refresh) and the
/// full weather reading below.
class StationSheet extends StatelessWidget {
  final int stationId;

  const StationSheet({super.key, required this.stationId});

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
            overlayTemp: station.temperatureC,
          ),
          const SizedBox(height: 16),
        ],
        if (station.weather == null)
          _cameraOnlyNote(context)
        else
          WeatherDetailsView(weather: station.weather!),
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
