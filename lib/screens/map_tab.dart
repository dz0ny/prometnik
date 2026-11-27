import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rest_area.dart';
import '../models/drsi_station.dart';
import '../models/traffic_camera.dart';
import '../models/traffic_event.dart';
import '../models/weather_station.dart';
import '../providers/alerts_controller.dart';
import '../providers/burja_provider.dart';
import '../providers/drsi_provider.dart';
import '../services/drsi_service.dart';
import '../providers/cameras_provider.dart';
import '../providers/events_provider.dart';
import '../providers/rest_areas_provider.dart';
import '../providers/weather_provider.dart';
import '../router/route_names.dart';
import '../services/prefs.dart';
import '../services/roads_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/base_tile_layer.dart';
import '../widgets/burja_sheet.dart';
import '../widgets/drsi_sheet.dart';
import '../widgets/camera_sheet.dart';
import '../widgets/event_marker.dart';
import '../widgets/event_sheet.dart';
import '../widgets/event_visuals.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/rest_area_sheet.dart';
import '../widgets/station_sheet.dart';
import '../widgets/temperature_marker.dart';
import '../widgets/webcam_thumbnail.dart';

/// Map tab: shows every station as a coloured temperature marker over Slovenia.
class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key});

  @override
  ConsumerState<MapTab> createState() => MapTabState();
}

class MapTabState extends ConsumerState<MapTab> {
  final MapController _mapController = MapController();
  final LayerHitNotifier<TrafficEvent> _eventRoadHitNotifier = ValueNotifier(
    null,
  );

  // Slovenia centre.
  static const LatLng _sloveniaCenter = LatLng(46.1512, 14.9955);
  static const double _initialZoom = 8.2;

  bool _mapReady = false;

  /// Zoom from which weather pins also show a mini webcam frame.
  /// Frames grow with zoom (see [ThumbnailSize.forZoom]); null = none.
  static const double _thumbnailZoom = 11;
  ThumbnailSize? _thumbnailSize;

  /// DARS cameras are far denser, so their frames need a closer zoom.
  static const double _cameraThumbnailZoom = 13;
  ThumbnailSize? _cameraThumbnailSize;

  /// Below this zoom nearby cameras merge into count badges; from here on
  /// (where their webcam frames start) every camera has its own pin.
  static const double _clusterMaxZoom = _cameraThumbnailZoom;

  /// Whole-zoom bucket the camera clusters are computed for, or null when
  /// zoomed in past [_clusterMaxZoom]. Changes only when crossing a whole
  /// zoom level, so panning never re-clusters.
  int? _clusterZoom = _clusterZoomFor(_initialZoom);

  static int? _clusterZoomFor(double zoom) =>
      zoom >= _clusterMaxZoom ? null : zoom.floor();

  // Base map tiles: Esri satellite, OpenStreetMap or Seznam (Mapy.cz).
  BaseMap _baseMap = BaseMap.saved;

  void _setBaseMap(BaseMap base) {
    if (base == _baseMap) return;
    setState(() => _baseMap = base);
    BaseMap.saved = base;
  }

  /// Zoom in on a camera cluster: fit its cameras, but always at least one
  /// level deeper so co-located cameras (degenerate bounds) still split.
  void _zoomToCluster(List<LatLng> points) {
    if (!_mapReady || points.isEmpty) return;
    final camera = _mapController.camera;
    final fitted = CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(72),
      maxZoom: 16,
    ).fit(camera);
    final zoom = math.max(fitted.zoom, camera.zoom.floor() + 1.0);
    _mapController.move(fitted.center, math.min(zoom, 16));
  }

  // Map layer filters.
  static const List<EventSeverity> _severities = [
    EventSeverity.closed,
    EventSeverity.jam,
    EventSeverity.roadworks,
    EventSeverity.other,
  ];
  bool _showWeather = true;
  bool _showCameras = true;
  bool _showDarsCameras = true;
  bool _showRestAreas = true;
  bool _showBurja = true;
  bool _showDrsi = true;
  final Set<EventSeverity> _eventFilter = {..._severities};

  // Affected-area road highlights for the visible events.
  List<Polyline<TrafficEvent>> _eventRoads = const [];
  String _roadsSig = '';
  // Bumped per refresh so a slower, older refresh can't overwrite a newer one.
  int _roadsGen = 0;

  @override
  void dispose() {
    _focusTimer?.cancel();
    _eventRoadHitNotifier.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _showWeather = Prefs.getBool('map.showWeather', true);
    _showCameras = Prefs.getBool('map.showCameras', true);
    _showDarsCameras = Prefs.getBool('map.darsCameras', true);
    _showRestAreas = Prefs.getBool('map.pocivalisca', true);
    _showBurja = Prefs.getBool('map.burja', true);
    _showDrsi = Prefs.getBool('map.drsi', true);
    if (Prefs.has('map.severities')) {
      final saved = Prefs.getStringList('map.severities', const []);
      _eventFilter
        ..clear()
        ..addAll(saved.map(_severityByName).whereType<EventSeverity>());
    }
  }

  void _saveMapFilters() {
    Prefs.setBool('map.showWeather', _showWeather);
    Prefs.setBool('map.showCameras', _showCameras);
    Prefs.setBool('map.darsCameras', _showDarsCameras);
    Prefs.setBool('map.pocivalisca', _showRestAreas);
    Prefs.setBool('map.burja', _showBurja);
    Prefs.setBool('map.drsi', _showDrsi);
    Prefs.setStringList(
      'map.severities',
      _eventFilter.map((s) => s.name).toList(),
    );
  }

  static EventSeverity? _severityByName(String n) {
    for (final s in _severities) {
      if (s.name == n) return s;
    }
    return null;
  }

  static int _mapNoticePriority(TrafficEvent event) => switch (event.severity) {
    EventSeverity.jam => 0,
    EventSeverity.closed => 1,
    EventSeverity.roadworks => 2,
    EventSeverity.other => 3,
  };

  static int _compareMapNotices(TrafficEvent a, TrafficEvent b) {
    final p = _mapNoticePriority(a).compareTo(_mapNoticePriority(b));
    if (p != 0) return p;
    final feedPriority = a.priority.compareTo(b.priority);
    if (feedPriority != 0) return feedPriority;
    return a.road.compareTo(b.road);
  }

  static int _compareMapDrawOrder(TrafficEvent a, TrafficEvent b) =>
      _compareMapNotices(b, a);

  /// Called by [_EventsLayer] when the filtered event list changes; refresh
  /// the affected-road highlights only when the visible set really changed.
  void _onVisibleEventsChanged(List<TrafficEvent> visibleEvents) {
    final sig = visibleEvents
        .map((e) => '${e.id}:${e.severity.index}')
        .join('|');
    if (sig == _roadsSig) return;
    _roadsSig = sig;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshEventRoads(visibleEvents),
    );
  }

  /// Recompute the highlighted roads inside each visible event's affected area
  /// when the visible event set changes.
  Future<void> _refreshEventRoads(List<TrafficEvent> events) async {
    final gen = ++_roadsGen;
    final lines = <Polyline<TrafficEvent>>[];
    try {
      await _collectEventRoads(events, lines);
    } on Exception catch (e, s) {
      debugPrint('event roads failed: $e\n$s');
      _roadsSig = ''; // retry on the next build
      return;
    }
    if (mounted && gen == _roadsGen) setState(() => _eventRoads = lines);
  }

  Future<void> _collectEventRoads(
    List<TrafficEvent> events,
    List<Polyline<TrafficEvent>> lines,
  ) async {
    for (final e in events) {
      if (!e.hasArea) continue;
      final sw = e.areaSouthWest!, ne = e.areaNorthEast!;
      final roads = await RoadsService.instance.roadsIn(
        sw.longitude,
        sw.latitude,
        ne.longitude,
        ne.latitude,
      );
      final color = EventVisuals.color(e.severity);
      final eref = eventRoadRef(e.road);
      final matched = roads.where((r) => roadRefMatches(eref, r.ref)).toList();
      if (matched.isNotEmpty) {
        // Highlight just the matched road to keep the map readable.
        for (final r in matched) {
          lines.add(
            Polyline(
              points: r.points,
              color: color,
              strokeWidth: 4,
              borderColor: Colors.white.withValues(alpha: 0.5),
              borderStrokeWidth: 1,
              hitValue: e,
            ),
          );
        }
      } else {
        // No ref match — faintly tint the roads in the affected area.
        for (final r in roads) {
          lines.add(
            Polyline(
              points: r.points,
              color: color.withValues(alpha: 0.55),
              strokeWidth: 2,
              hitValue: e,
            ),
          );
        }
      }
    }
  }

  void _openEventRoadNotices(List<TrafficEvent> events) {
    final byId = <String, TrafficEvent>{};
    for (final event in events) {
      byId[event.id] = event;
    }
    final notices = byId.values.toList()..sort(_compareMapNotices);
    if (notices.isEmpty) return;
    if (notices.length == 1) {
      showEventSheet(context, notices.single);
      return;
    }
    _showEventChooser(notices);
  }

  /// Sheet height that fits [rows] list tiles under the header, capped so the
  /// map stays visible behind it.
  static double _chooserSize(BuildContext context, int rows) {
    final h = MediaQuery.sizeOf(context).height;
    if (h <= 0) return 0.5;
    return ((64 + rows * 72 + 32) / h).clamp(0.3, 0.7);
  }

  static Widget _chooserDivider(BuildContext context) => Divider(
    height: 1,
    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
  );

  void _showEventChooser(List<TrafficEvent> events) {
    showAppSheet<void>(
      context,
      builder: (sheetContext) => AppSheet(
        title: 'Dogodki na cesti',
        subtitle: 'Izberi obvestilo',
        initialSize: _chooserSize(sheetContext, events.length),
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
        children: [
          for (final (i, event) in events.indexed) ...[
            if (i > 0) _chooserDivider(sheetContext),
            ListTile(
              leading: Icon(
                EventVisuals.causeIcon(event),
                color: EventVisuals.color(event.severity),
              ),
              title: Text(event.title.isEmpty ? event.cause : event.title),
              subtitle: Text(event.road),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showEventSheet(context, event);
              },
            ),
          ],
        ],
      ),
    );
  }

  static List<_RestAreaGroup> _restAreaGroups(List<RestArea> areas) {
    const distance = Distance();
    final groups = <_RestAreaGroup>[];
    for (final area in areas) {
      _RestAreaGroup? match;
      for (final group in groups) {
        if (distance(area.position, group.position) <= 500) {
          match = group;
          break;
        }
      }
      if (match == null) {
        groups.add(_RestAreaGroup([area]));
      } else {
        match.areas.add(area);
      }
    }
    for (final group in groups) {
      group.areas.sort((a, b) => a.title.compareTo(b.title));
    }
    return groups;
  }

  void _openRestAreaGroup(List<RestArea> areas) {
    if (areas.length == 1) {
      showRestAreaSheet(context, areas.single);
      return;
    }
    showAppSheet<void>(
      context,
      builder: (sheetContext) => AppSheet(
        title: 'Počivališča',
        subtitle: 'Izberi počivališče',
        initialSize: _chooserSize(sheetContext, areas.length),
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
        children: [
          for (var i = 0; i < areas.length; i++) ...[
            if (i > 0) _chooserDivider(sheetContext),
            ListTile(
              leading: Icon(
                Icons.local_parking,
                color: restAreaColor(areas[i]),
              ),
              title: Text(
                areas[i].title.isEmpty ? 'Počivališče' : areas[i].title,
              ),
              subtitle: areas[i].hasLiveAvailability
                  ? Text('${areas[i].available} / ${areas[i].total} prostih')
                  : const Text('Ni podatkov o zasedenosti'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showRestAreaSheet(context, areas[i]);
              },
            ),
          ],
        ],
      ),
    );
  }

  int get _activeMapFilterCount =>
      (_showWeather ? 0 : 1) +
      (_showCameras ? 0 : 1) +
      (_showDarsCameras ? 0 : 1) +
      (_showRestAreas ? 0 : 1) +
      (_showBurja ? 0 : 1) +
      (_showDrsi || !DrsiService.isSupported ? 0 : 1) +
      (_severities.length - _eventFilter.length);

  void _openMapFilters() {
    final events = ref.read(eventsProvider).items;
    int count(EventSeverity s) => events.where((e) => e.severity == s).length;

    showFilterSheet(
      context: context,
      title: 'Prikaz na karti',
      contentBuilder: (setSheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FilterSectionLabel('Sloji'),
          _switchRow(
            Icons.thermostat,
            'Vremenske postaje',
            _showWeather,
            (v) => setSheet(() {
              setState(() => _showWeather = v);
              _saveMapFilters();
            }),
          ),
          _switchRow(
            Icons.videocam,
            'Kamere na vremenskih postajah',
            _showCameras,
            (v) => setSheet(() {
              setState(() => _showCameras = v);
              _saveMapFilters();
            }),
          ),
          _switchRow(
            Icons.photo_camera,
            'Prometne kamere (DARS)',
            _showDarsCameras,
            (v) => setSheet(() {
              setState(() => _showDarsCameras = v);
              _saveMapFilters();
            }),
          ),
          _switchRow(
            Icons.local_parking,
            'Počivališča',
            _showRestAreas,
            (v) => setSheet(() {
              setState(() => _showRestAreas = v);
              _saveMapFilters();
            }),
          ),
          _switchRow(
            Icons.air,
            'Burja',
            _showBurja,
            (v) => setSheet(() {
              setState(() => _showBurja = v);
              _saveMapFilters();
            }),
          ),
          // DRSI is plain HTTP without CORS: not reachable from the web build.
          if (DrsiService.isSupported)
            _switchRow(
              Icons.ac_unit,
              'Stanje cestišča (DRSI)',
              _showDrsi,
              (v) => setSheet(() {
                setState(() => _showDrsi = v);
                _saveMapFilters();
              }),
            ),
          const FilterSectionLabel('Dogodki'),
          for (final s in _severities)
            _switchRow(
              EventVisuals.icon(s),
              '${EventVisuals.label(s)} (${count(s)})',
              _eventFilter.contains(s),
              (v) => setSheet(() {
                setState(() {
                  if (v) {
                    _eventFilter.add(s);
                  } else {
                    _eventFilter.remove(s);
                  }
                });
                _saveMapFilters();
              }),
              iconColor: EventVisuals.color(s),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Builder(
            builder: (sheetContext) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: const Text('O aplikaciji', style: TextStyle(fontSize: 15)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(AppRoutes.about);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// A filter row whose label is announced together with its switch and
  /// toggles it when the whole row is tapped.
  Widget _switchRow(
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    Color? iconColor,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      secondary: Icon(icon, color: iconColor),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      value: value,
      onChanged: onChanged,
    );
  }

  /// Move the map to a station and open its sheet. Called via [mapTabKey]
  /// when the user taps "show on map" elsewhere.
  void focusStation(int stationId) {
    final station = ref.read(weatherProvider).byId(stationId);
    if (station == null) return;
    if (_mapReady) {
      _mapController.move(station.position, 12.0);
    }
    _openStation(station);
  }

  /// Centre the map on an arbitrary location (e.g. a tapped traffic event)
  /// and briefly ring it so the target is easy to spot. When [event] is given
  /// its sheet opens too.
  void focusLocation(LatLng location, {TrafficEvent? event}) {
    if (_mapReady) _mapController.move(location, 13.0);
    _focusTimer?.cancel();
    setState(() => _focusHighlight = location);
    _focusTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _focusHighlight = null);
    });
    if (event != null) showEventSheet(context, event);
  }

  /// Location ringed after [focusLocation], cleared after a few seconds.
  LatLng? _focusHighlight;
  Timer? _focusTimer;

  Future<void> _goToMyLocation() async {
    final notifier = ref.read(alertsProvider.notifier);
    if (!ref.read(alertsProvider).locationEnabled) {
      await notifier.enableLocation();
    }
    if (!mounted) return;
    final alerts = ref.read(alertsProvider);
    final problem = alerts.locationProblemMessage;
    if (problem != null) {
      final canFix = alerts.canOpenLocationSettings;
      AdaptiveSnackBar.show(
        context,
        message: problem,
        type: AdaptiveSnackBarType.warning,
        duration: const Duration(seconds: 6),
        action: canFix ? 'Nastavitve' : null,
        onActionPressed: canFix
            ? () => unawaited(notifier.openLocationSettings())
            : null,
      );
      return;
    }
    final p = alerts.position;
    if (p != null && _mapReady) {
      _mapController.move(LatLng(p.latitude, p.longitude), 13);
    }
  }

  void _openStation(WeatherStation station, [DrsiStation? road]) =>
      showStationSheet(context, station.stationId, roadId: road?.id);

  @override
  Widget build(BuildContext context) {
    // No app bar: the map fills the whole screen for maximum map area.
    // The map itself watches no provider: each marker layer below is its own
    // widget that rebuilds only when its own data changes. Previously any
    // provider notifying (a GPS fix, a poll, a loading flag) rebuilt every
    // marker on the map.
    return AdaptiveScaffold(
      body: Consumer(
        builder: (context, ref, _) {
          final cs = Theme.of(context).colorScheme;
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final stationFlags = (
            weather: _showWeather,
            cameras: _showCameras,
            road: _showDrsi && DrsiService.isSupported,
          );
          // Message to show when loading failed with nothing to fall back on.
          final weatherError = ref.watch(
            weatherProvider.select(
              (s) => s.error != null && !s.hasData ? s.error : null,
            ),
          );

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _sloveniaCenter,
                  initialZoom: _initialZoom,
                  minZoom: 7,
                  maxZoom: 17,
                  // Dark surface so loading tiles don't flash white in dark mode.
                  backgroundColor: cs.surface,
                  // Allow pan/zoom but not rotation.
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onMapReady: () => _mapReady = true,
                  // Only rebuild when crossing a thumbnail threshold or a
                  // whole cluster zoom level, not on every pan/zoom frame.
                  onPositionChanged: (camera, _) {
                    final size = ThumbnailSize.forZoom(
                      camera.zoom,
                      minZoom: _thumbnailZoom,
                    );
                    final camSize = ThumbnailSize.forZoom(
                      camera.zoom,
                      minZoom: _cameraThumbnailZoom,
                    );
                    final clusterZoom = _clusterZoomFor(camera.zoom);
                    if (size != _thumbnailSize ||
                        camSize != _cameraThumbnailSize ||
                        clusterZoom != _clusterZoom) {
                      setState(() {
                        _thumbnailSize = size;
                        _cameraThumbnailSize = camSize;
                        _clusterZoom = clusterZoom;
                      });
                    }
                  },
                ),
                children: [
                  buildBaseTileLayer(context, base: _baseMap, isDark: isDark),
                  ...buildBaseOverlayLayers(_baseMap),
                  // Affected-area roads for the visible events (under markers).
                  if (_eventRoads.isNotEmpty)
                    GestureDetector(
                      onTap: () => _openEventRoadNotices(
                        _eventRoadHitNotifier.value?.hitValues ?? const [],
                      ),
                      child: PolylineLayer<TrafficEvent>(
                        hitNotifier: _eventRoadHitNotifier,
                        polylines: _eventRoads,
                      ),
                    ),
                  // DARS cameras and camera-only stations, merged into
                  // count badges where they would pile up.
                  _CamerasLayer(
                    stationFlags: stationFlags,
                    showDars: _showDarsCameras,
                    thumbnailSize: _cameraThumbnailSize,
                    stationThumbnailSize: _thumbnailSize,
                    clusterZoom: _clusterZoom,
                    onTapStation: _openStation,
                    onTapCluster: _zoomToCluster,
                  ),
                  if (_showRestAreas)
                    _RestAreasLayer(onTapGroup: _openRestAreaGroup),
                  if (_showBurja) const _BurjaLayer(),
                  // Weather + DRSI road stations; ones sharing a spot are
                  // one pin.
                  _StationsLayer(
                    flags: stationFlags,
                    thumbnailSize: _thumbnailSize,
                    onTap: _openStation,
                  ),
                  // Traffic events render on top of the camera/weather pins
                  // and their webcam frames, so a frame never buries one.
                  _EventsLayer(
                    filterKey: _eventFilter.map((e) => e.index).toList()
                      ..sort(),
                    onVisibleChanged: _onVisibleEventsChanged,
                  ),
                  const _UserLocationLayer(),
                  if (_focusHighlight != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _focusHighlight!,
                          width: 64,
                          height: 64,
                          child: const IgnorePointer(child: _FocusRing()),
                        ),
                      ],
                    ),
                  buildBaseMapAttribution(
                    _baseMap,
                    bottomInset: AppTheme.bottomBarContentInset(context),
                  ),
                ],
              ),
              // Scrim behind the status bar so pins and webcam frames
              // scrolled under it don't make the clock unreadable.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.paddingOf(context).top + 12,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          cs.surface.withValues(alpha: 0.9),
                          cs.surface.withValues(alpha: 0.6),
                          cs.surface.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.6, 1],
                      ),
                    ),
                  ),
                ),
              ),
              if (weatherError != null)
                _errorBanner(
                  context,
                  weatherError,
                  ref.read(weatherProvider.notifier).refresh,
                ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _GlassFilterButton(
                      activeCount: _activeMapFilterCount,
                      onTap: _openMapFilters,
                    ),
                  ),
                ),
              ),
              // Keep the map buttons above the floating iOS tab bar, not just
              // the safe area (it covered the my-location button).
              SafeArea(
                bottom: AppTheme.bottomBarContentInset(context) == 0,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      12,
                      12,
                      12 + AppTheme.bottomBarContentInset(context),
                    ),
                    child: _GlassPanel(
                      children: [
                        _BaseMapMenu(
                          current: _baseMap,
                          onSelected: _setBaseMap,
                        ),
                        _GlassIconButton(
                          icon: Icons.my_location,
                          label: 'Moja lokacija',
                          onTap: _goToMyLocation,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _errorBanner(
    BuildContext context,
    String error,
    Future<void> Function() onRetry,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: AdaptiveCard(
        color: cs.errorContainer,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: cs.onErrorContainer, size: 40),
            const SizedBox(height: 12),
            Text(
              'Podatkov ni mogoče naložiti',
              style: TextStyle(
                color: cs.onErrorContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 240,
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            AdaptiveButton.child(
              onPressed: onRetry,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 18),
                  SizedBox(width: 8),
                  Text('Poskusi znova'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round camera badge for a DARS camera or a camera-only station. When
/// [thumbnailUrl] is set (zoomed in), a live webcam frame sits above it.
class _CameraMarker extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final String? thumbnailUrl;
  final ThumbnailSize thumbnailSize;

  /// Tappable square around the badge (transparent padding).
  static const double hitSize = _minPinHitSize;

  const _CameraMarker({
    required this.label,
    required this.onTap,
    this.thumbnailUrl,
    this.thumbnailSize = ThumbnailSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (thumbnailUrl != null) ...[
              WebcamThumbnail.sized(thumbnailUrl!, thumbnailSize),
              const SizedBox(height: WebcamThumbnail.gap),
            ],
            const SizedBox.square(
              dimension: hitSize,
              child: Center(child: MapCameraBadge()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Several cameras merged at a low zoom; tapping zooms in on them.
class _ClusterMarker extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ClusterMarker({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${cameraCountLabel(count)}, povečaj',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // Sized to the badge, centred on the coordinate (not stretched to
        // the Marker box).
        child: OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: MapClusterBadge(count: count),
        ),
      ),
    );
  }
}

/// "1 kamera", "2 kameri", "3 kamere", "5 kamer" (Slovenian dual/plural).
@visibleForTesting
String cameraCountLabel(int n) {
  final m = n % 100;
  if (m == 1) return '$n kamera';
  if (m == 2) return '$n kameri';
  if (m == 3 || m == 4) return '$n kamere';
  return '$n kamer';
}

/// A rest-area pin tinted by parking availability. When live data is present
/// it becomes a pill showing the free/total space count next to a "P" badge;
/// otherwise it falls back to a compact square "P".
class _RestAreaMarker extends StatelessWidget {
  final List<RestArea> areas;
  final VoidCallback onTap;

  const _RestAreaMarker({required this.areas, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const shadow = [
      BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
    ];

    if (areas.length == 1 && !areas.single.hasLiveAvailability) {
      final color = restAreaColor(areas.single);
      return Semantics(
        button: true,
        label: areas.single.title.isEmpty
            ? 'Počivališče'
            : 'Počivališče ${areas.single.title}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: shadow,
            ),
            child: const Icon(
              Icons.local_parking,
              size: 15,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // The Marker box is only an estimate from digit counts (used for
      // positioning/culling); let the pills take their real size instead of
      // throwing RenderFlex overflows when fonts render wider or taller.
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: shadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < areas.length; i++) ...[
                _RestAreaAvailabilityPill(area: areas[i]),
                if (i < areas.length - 1) const SizedBox(height: 3),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RestAreaAvailabilityPill extends StatelessWidget {
  final RestArea area;

  const _RestAreaAvailabilityPill({required this.area});

  @override
  Widget build(BuildContext context) {
    final color = restAreaColor(area);
    if (!area.hasLiveAvailability) {
      return Container(
        width: 22,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'P',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(3, 2, 7, 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Text(
              'P',
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${area.available}'),
                TextSpan(
                  text: '/${area.total}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestAreaGroup {
  final List<RestArea> areas;

  _RestAreaGroup(this.areas);

  LatLng get position {
    var lat = 0.0;
    var lon = 0.0;
    for (final area in areas) {
      lat += area.position.latitude;
      lon += area.position.longitude;
    }
    return LatLng(lat / areas.length, lon / areas.length);
  }

  double get markerWidth {
    var maxTotal = 0;
    var maxAvailable = 0;
    var hasLive = false;
    for (final area in areas) {
      if (!area.hasLiveAvailability) continue;
      hasLive = true;
      if (area.total > maxTotal) maxTotal = area.total;
      if (area.available > maxAvailable) maxAvailable = area.available;
    }
    if (!hasLive) return 30;
    final digits = '$maxAvailable/$maxTotal'.length;
    return 34 + digits * 7.5;
  }

  double get markerHeight {
    if (areas.length == 1) return 26;
    return 6 + areas.length * 23 + (areas.length - 1) * 3;
  }
}

/// Minimum tappable square for the small circular map pins; the visible pin
/// is centred in it with transparent padding.
const double _minPinHitSize = 40;

/// A circular pin for a burja measurement point, tinted by severity.
class _BurjaMarker extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback onTap;

  static const double pinSize = 28;

  const _BurjaMarker({
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(child: _pin()),
      ),
    );
  }

  Widget _pin() {
    return SizedBox.square(
      dimension: pinSize,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: const Icon(Icons.air, size: 15, color: Colors.white),
      ),
    );
  }
}

/// The user's current-location dot.
class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A73E8),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// Frosted-glass backdrop for the map controls: the blurred map behind a
/// translucent surface with a hairline border.
class _Glass extends StatelessWidget {
  final double radius;
  final Widget child;

  const _Glass({required this.radius, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: const [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      // Clipped, so the blur covers only the control and not the whole map.
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: dark ? 0.55 : 0.68),
              borderRadius: shape,
              border: Border.all(
                color: (dark ? Colors.white : Colors.black).withValues(
                  alpha: dark ? 0.18 : 0.10,
                ),
                width: 0.5,
              ),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}

/// Minimum touch target of the map controls.
const double _glassButtonSize = 44;

/// Vertical stack of glass buttons sharing one frosted capsule.
class _GlassPanel extends StatelessWidget {
  final List<Widget> children;

  const _GlassPanel({required this.children});

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.12);
    return _Glass(
      radius: _glassButtonSize / 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              SizedBox(
                width: _glassButtonSize - 16,
                height: 0.5,
                child: ColoredBox(color: divider),
              ),
            child,
          ],
        ],
      ),
    );
  }
}

/// A 44pt icon button for the map controls (inside a [_Glass] surface).
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: _glassButtonSize,
            child: Icon(icon, color: cs.primary, size: 21),
          ),
        ),
      ),
    );
  }
}

/// Compact glass filter button; a small badge counts the map filters that
/// hide something.
class _GlassFilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _GlassFilterButton({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = activeCount > 0;
    return Tooltip(
      message: 'Filtri',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: active ? 'Filtri, aktivnih: $activeCount' : 'Filtri',
        excludeSemantics: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _Glass(
              radius: _glassButtonSize / 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox.square(
                  dimension: _glassButtonSize,
                  child: Icon(
                    Icons.tune,
                    size: 21,
                    color: active ? cs.primary : cs.onSurface,
                  ),
                ),
              ),
            ),
            if (active)
              Positioned(
                top: -3,
                right: -3,
                child: IgnorePointer(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: cs.surface, width: 1.5),
                    ),
                    child: Text(
                      '$activeCount',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The layers button: a menu of the base maps, the current one ticked.
class _BaseMapMenu extends StatelessWidget {
  final BaseMap current;
  final ValueChanged<BaseMap> onSelected;

  const _BaseMapMenu({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final base in BaseMap.selectable)
          MenuItemButton(
            leadingIcon: SizedBox.square(
              dimension: 18,
              child: base == current ? const Icon(Icons.check, size: 18) : null,
            ),
            onPressed: () => onSelected(base),
            child: Text(base.label),
          ),
      ],
      builder: (context, controller, _) => _GlassIconButton(
        icon: Icons.layers,
        label: 'Zamenjaj podlago',
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// A short-lived pulsing ring marking the spot [MapTabState.focusLocation]
/// moved to.
class _FocusRing extends StatefulWidget {
  const _FocusRing();

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Center(
          child: Container(
            width: 28 + 36 * t,
            height: 28 + 36 * t,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 1 - t),
                width: 3,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Marker layers ────────────────────────────────────────────────────────
// Markers carry stable keys: flutter_map culls off-screen markers, so as the
// map pans the visible list shifts and unkeyed markers would re-mount (and
// reload their webcam thumbnails) on every move.
// Each layer selects only the list it draws, so it rebuilds when that list's
// identity changes (providers replace it on each successful poll), not when
// an unrelated provider notifies. Derived lists are memoized on the inputs'
// identity so grouping/sorting runs once per data refresh, not per build.

/// Memoizes `compute(a, b)` while both inputs are identical to the last call.
class _Memo<A, B, R> {
  A? _a;
  B? _b;
  late R _r;
  bool _has = false;

  R call(A a, B b, R Function(A, B) compute) {
    if (!_has || !identical(a, _a) || !identical(b, _b)) {
      _a = a;
      _b = b;
      _r = compute(a, b);
      _has = true;
    }
    return _r;
  }
}

/// Nearby points merged into one, see [clusterByScreenDistance].
@visibleForTesting
class MapCluster<T> {
  final List<T> items;
  final List<LatLng> points;

  MapCluster._(this.items, this.points);

  /// Mean position of the members.
  LatLng get center {
    var lat = 0.0, lon = 0.0;
    for (final p in points) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / points.length, lon / points.length);
  }
}

/// Greedy screen-space clustering: projects every item to world pixels at
/// [zoom] and joins it to the first cluster whose seed lies within [radius]
/// pixels, else starts a new one. A grid of [radius]-sized cells keeps it
/// O(n). Working in world pixels (not screen pixels) makes the result
/// independent of panning, so it only changes with [zoom] or the data.
@visibleForTesting
List<MapCluster<T>> clusterByScreenDistance<T>(
  List<T> items,
  LatLng Function(T) positionOf, {
  required int zoom,
  double radius = 40,
}) {
  const crs = Epsg3857();
  final z = zoom.toDouble();
  final r2 = radius * radius;
  final clusters = <MapCluster<T>>[];
  final seeds = <Offset>[];
  final grid = <(int, int), List<int>>{};
  for (final item in items) {
    final pos = positionOf(item);
    final p = crs.latLngToOffset(pos, z);
    final cx = (p.dx / radius).floor(), cy = (p.dy / radius).floor();
    int? hit;
    search:
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final i in grid[(cx + dx, cy + dy)] ?? const <int>[]) {
          if ((seeds[i] - p).distanceSquared <= r2) {
            hit = i;
            break search;
          }
        }
      }
    }
    if (hit != null) {
      clusters[hit].items.add(item);
      clusters[hit].points.add(pos);
    } else {
      grid.putIfAbsent((cx, cy), () => []).add(clusters.length);
      seeds.add(p);
      clusters.add(MapCluster._([item], [pos]));
    }
  }
  return clusters;
}

/// One point of the cameras layer: a DARS camera or a camera-only station.
class _CameraPoint {
  final String key;
  final LatLng position;
  final TrafficCamera? camera;
  final WeatherStation? station;

  _CameraPoint.dars(TrafficCamera this.camera)
    : key = 'cam:${camera.id}',
      position = camera.position,
      station = null;

  _CameraPoint.station(WeatherStation this.station)
    : key = 'st:${station.stationId}',
      position = station.position,
      camera = null;
}

/// DARS cameras and camera-only weather stations as round camera badges.
/// Below [clusterZoom]'s threshold nearby badges merge into count badges.
class _CamerasLayer extends ConsumerStatefulWidget {
  final _StationFlags stationFlags;
  final bool showDars;

  /// Thumbnail tier for DARS cameras at the current zoom, or null.
  final ThumbnailSize? thumbnailSize;

  /// Thumbnail tier for camera-only stations at the current zoom, or null.
  final ThumbnailSize? stationThumbnailSize;

  /// Whole zoom to cluster at, or null for no clustering.
  final int? clusterZoom;
  final void Function(WeatherStation, DrsiStation?) onTapStation;
  final void Function(List<LatLng>) onTapCluster;

  const _CamerasLayer({
    required this.stationFlags,
    required this.showDars,
    required this.thumbnailSize,
    required this.stationThumbnailSize,
    required this.clusterZoom,
    required this.onTapStation,
    required this.onTapCluster,
  });

  @override
  ConsumerState<_CamerasLayer> createState() => _CamerasLayerState();
}

class _CamerasLayerState extends ConsumerState<_CamerasLayer> {
  final _visibleMemo =
      _Memo<List<TrafficCamera>, List<WeatherStation>, List<TrafficCamera>>();
  final _pointsMemo =
      _Memo<List<TrafficCamera>, List<WeatherStation>, List<_CameraPoint>>();

  /// Pins already shown once; they don't pop in again after culling.
  final Set<Object> _seen = {};

  // Markers are rebuilt only when the points, the cluster zoom, a thumbnail
  // tier or the 5-minute frame bucket changes, not on every build.
  List<_CameraPoint>? _forPoints;
  int? _forZoom;
  ThumbnailSize? _forSize;
  ThumbnailSize? _forStationSize;
  int? _forBucket;
  List<Marker> _markers = const [];

  @override
  Widget build(BuildContext context) {
    final stations = ref.watch(weatherProvider.select((s) => s.items));
    final cameras = widget.showDars
        ? ref.watch(camerasProvider.select((s) => s.items))
        : const <TrafficCamera>[];
    final cameraStations = ref.watch(
      _pairingProvider(widget.stationFlags).select((p) => p.cameraOnly),
    );
    // De-duplicating against weather-station cameras is O(cameras*stations);
    // do it once per data refresh, not on every build.
    final dars = _visibleMemo(cameras, stations, visibleCameras);
    final points = _pointsMemo(
      dars,
      cameraStations,
      (d, s) => [
        for (final cam in d) _CameraPoint.dars(cam),
        for (final st in s) _CameraPoint.station(st),
      ],
    );
    final zoom = widget.clusterZoom;
    final size = widget.thumbnailSize;
    final stSize = widget.stationThumbnailSize;
    final bucket = size != null || stSize != null ? webcamCacheBucket() : null;
    if (!identical(points, _forPoints) ||
        zoom != _forZoom ||
        size != _forSize ||
        stSize != _forStationSize ||
        bucket != _forBucket) {
      _forPoints = points;
      _forZoom = zoom;
      _forSize = size;
      _forStationSize = stSize;
      _forBucket = bucket;
      _markers = _buildMarkers(points, zoom, bucket);
    }
    return MarkerLayer(markers: _markers);
  }

  List<Marker> _buildMarkers(
    List<_CameraPoint> points,
    int? zoom,
    int? bucket,
  ) {
    if (zoom == null) {
      return [for (final p in points) _single(p, bucket)];
    }
    return [
      for (final c in clusterByScreenDistance(
        points,
        (p) => p.position,
        zoom: zoom,
      ))
        if (c.items.length == 1)
          _single(c.items.single, bucket)
        else
          _cluster(c),
    ];
  }

  Marker _cluster(MapCluster<_CameraPoint> c) {
    // Keyed by the first member, not the zoom: a cluster that survives a
    // zoom step keeps its state and doesn't pop in again.
    final key = 'cl:${c.items.first.key}';
    final width = math.max(
      MapClusterBadge.estimateWidth(c.items.length),
      _minPinHitSize,
    );
    return Marker(
      key: ValueKey(key),
      point: c.center,
      width: width,
      height: _minPinHitSize,
      child: MapPopIn(
        id: key,
        seen: _seen,
        child: _ClusterMarker(
          count: c.items.length,
          onTap: () => widget.onTapCluster(c.points),
        ),
      ),
    );
  }

  Marker _single(_CameraPoint p, int? bucket) {
    final cam = p.camera;
    final station = p.station;
    final String label;
    final VoidCallback onTap;
    String? thumb;
    ThumbnailSize? size;
    if (cam != null) {
      final title = cam.title.trim();
      label = title.isEmpty ? 'Prometna kamera' : 'Kamera $title';
      onTap = () => showCameraSheet(context, cam);
      size = widget.thumbnailSize;
      if (size != null && bucket != null && cam.imageUrl.isNotEmpty) {
        thumb = cam.imageUrlWithBuster(bucket);
      }
    } else {
      final st = station!;
      final name = st.name.trim();
      label = 'Kamera $name'.trim();
      onTap = () => widget.onTapStation(st, null);
      size = widget.stationThumbnailSize;
      if (size != null && bucket != null && st.cameraLink.isNotEmpty) {
        thumb = st.cameraUrlWithBuster(bucket);
      }
    }
    const pin = _CameraMarker.hitSize;
    if (thumb == null || size == null) {
      return Marker(
        key: ValueKey(p.key),
        point: p.position,
        width: pin,
        height: pin,
        child: MapPopIn(
          id: p.key,
          seen: _seen,
          child: _CameraMarker(label: label, onTap: onTap),
        ),
      );
    }
    final width = math.max(size.width, pin);
    final height = size.extent + pin;
    return Marker(
      key: ValueKey(p.key),
      point: p.position,
      width: width,
      height: height,
      // Keep the badge's centre (not the box centre) on the coordinate.
      alignment: Marker.computePixelAlignment(
        width: width,
        height: height,
        left: width / 2,
        top: height - pin / 2,
      ),
      child: MapPopIn(
        id: p.key,
        seen: _seen,
        alignment: Alignment.bottomCenter,
        child: _CameraMarker(
          label: label,
          thumbnailUrl: thumb,
          thumbnailSize: size,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _RestAreasLayer extends ConsumerStatefulWidget {
  final void Function(List<RestArea>) onTapGroup;
  const _RestAreasLayer({required this.onTapGroup});

  @override
  ConsumerState<_RestAreasLayer> createState() => _RestAreasLayerState();
}

class _RestAreasLayerState extends ConsumerState<_RestAreasLayer> {
  final _memo = _Memo<List<RestArea>, Object?, List<_RestAreaGroup>>();

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(restAreasProvider.select((s) => s.items));
    final groups = _memo(items, null, (a, _) => MapTabState._restAreaGroups(a));
    return MarkerLayer(
      markers: [
        for (final group in groups)
          Marker(
            key: ValueKey('rest:${group.areas.first.id}'),
            point: group.position,
            width: group.markerWidth,
            height: group.markerHeight,
            child: _RestAreaMarker(
              areas: group.areas,
              onTap: () => widget.onTapGroup(group.areas),
            ),
          ),
      ],
    );
  }
}

class _BurjaLayer extends ConsumerWidget {
  const _BurjaLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(burjaProvider.select((s) => s.items));
    return MarkerLayer(
      markers: [
        for (final st in items)
          Marker(
            key: ValueKey('burja:${st.id}'),
            point: st.position,
            width: _minPinHitSize,
            height: _minPinHitSize,
            child: _BurjaMarker(
              color: burjaColor(st.level),
              label:
                  '${st.title.trim().isEmpty ? 'Burja' : 'Burja ${st.title.trim()}'}'
                  ', sunki ${st.gust.round()} km/h',
              onTap: () => showBurjaSheet(context, st),
            ),
          ),
      ],
    );
  }
}

/// Which station kinds the map shows: weather stations, camera-only
/// stations, DRSI road stations.
typedef _StationFlags = ({bool weather, bool cameras, bool road});

/// Weather stations paired with the DRSI road stations sharing their spot.
class _Pairing {
  /// A road station within [_pairMeters] of a visible weather station is
  /// folded into that station's pin (one capsule, one tap, one sheet).
  static const double _pairMeters = 400;

  /// Visible stations drawn as capsules (by the stations layer).
  final List<WeatherStation> pills;

  /// Visible camera-only stations with no road station: round camera badges
  /// (drawn and clustered by the cameras layer).
  final List<WeatherStation> cameraOnly;
  final Map<int, DrsiStation> roadByStation;

  /// Road stations with no weather station nearby: their own capsule.
  final List<DrsiStation> loneRoads;

  const _Pairing._(
    this.pills,
    this.cameraOnly,
    this.roadByStation,
    this.loneRoads,
  );

  /// Pair each road station with its nearest visible weather station.
  factory _Pairing.compute(
    List<WeatherStation> stations,
    List<DrsiStation> roads,
    _StationFlags flags,
  ) {
    bool visible(WeatherStation s) =>
        s.hasWeather ? flags.weather : flags.cameras;
    const distance = Distance();
    final byStation = <int, DrsiStation>{};
    final lone = <DrsiStation>[];
    for (final road in roads) {
      WeatherStation? best;
      var bestD = _pairMeters;
      for (final s in stations) {
        if (!visible(s) || byStation.containsKey(s.stationId)) continue;
        // Cheap reject before the exact distance.
        if ((s.position.latitude - road.position.latitude).abs() > 0.01) {
          continue;
        }
        final d = distance(s.position, road.position);
        if (d <= bestD) {
          bestD = d;
          best = s;
        }
      }
      if (best != null) {
        byStation[best.stationId] = road;
      } else {
        lone.add(road);
      }
    }
    final pills = <WeatherStation>[];
    final cameraOnly = <WeatherStation>[];
    for (final s in stations) {
      if (!visible(s)) continue;
      if (s.temperatureC == null && !byStation.containsKey(s.stationId)) {
        cameraOnly.add(s);
      } else {
        pills.add(s);
      }
    }
    return _Pairing._(pills, cameraOnly, byStation, lone);
  }
}

/// Station pairing for the given flags, shared by the stations and cameras
/// layers so it runs once per data refresh.
final _pairingProvider = Provider.autoDispose.family<_Pairing, _StationFlags>((
  ref,
  flags,
) {
  final stations = ref.watch(weatherProvider.select((s) => s.items));
  final roads = flags.road
      ? ref.watch(drsiProvider.select((s) => s.items))
      : const <DrsiStation>[];
  return _Pairing.compute(stations, roads, flags);
});

/// Weather stations and DRSI road stations as capsules; ones sharing a spot
/// are one pin. Camera-only stations are drawn by [_CamerasLayer].
class _StationsLayer extends ConsumerStatefulWidget {
  final _StationFlags flags;

  /// Thumbnail tier for the current zoom, or null for plain pins.
  final ThumbnailSize? thumbnailSize;
  final void Function(WeatherStation, DrsiStation?) onTap;

  const _StationsLayer({
    required this.flags,
    required this.thumbnailSize,
    required this.onTap,
  });

  @override
  ConsumerState<_StationsLayer> createState() => _StationsLayerState();
}

class _StationsLayerState extends ConsumerState<_StationsLayer> {
  /// Pins already shown once; they don't pop in again after culling.
  final Set<Object> _seen = {};

  @override
  Widget build(BuildContext context) {
    final pairing = ref.watch(_pairingProvider(widget.flags));
    // Frames refresh in 5-minute steps so rebuilds reuse the cached image.
    final bucket = webcamCacheBucket();
    return MarkerLayer(
      markers: [
        for (final station in pairing.pills)
          _stationMarker(
            station,
            pairing.roadByStation[station.stationId],
            bucket,
          ),
        for (final road in pairing.loneRoads) _roadMarker(road),
      ],
    );
  }

  Marker _roadMarker(DrsiStation road) {
    final key = 'drsi:${road.id}';
    return Marker(
      key: ValueKey(key),
      point: road.position,
      width: DrsiMarker.pinWidth,
      height: MapPinStyle.pinHeight + 6,
      // Bottom of the box (the pointer tip) sits on the coordinate.
      alignment: Alignment.topCenter,
      child: MapPopIn(
        id: key,
        seen: _seen,
        alignment: Alignment.bottomCenter,
        child: DrsiMarker(
          station: road,
          onTap: () => showRoadStationSheet(context, road),
        ),
      ),
    );
  }

  Marker _stationMarker(WeatherStation station, DrsiStation? road, int bucket) {
    final size = widget.thumbnailSize;
    final thumb = size != null && station.cameraLink.isNotEmpty
        ? station.cameraUrlWithBuster(bucket)
        : null;
    final pinWidth = TemperatureMarker.pinWidth(
      hasWeather: station.temperatureC != null,
      hasRoad: road != null,
    );
    final key = 'st:${station.stationId}';
    return Marker(
      key: ValueKey(key),
      point: station.position,
      width: thumb != null && size != null
          ? math.max(size.width, pinWidth)
          : pinWidth,
      height:
          MapPinStyle.pinHeight +
          6 +
          (thumb != null && size != null ? size.extent : 0),
      // Bottom of the box (the pointer tip) sits on the coordinate.
      alignment: Alignment.topCenter,
      child: MapPopIn(
        id: key,
        seen: _seen,
        alignment: Alignment.bottomCenter,
        child: TemperatureMarker(
          station: station,
          road: road,
          thumbnailUrl: thumb,
          thumbnailSize: size ?? ThumbnailSize.small,
          onTap: () => widget.onTap(station, road),
        ),
      ),
    );
  }
}

class _EventsLayer extends ConsumerStatefulWidget {
  /// Sorted severity indexes that pass the filter.
  final List<int> filterKey;
  final void Function(List<TrafficEvent>) onVisibleChanged;

  const _EventsLayer({required this.filterKey, required this.onVisibleChanged});

  @override
  ConsumerState<_EventsLayer> createState() => _EventsLayerState();
}

class _EventsLayerState extends ConsumerState<_EventsLayer> {
  List<TrafficEvent>? _source;
  String _filter = '';
  List<TrafficEvent> _visible = const [];

  /// Pins already shown once; they don't pop in again after culling.
  final Set<Object> _seen = {};

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider.select((s) => s.items));
    final filter = widget.filterKey.join(',');
    if (!identical(events, _source) || filter != _filter) {
      _source = events;
      _filter = filter;
      final allowed = widget.filterKey.toSet();
      _visible =
          events.where((e) => allowed.contains(e.severity.index)).toList()
            ..sort(MapTabState._compareMapDrawOrder);
      widget.onVisibleChanged(_visible);
    }
    return MarkerLayer(
      markers: [
        for (final event in _visible)
          Marker(
            key: ValueKey('ev:${event.id}'),
            point: event.position,
            width: _minPinHitSize,
            height: _minPinHitSize,
            child: MapPopIn(
              id: event.id,
              seen: _seen,
              child: EventMarker(
                event: event,
                hitSize: _minPinHitSize,
                onTap: () => showEventSheet(context, event),
              ),
            ),
          ),
      ],
    );
  }
}

class _UserLocationLayer extends ConsumerWidget {
  const _UserLocationLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuilds on GPS updates without touching the other layers.
    final pos = ref.watch(
      alertsProvider.select((a) {
        final p = a.position;
        return p == null ? null : LatLng(p.latitude, p.longitude);
      }),
    );
    if (pos == null) return const SizedBox.shrink();
    return MarkerLayer(
      markers: [
        Marker(point: pos, width: 22, height: 22, child: const _UserDot()),
      ],
    );
  }
}
