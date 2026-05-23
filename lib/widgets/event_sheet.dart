import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/traffic_event.dart';
import 'event_marker.dart';
import 'event_visuals.dart';
import 'weather_details.dart' show WeatherFormat;

/// Present [event] details in a modal bottom sheet. Shared by the map markers
/// and the events list.
void showEventSheet(BuildContext context, TrafficEvent event) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EventSheet(event: event),
  );
}

class EventSheet extends StatelessWidget {
  final TrafficEvent event;

  const EventSheet({super.key, required this.event});

  Future<void> _openInfo(BuildContext context) async {
    final uri = Uri.tryParse(event.infoUrl);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'Povezave ni mogoče odpreti',
          type: AdaptiveSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
              _Hero(event: event),
              const SizedBox(height: 14),
              _MiniMap(event: event),
              if (event.description.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  event.description,
                  style: TextStyle(
                    color: cs.onSurface,
                    height: 1.4,
                    fontSize: 15,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _StatGrid(event: event),
              if (event.noticeText.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      Icons.account_balance,
                      size: 15,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Vir: ${event.noticeText}',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (event.infoUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                AdaptiveButton.child(
                  onPressed: () => _openInfo(context),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new, size: 18),
                      SizedBox(width: 8),
                      Text('Več informacij'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Severity-tinted hero: cause icon, severity label + road badge, and title.
class _Hero extends StatelessWidget {
  final TrafficEvent event;

  const _Hero({required this.event});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = EventVisuals.color(event.severity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(
                  EventVisuals.causeIcon(event),
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.cause.isEmpty
                          ? EventVisuals.label(event.severity)
                          : event.cause,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    if (event.road.isNotEmpty)
                      Text(
                        event.road,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                  ],
                ),
              ),
              if (event.isRoadClosed)
                _Pill(text: 'Zaprto', color: const Color(0xFFE53935)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            event.title.isEmpty ? EventVisuals.label(event.severity) : event.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (event.updated != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(
                  'Posodobljeno: ${WeatherFormat.timestamp(event.updated)}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A small, non-interactive map preview of where the event is.
class _MiniMap extends StatelessWidget {
  final TrafficEvent event;

  const _MiniMap({required this.event});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = EventVisuals.color(event.severity);

    // Fit to the affected-area bbox when present, else centre on the point.
    final hasArea = event.hasArea;
    final bounds = hasArea
        ? LatLngBounds(event.areaSouthWest!, event.areaNorthEast!)
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 170,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: event.position,
            initialZoom: 13,
            initialCameraFit: bounds == null
                ? null
                : CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(28),
                    maxZoom: 15,
                  ),
            // Static preview — let the sheet handle gestures.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: isDark
                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: isDark ? const ['a', 'b', 'c', 'd'] : const [],
              retinaMode: isDark && RetinaMode.isHighDensity(context),
              userAgentPackageName: 'dev.dz0ny.promet',
              maxZoom: 19,
            ),
            // Affected-area extent (bbox) drawn as a translucent rectangle.
            if (hasArea)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: [
                      event.areaSouthWest!,
                      LatLng(
                        event.areaSouthWest!.latitude,
                        event.areaNorthEast!.longitude,
                      ),
                      event.areaNorthEast!,
                      LatLng(
                        event.areaNorthEast!.latitude,
                        event.areaSouthWest!.longitude,
                      ),
                    ],
                    color: color.withValues(alpha: 0.15),
                    borderColor: color.withValues(alpha: 0.8),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: event.position,
                  width: 28,
                  height: 28,
                  child: EventMarker(event: event, onTap: () {}),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// A responsive grid of stat tiles for the event's key facts.
class _StatGrid extends StatelessWidget {
  final TrafficEvent event;

  const _StatGrid({required this.event});

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      if (event.queueLength > 0)
        _StatTile(
          icon: Icons.timeline,
          label: 'Zastoj',
          value: _distance(event.queueLength),
        ),
      if (event.delaySeconds > 0)
        _StatTile(
          icon: Icons.timer_outlined,
          label: 'Zamuda',
          value: _duration(event.delaySeconds),
        ),
      if (event.validFrom != null)
        _StatTile(
          icon: Icons.event_available,
          label: 'Velja od',
          value: WeatherFormat.timestamp(event.validFrom),
        ),
      if (event.estimatedEnd != null)
        _StatTile(
          icon: Icons.event_busy,
          label: 'Predviden konec',
          value: WeatherFormat.timestamp(event.estimatedEnd),
        )
      else if (event.validTo != null)
        _StatTile(
          icon: Icons.event_busy,
          label: 'Velja do',
          value: WeatherFormat.timestamp(event.validTo),
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final tileWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: tileWidth, child: t),
          ],
        );
      },
    );
  }

  static String _distance(int metres) =>
      metres >= 1000 ? '${(metres / 1000).toStringAsFixed(1)} km' : '$metres m';

  static String _duration(int seconds) {
    final m = (seconds / 60).round();
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rem = m % 60;
    return rem == 0 ? '$h h' : '$h h $rem min';
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
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
