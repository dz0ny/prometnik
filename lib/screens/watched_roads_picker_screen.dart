import 'dart:async';
import 'dart:math' as math;
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/alerts_controller.dart';
import '../providers/events_provider.dart';
import '../services/roads_service.dart';
import '../theme/app_theme.dart';
import '../widgets/event_marker.dart';
import '../widgets/event_sheet.dart';
import '../widgets/base_tile_layer.dart';

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

  /// All of Slovenia, so the first view shows every road that can be picked.
  static final LatLngBounds _slovenia = LatLngBounds(
    const LatLng(45.42, 13.37),
    const LatLng(46.88, 16.61),
  );

  /// How far from a road (in screen points) a tap still selects it.
  static const double _snapPoints = 24;

  final _mapController = MapController();
  List<List<LatLng>> _watchedLines = const [];
  List<List<LatLng>> _exampleLines = const []; // illustrative "A1" highlight
  bool _showNotice = true;
  int _reloadGen = 0;

  String? _banner;
  bool _bannerError = false;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    unawaited(_loadExample());
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    // Quick taps start overlapping reloads; only the newest may win.
    final gen = ++_reloadGen;
    final refs = context.read<AlertsController>().watchedRoads;
    try {
      final roads = await RoadsService.instance.roadsByRefs(refs);
      if (mounted && gen == _reloadGen) {
        setState(() => _watchedLines = roads.map((r) => r.points).toList());
      }
    } on Exception catch (e) {
      debugPrint('watched roads failed: $e');
    }
  }

  Future<void> _loadExample() async {
    try {
      final roads = await RoadsService.instance.roadsByRefs({'A1'});
      if (mounted) {
        setState(() => _exampleLines = roads.map((r) => r.points).toList());
      }
    } on Exception catch (e) {
      debugPrint('example road failed: $e');
    }
  }

  /// Bottom banner above the tab bar (the platform snack bar shows at the top
  /// on iOS, over the navigation bar).
  void _showBanner(String message, {bool error = false}) {
    _bannerTimer?.cancel();
    setState(() {
      _banner = message;
      _bannerError = error;
    });
    _bannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  /// Snap radius in metres for [_snapPoints] at the current zoom, so a tap
  /// near a road selects it whether the map is zoomed out or in.
  double _snapMeters(LatLng p) {
    final zoom = _mapController.camera.zoom;
    final metersPerPixel =
        156543.03 * math.cos(p.latitude * math.pi / 180) / math.pow(2, zoom);
    return (_snapPoints * metersPerPixel).clamp(25.0, 5000.0);
  }

  Future<void> _onTap(LatLng p) async {
    final ref = await RoadsService.instance.nearestRoadRef(
      p.latitude,
      p.longitude,
      maxMeters: _snapMeters(p),
    );
    if (!mounted) return;
    if (ref == null) {
      _showBanner('Tukaj ni ceste za spremljanje.', error: true);
      return;
    }
    final wasWatched = context.read<AlertsController>().isWatched(ref);
    await _toggle(ref);
    if (mounted) {
      _showBanner(wasWatched ? 'Odstranjeno: $ref' : 'Spremljam: $ref');
    }
  }

  Future<void> _toggle(String ref) async {
    context.read<AlertsController>().toggleRoad(ref);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final watched = context.watch<AlertsController>().watchedRoads;
    final events = context.watch<EventsProvider>().events;
    final showExample = watched.isEmpty && _exampleLines.isNotEmpty;
    final bottomInset = math.max(
      AppTheme.bottomBarContentInset(context),
      MediaQuery.paddingOf(context).bottom,
    );
    final sortedRefs = watched.toList()..sort();

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: watched.isEmpty
            ? 'Spremljane ceste'
            : 'Spremljane ceste (${watched.length})',
        actions: [
          AdaptiveAppBarAction(
            icon: Icons.info_outline,
            iosSymbol: 'info.circle',
            label: 'Pomoč',
            onPressed: () => setState(() => _showNotice = true),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 8,
              initialCameraFit: CameraFit.bounds(
                bounds: _slovenia,
                padding: const EdgeInsets.all(16),
              ),
              minZoom: 7,
              maxZoom: 17,
              backgroundColor: cs.surface,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: (_, p) => _onTap(p),
            ),
            children: [
              buildBaseTileLayer(context, base: BaseMap.saved, isDark: isDark),
              // Example road (dashed) shown until the user picks something.
              if (showExample)
                PolylineLayer(
                  polylines: [
                    for (final pts in _exampleLines)
                      Polyline(
                        points: pts,
                        color: cs.secondary.withValues(alpha: 0.8),
                        strokeWidth: 4,
                        pattern: StrokePattern.dashed(segments: const [12, 8]),
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
              // Tapping an event shows it; it never toggles a road.
              MarkerLayer(
                markers: [
                  for (final e in events)
                    Marker(
                      point: e.position,
                      width: 22,
                      height: 22,
                      child: EventMarker(
                        event: e,
                        onTap: () => showEventSheet(context, e),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Watched roads with remove buttons, and the confirmation banner.
          Positioned(
            left: 0,
            right: 0,
            bottom: 12 + bottomInset,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_banner != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(12),
                        color: _bannerError
                            ? cs.errorContainer
                            : cs.inverseSurface,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Text(
                            _banner!,
                            style: TextStyle(
                              color: _bannerError
                                  ? cs.onErrorContainer
                                  : cs.onInverseSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (sortedRefs.isNotEmpty)
                  Material(
                    type: MaterialType.transparency,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          for (final ref in sortedRefs)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: InputChip(
                                label: Text(ref),
                                avatar: Icon(
                                  Icons.notifications_active,
                                  size: 16,
                                  color: cs.primary,
                                ),
                                backgroundColor: cs.surface,
                                elevation: 2,
                                deleteButtonTooltipMessage: 'Odstrani $ref',
                                onDeleted: () async {
                                  await _toggle(ref);
                                  if (mounted) {
                                    _showBanner('Odstranjeno: $ref');
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
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
                            tooltip: 'Zapri',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                setState(() => _showNotice = false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tapni cesto na karti, da jo dodaš med spremljane — '
                        'obvestili te bomo o dogodkih na njej. Tapni znova '
                        'ali tapni × na oznaki spodaj za odstranitev. Tapni '
                        'dogodek za podrobnosti.\n\nPrekinjena črta je '
                        'primer (avtocesta A1). To pomoč znova odpreš z '
                        'gumbom (i) zgoraj.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
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
