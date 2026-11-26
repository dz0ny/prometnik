import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/traffic_camera.dart';
import '../models/traffic_event.dart';
import '../providers/cameras_provider.dart';
import '../providers/weather_provider.dart';
import '../router/navigation_notifier.dart';
import '../services/road_preview_simplifier.dart';
import '../services/roads_service.dart';
import 'base_tile_layer.dart';
import 'camera_sheet.dart';
import 'event_marker.dart';
import 'event_visuals.dart';
import 'weather_details.dart' show WeatherFormat;
import 'sheet_snack.dart';
import 'app_sheet.dart';

/// Present [event] details in a modal bottom sheet. Shared by the map markers
/// and the events list.
void showEventSheet(BuildContext context, TrafficEvent event) {
  showAppSheet<void>(context, builder: (_) => EventSheet(event: event));
}

class EventSheet extends StatelessWidget {
  final TrafficEvent event;

  const EventSheet({super.key, required this.event});

  Future<void> _openInfo(BuildContext context) async {
    final raw = event.infoUrl.trim();
    if (raw.isEmpty) return;
    // The feed sometimes omits the scheme ("www.dars.si/..."), which
    // launchUrl can't open.
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null) return;
    bool opened;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      opened = false;
    }
    if (!opened) {
      if (context.mounted) {
        showSheetSnack(
          context,
          message: 'Povezave ni mogoče odpreti',
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = EventVisuals.color(event.severity);
    final title = event.title.isEmpty
        ? EventVisuals.label(event.severity)
        : event.title;
    final subtitle = [
      ?_causeLabel(event, title),
      ?eventRoadLabel(event.road),
    ].join(' · ');

    return AppSheet(
      title: title,
      titleMaxLines: 2,
      subtitle: subtitle.isEmpty ? null : subtitle,
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(
          EventVisuals.causeIcon(event),
          color: Colors.white,
          size: 17,
        ),
      ),
      children: [
        _MetaRow(event: event),
        EventMiniMap(event: event),
        if (event.description.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            event.description,
            style: TextStyle(color: cs.onSurface, height: 1.4, fontSize: 15),
          ),
        ],
        const SizedBox(height: 16),
        _StatGrid(event: event),
        if (event.noticeText.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.account_balance, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Vir: ${event.noticeText}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
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
        // Cameras come after the event's own information.
        const SizedBox(height: 20),
        EventNearbyCamerasSection(event: event),
      ],
    );
  }

  /// The feed's short cause ("dela", "zastoj"), capitalised, unless it just
  /// repeats the title.
  static String? _causeLabel(TrafficEvent event, String title) {
    final cause = event.cause.trim();
    if (cause.isEmpty) return null;
    if (cause.toLowerCase() == title.trim().toLowerCase()) return null;
    return cause[0].toUpperCase() + cause.substring(1);
  }
}

/// The road to show for an event, or null when the feed's `Cesta` is an
/// internal id (e.g. "LZ-212840" for a local road) rather than a road number
/// ("A1", "H4", "G1-5", "R3-651") or a street name.
String? eventRoadLabel(String road) {
  final r = road.trim();
  if (r.isEmpty) return null;
  final ref = RegExp(r'^(?:[AH]\d{1,2}|[GR][123]-\d{1,4}|RT-\d{1,4})(?:\b|-)');
  if (ref.hasMatch(r.toUpperCase())) {
    // Drop the European route suffix: "A1-E57" → "A1".
    return r.replaceFirst(RegExp(r'-E\d+.*$', caseSensitive: false), '');
  }
  // A name: has at least one lowercase word, not just a code and digits.
  if (RegExp(r'[a-zčšžćđ]{3,}').hasMatch(r)) return r;
  return null;
}

/// "Zaprto" badge and the last-update time, under the sheet header.
class _MetaRow extends StatelessWidget {
  final TrafficEvent event;

  const _MetaRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!event.isRoadClosed && event.updated == null) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (event.isRoadClosed)
            const _Pill(text: 'Zaprto', color: Color(0xFFE53935)),
          if (event.updated != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Posodobljeno: ${WeatherFormat.timestamp(event.updated)}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A small, non-interactive map preview of where the event is. When the event
/// has an affected-area bbox, the roads inside it are highlighted in the
/// severity colour (the closest we can get to the affected route from open
/// data — see RoadsService).
class EventMiniMap extends StatefulWidget {
  final TrafficEvent event;
  final double height;
  final double borderRadius;
  final bool showMapButton;
  final VoidCallback? onTap;

  const EventMiniMap({
    super.key,
    required this.event,
    this.height = 170,
    this.borderRadius = 16,
    this.showMapButton = true,
    this.onTap,
  });

  @override
  State<EventMiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends State<EventMiniMap> {
  List<RoadLine> _roads = const [];

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    if (e.hasArea) {
      final sw = e.areaSouthWest!, ne = e.areaNorthEast!;
      RoadPreviewSimplifier.roadsIn(
            sw.longitude,
            sw.latitude,
            ne.longitude,
            ne.latitude,
          )
          .then((roads) {
            if (mounted) setState(() => _roads = roads);
          })
          .catchError((Object e, StackTrace s) {
            // The mini-map still works without highlighted roads.
            debugPrint('road preview failed: $e\n$s');
          });
    }
  }

  void _jumpToMap() {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    context.read<NavigationNotifier>().showLocationOnMap(widget.event.position);
    Navigator.of(context).pop();
  }

  Widget _roadLayer(Color color) {
    final eref = eventRoadRef(widget.event.road);
    final matched = _roads.where((r) => roadRefMatches(eref, r.ref)).toList();
    final others = _roads.where((r) => !roadRefMatches(eref, r.ref)).toList();
    final hasMatch = matched.isNotEmpty;
    return PolylineLayer(
      simplificationTolerance: 2,
      polylines: [
        // Context roads (faint when a specific road is matched, else moderate).
        for (final r in others)
          Polyline(
            points: r.points,
            color: color.withValues(alpha: hasMatch ? 0.3 : 0.85),
            strokeWidth: hasMatch ? 2 : 4,
          ),
        // The matched road, drawn prominently on top.
        for (final r in matched)
          Polyline(
            points: r.points,
            color: color,
            strokeWidth: 5,
            borderColor: Colors.white.withValues(alpha: 0.7),
            borderStrokeWidth: 1,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = EventVisuals.color(event.severity);

    final hasArea = event.hasArea;
    // Include the marker itself so it is always inside the fitted view.
    final bounds = hasArea
        ? LatLngBounds.fromPoints([
            event.areaSouthWest!,
            event.areaNorthEast!,
            event.position,
          ])
        : null;
    // Keep the marker clear of the "Pokaži na karti" pill (bottom right).
    final fitPadding = widget.showMapButton
        ? const EdgeInsets.fromLTRB(28, 24, 48, 52)
        : const EdgeInsets.all(28);

    return Semantics(
      button: true,
      label: widget.onTap == null ? 'Pokaži na karti' : null,
      child: GestureDetector(
        // Opaque: the map below is wrapped in IgnorePointer, so without this
        // the map area would not be hit-testable and taps would be lost.
        behavior: HitTestBehavior.opaque,
        onTap: _jumpToMap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                // Static preview: FlutterMap would otherwise swallow taps even
                // with interactions off; the whole card handles the tap.
                IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: event.position,
                      initialZoom: 13,
                      initialCameraFit: bounds == null
                          ? null
                          : CameraFit.bounds(
                              bounds: bounds,
                              padding: fitPadding,
                              maxZoom: 15,
                            ),
                      // Avoid a light-grey flash in dark mode while tiles load.
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      buildBaseTileLayer(
                        context,
                        base: BaseMap.saved,
                        isDark: isDark,
                      ),
                      // Roads within the affected area. The road matching the
                      // event's number is emphasised; others provide faint context.
                      if (_roads.isNotEmpty) _roadLayer(color),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: event.position,
                            width: 28,
                            height: 28,
                            child: EventMarker(event: event, onTap: _jumpToMap),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // "Open on map" affordance.
                if (widget.showMapButton)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map, size: 14, color: Colors.white),
                          SizedBox(width: 5),
                          Text(
                            'Pokaži na karti',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EventNearbyCamerasSection extends StatefulWidget {
  final TrafficEvent event;

  const EventNearbyCamerasSection({super.key, required this.event});

  @override
  State<EventNearbyCamerasSection> createState() =>
      _EventNearbyCamerasSectionState();
}

class _EventNearbyCamerasSectionState extends State<EventNearbyCamerasSection> {
  static const double _fallbackRadiusMeters = 8000;

  /// Nearest cameras shown before "Prikaži vse".
  static const int _collapsedCount = 3;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stations = context.watch<WeatherProvider>().stations;
    final cameras =
        context
            .watch<CamerasProvider>()
            .visibleCameras(stations)
            .where(_isNearby)
            .toList()
          ..sort(_compareByDistance);
    final shown = _showAll ? cameras : cameras.take(_collapsedCount).toList();
    final canToggle = cameras.length > _collapsedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Row(
            children: [
              Icon(Icons.photo_camera, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Kamere v bližini (${cameras.length})',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (cameras.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'V bližini ni kamer.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
        for (final camera in shown) ...[
          const SizedBox(height: 10),
          EventCameraCard(camera: camera),
        ],
        if (canToggle) ...[
          const SizedBox(height: 4),
          _DisclosureRow(
            label: _showAll
                ? 'Prikaži manj'
                : 'Prikaži vse (${cameras.length})',
            expanded: _showAll,
            onTap: () => setState(() => _showAll = !_showAll),
          ),
        ],
      ],
    );
  }

  bool _isNearby(TrafficCamera camera) {
    final event = widget.event;
    final point = camera.position;
    if (event.hasArea) {
      final sw = event.areaSouthWest!, ne = event.areaNorthEast!;
      if (point.latitude >= sw.latitude &&
          point.latitude <= ne.latitude &&
          point.longitude >= sw.longitude &&
          point.longitude <= ne.longitude) {
        return true;
      }
    }
    return const Distance()(event.position, point) <= _fallbackRadiusMeters;
  }

  int _compareByDistance(TrafficCamera a, TrafficCamera b) {
    const distance = Distance();
    return distance(
      widget.event.position,
      a.position,
    ).compareTo(distance(widget.event.position, b.position));
  }
}

/// A full-width live DARS camera image inside an event detail; tap to open.
class EventCameraCard extends StatelessWidget {
  final TrafficCamera camera;

  const EventCameraCard({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    // Per-minute cache buster so the snapshot stays reasonably fresh.
    final bust = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final url = camera.imageUrlWithBuster(bust);
    return GestureDetector(
      onTap: () => showCameraSheet(context, camera),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: CachedNetworkImage(
                  imageUrl: url,
                  cacheKey: url,
                  useOldImageOnUrlChange: true,
                  // Card-sized preview; the fullscreen viewer loads full res.
                  memCacheWidth: 800,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 40,
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.6, 1.0],
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Text(
                  camera.title.isEmpty ? 'Kamera' : camera.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-width "show more / less" row with a chevron (44pt tall).
class _DisclosureRow extends StatelessWidget {
  final String label;
  final bool expanded;
  final VoidCallback onTap;

  const _DisclosureRow({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      expanded: expanded,
      // Own Material so the ripple paints above the sheet's background.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.primary,
                  ),
                ],
              ),
            ),
          ),
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

  static String _distance(int metres) => metres >= 1000
      ? '${WeatherFormat.decimal(metres / 1000)} km'
      : '$metres m';

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
