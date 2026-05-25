import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/alerts_controller.dart';
import '../providers/events_provider.dart';
import '../services/map_tile_cache_service.dart';
import '../services/roads_service.dart';
import '../widgets/event_marker.dart';

/// Full-screen map where the user taps roads to add/remove them from the
/// watched set. Tapped point snaps to the nearest road's `ref`.
class WatchedRoadsPickerScreen extends StatefulWidget {
  const WatchedRoadsPickerScreen({super.key});

  @override
  State<WatchedRoadsPickerScreen> createState() =>
      _WatchedRoadsPickerScreenState();
}

class _WatchedRoadsPickerScreenState extends State<WatchedRoadsPickerScreen> {
  static const LatLng _center = LatLng(46.1512, 14.9955);
  final _mapController = MapController();
  List<List<LatLng>> _watchedLines = const [];
  List<List<LatLng>> _exampleLines = const []; // illustrative "A1" highlight
  bool _showNotice = true;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadExample();
  }

  Future<void> _reload() async {
    final refs = context.read<AlertsController>().watchedRoads;
    final roads = await RoadsService.instance.roadsByRefs(refs);
    if (mounted) {
      setState(() => _watchedLines = roads.map((r) => r.points).toList());
    }
  }

  Future<void> _loadExample() async {
    final roads = await RoadsService.instance.roadsByRefs({'A1'});
    if (mounted) {
      setState(() => _exampleLines = roads.map((r) => r.points).toList());
    }
  }

  Future<void> _onTap(LatLng p) async {
    final ref = await RoadsService.instance.nearestRoadRef(
      p.latitude,
      p.longitude,
      maxMeters: 250,
    );
    if (!mounted) return;
    if (ref == null) {
      AdaptiveSnackBar.show(context, message: 'Tukaj ni ceste za spremljanje.');
      return;
    }
    final alerts = context.read<AlertsController>();
    final wasWatched = alerts.isWatched(ref);
    alerts.toggleRoad(ref);
    await _reload();
    if (mounted) {
      AdaptiveSnackBar.show(
        context,
        message: wasWatched ? 'Odstranjeno: $ref' : 'Spremljam: $ref',
        type: wasWatched
            ? AdaptiveSnackBarType.info
            : AdaptiveSnackBarType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final watched = context.watch<AlertsController>().watchedRoads;
    final events = context.watch<EventsProvider>().events;
    final showExample = watched.isEmpty && _exampleLines.isNotEmpty;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: watched.isEmpty
            ? 'Spremljane ceste'
            : 'Spremljane ceste (${watched.length})',
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 8.2,
              minZoom: 7,
              maxZoom: 17,
              backgroundColor: cs.surface,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: (_, p) => _onTap(p),
            ),
            children: [
              TileLayer(
                urlTemplate: isDark
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                tileProvider: MapTileCacheService.instance.createTileProvider(),
                subdomains: isDark ? const ['a', 'b', 'c', 'd'] : const [],
                retinaMode: isDark && RetinaMode.isHighDensity(context),
                userAgentPackageName: 'dev.dz0ny.promet',
                maxZoom: 19,
              ),
              // Example road (dashed) shown until the user picks something.
              if (showExample)
                PolylineLayer(
                  polylines: [
                    for (final pts in _exampleLines)
                      Polyline(
                        points: pts,
                        color: cs.secondary.withValues(alpha: 0.8),
                        strokeWidth: 4,
                        pattern: StrokePattern.dashed(
                          segments: const [12, 8],
                        ),
                      ),
                  ],
                ),
              if (_watchedLines.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (final pts in _watchedLines)
                      Polyline(
                        points: pts,
                        color: cs.primary,
                        strokeWidth: 5,
                        borderColor: Colors.white.withValues(alpha: 0.6),
                        borderStrokeWidth: 1,
                      ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final e in events)
                    Marker(
                      point: e.position,
                      width: 22,
                      height: 22,
                      child: EventMarker(
                        event: e,
                        onTap: () => _onTap(e.position),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Centered, dismissible instruction notice.
          if (_showNotice)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AdaptiveCard(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.touch_app, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Izberi ceste za spremljanje',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _showNotice = false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tapni cesto na karti, da jo dodaš med spremljane — '
                        'obvestili te bomo o dogodkih na njej. Tapni znova za '
                        'odstranitev.\n\nPrekinjena črta je primer (avtocesta A1).',
                        style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      AdaptiveButton(
                        onPressed: () => setState(() => _showNotice = false),
                        label: 'Razumem',
                        size: AdaptiveButtonSize.small,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
