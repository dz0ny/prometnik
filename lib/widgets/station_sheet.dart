import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/weather_provider.dart';
import 'interactive_webcam.dart';
import 'weather_details.dart';

/// Bottom sheet shown when a map marker is tapped: an interactive webcam frame
/// (tap = fullscreen, long-press = refresh) plus the full weather reading.
class StationSheet extends StatelessWidget {
  final int stationId;

  const StationSheet({super.key, required this.stationId});

  @override
  Widget build(BuildContext context) {
    return Consumer<WeatherProvider>(
      builder: (context, provider, _) {
        final station = provider.byId(stationId);
        if (station == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text('Postaja ni na voljo')),
          );
        }
        final cs = Theme.of(context).colorScheme;
        final temp = station.temperatureC;

        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: cs.outline,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // Webcam hero: tap = fullscreen, long-press = refresh.
                  InteractiveWebcam(
                    station: station,
                    autoRefresh: const Duration(seconds: 60),
                    overlayName: station.name,
                    overlayTemp: temp,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 15, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          WeatherFormat.timestamp(station.weather?.timestamp),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        'Pritisni za celozaslon • dolg pritisk za osvežitev',
                        style: TextStyle(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (station.weather == null)
                    _cameraOnlyNote(context)
                  else
                    WeatherDetailsView(weather: station.weather!),
                ],
              ),
            );
          },
        );
      },
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
