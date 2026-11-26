import 'dart:async';
import 'dart:math' as math;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/rest_area.dart';
import '../models/drsi_station.dart';
import '../models/burja_station.dart';
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
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => MapTabState();
}

class MapTabState extends State<MapTab> {
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

  // Base map tiles: OpenStreetMap or Seznam (Mapy.cz), as in gozdar.
  BaseMap _baseMap = BaseMap.saved;

  void _toggleBaseMap() {
    setState(() {
      _baseMap = _baseMap == BaseMap.openStreetMap
          ? BaseMap.seznam
          : BaseMap.openStreetMap;
    });
    BaseMap.saved = _baseMap;
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
    final events = context.read<EventsProvider>().events;
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
    final station = context.read<WeatherProvider>().byId(stationId);
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
    final alerts = context.read<AlertsController>();
    if (!alerts.locationEnabled) await alerts.enableLocation();
    if (!mounted) return;
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
            ? () => unawaited(alerts.openLocationSettings())
            : null,
      );
      return;
    }
    final p = alerts.position;
    if (p != null && _mapReady) {
      _mapController.move(LatLng(p.latitude, p.longitude), 13);
    }
  }

  void _openStation(WeatherStation station) =>
      showStationSheet(context, station.stationId);

  @override
  Widget build(BuildContext context) {
    // No app bar: the map fills the whole screen for maximum map area.
    // The map itself watches no provider: each marker layer below is its own
    // widget that rebuilds only when its own data changes. Previously any
    // provider notifying (a GPS fix, a poll, a loading flag) rebuilt every
    // marker on the map.
    return AdaptiveScaffold(
      body: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final showWeatherError = context.select<WeatherProvider, bool>(
            (p) => p.error != null && !p.hasData,
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
                  // Only rebuild when crossing a thumbnail threshold, not
                  // on every pan/zoom frame.
                  onPositionChanged: (camera, _) {
                    final size = ThumbnailSize.forZoom(
                      camera.zoom,
                      minZoom: _thumbnailZoom,
                    );
                    final camSize = ThumbnailSize.forZoom(
                      camera.zoom,
                      minZoom: _cameraThumbnailZoom,
                    );
                    if (size != _thumbnailSize ||
                        camSize != _cameraThumbnailSize) {
                      setState(() {
                        _thumbnailSize = size;
                        _cameraThumbnailSize = camSize;
                      });
                    }
                  },
                ),
                children: [
                  buildBaseTileLayer(context, base: _baseMap, isDark: isDark),
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
                  if (_showDarsCameras)
                    _DarsCamerasLayer(thumbnailSize: _cameraThumbnailSize),
                  if (_showRestAreas)
                    _RestAreasLayer(onTapGroup: _openRestAreaGroup),
                  if (_showBurja) const _BurjaLayer(),
                  _WeatherStationsLayer(
                    showWeather: _showWeather,
                    showCameras: _showCameras,
                    thumbnailSize: _thumbnailSize,
                    onTap: _openStation,
                  ),
                  // DRSI road stations sit above the weather pins, which
                  // often share the spot.
                  if (_showDrsi && DrsiService.isSupported) const _DrsiLayer(),
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
              if (showWeatherError)
                _errorBanner(context, context.read<WeatherProvider>()),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilterButton(
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (BaseMap.seznamAvailable) ...[
                          _MapButton(
                            icon: Icons.layers,
                            label: 'Zamenjaj podlago',
                            onTap: _toggleBaseMap,
                          ),
                          const SizedBox(height: 10),
                        ],
                        _MapButton(
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

  Widget _errorBanner(BuildContext context, WeatherProvider provider) {
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
                provider.error ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            AdaptiveButton.child(
              onPressed: provider.refresh,
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

/// A small circular pin for a DARS camera. When [thumbnailUrl] is set
/// (zoomed in), a live webcam frame sits above the pin.
class _CameraMarker extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final String? thumbnailUrl;
  final ThumbnailSize thumbnailSize;

  /// Visible pin diameter.
  static const double pinSize = 26;

  /// Tappable square around the pin (transparent padding).
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
            SizedBox.square(
              dimension: hitSize,
              child: Center(child: _pin()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pin() {
    return SizedBox.square(
      dimension: pinSize,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF455A64),
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
        child: const Icon(Icons.photo_camera, size: 13, color: Colors.white),
      ),
    );
  }
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

/// A circular map overlay button (e.g. "my location").
class _MapButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MapButton({
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
        child: Material(
          color: cs.surface.withValues(alpha: 0.95),
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Icon(icon, color: cs.primary, size: 22),
            ),
          ),
        ),
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

class _DarsCamerasLayer extends StatefulWidget {
  /// Thumbnail tier for the current zoom, or null for plain pins.
  final ThumbnailSize? thumbnailSize;
  const _DarsCamerasLayer({required this.thumbnailSize});

  @override
  State<_DarsCamerasLayer> createState() => _DarsCamerasLayerState();
}

class _DarsCamerasLayerState extends State<_DarsCamerasLayer> {
  final _visibleMemo =
      _Memo<List<TrafficCamera>, List<WeatherStation>, List<TrafficCamera>>();
  // Markers are rebuilt only when the visible list, the thumbnail tier or
  // the 5-minute frame bucket changes, not on every build.
  List<TrafficCamera>? _markersFor;
  ThumbnailSize? _markersSize;
  int? _markersBucket;
  List<Marker> _markers = const [];

  @override
  Widget build(BuildContext context) {
    final cameras = context.select<CamerasProvider, List<TrafficCamera>>(
      (p) => p.cameras,
    );
    final stations = context.select<WeatherProvider, List<WeatherStation>>(
      (p) => p.stations,
    );
    // De-duplicating against weather-station cameras is O(cameras*stations);
    // do it once per data refresh, not on every build.
    final visible = _visibleMemo(
      cameras,
      stations,
      (_, st) => context.read<CamerasProvider>().visibleCameras(st),
    );
    final size = widget.thumbnailSize;
    final bucket = size != null ? webcamCacheBucket() : null;
    if (!identical(visible, _markersFor) ||
        size != _markersSize ||
        bucket != _markersBucket) {
      _markersFor = visible;
      _markersSize = size;
      _markersBucket = bucket;
      _markers = [for (final cam in visible) _cameraMarker(cam, size, bucket)];
    }
    return MarkerLayer(markers: _markers);
  }

  Marker _cameraMarker(TrafficCamera cam, ThumbnailSize? size, int? bucket) {
    const pin = _CameraMarker.hitSize;
    final label = cam.title.trim().isEmpty
        ? 'Prometna kamera'
        : 'Kamera ${cam.title.trim()}';
    final thumb = size != null && bucket != null && cam.imageUrl.isNotEmpty
        ? cam.imageUrlWithBuster(bucket)
        : null;
    if (thumb == null || size == null) {
      return Marker(
        key: ValueKey('cam:${cam.id}'),
        point: cam.position,
        width: pin,
        height: pin,
        child: _CameraMarker(
          label: label,
          onTap: () => showCameraSheet(context, cam),
        ),
      );
    }
    final width = math.max(size.width, pin);
    final height = size.extent + pin;
    return Marker(
      key: ValueKey('cam:${cam.id}'),
      point: cam.position,
      width: width,
      height: height,
      // Keep the pin's centre (not the box centre) on the coordinate.
      alignment: Marker.computePixelAlignment(
        width: width,
        height: height,
        left: width / 2,
        top: height - pin / 2,
      ),
      child: _CameraMarker(
        label: label,
        thumbnailUrl: thumb,
        thumbnailSize: size,
        onTap: () => showCameraSheet(context, cam),
      ),
    );
  }
}

class _RestAreasLayer extends StatefulWidget {
  final void Function(List<RestArea>) onTapGroup;
  const _RestAreasLayer({required this.onTapGroup});

  @override
  State<_RestAreasLayer> createState() => _RestAreasLayerState();
}

class _RestAreasLayerState extends State<_RestAreasLayer> {
  final _memo = _Memo<List<RestArea>, Object?, List<_RestAreaGroup>>();

  @override
  Widget build(BuildContext context) {
    final items = context.select<RestAreasProvider, List<RestArea>>(
      (p) => p.items,
    );
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

class _BurjaLayer extends StatelessWidget {
  const _BurjaLayer();

  @override
  Widget build(BuildContext context) {
    final items = context.select<BurjaProvider, List<BurjaStation>>(
      (p) => p.items,
    );
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

class _WeatherStationsLayer extends StatelessWidget {
  final bool showWeather;
  final bool showCameras;

  /// Thumbnail tier for the current zoom, or null for plain pins.
  final ThumbnailSize? thumbnailSize;
  final void Function(WeatherStation) onTap;

  const _WeatherStationsLayer({
    required this.showWeather,
    required this.showCameras,
    required this.thumbnailSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stations = context.select<WeatherProvider, List<WeatherStation>>(
      (p) => p.stations,
    );
    // Frames refresh in 5-minute steps so rebuilds reuse the cached image.
    final bucket = webcamCacheBucket();
    return MarkerLayer(
      markers: [
        for (final station in stations)
          if (station.hasWeather ? showWeather : showCameras)
            _stationMarker(station, bucket),
      ],
    );
  }

  Marker _stationMarker(WeatherStation station, int bucket) {
    final size = thumbnailSize;
    final thumb = size != null && station.cameraLink.isNotEmpty
        ? station.cameraUrlWithBuster(bucket)
        : null;
    return Marker(
      key: ValueKey('st:${station.stationId}'),
      point: station.position,
      width: thumb != null && size != null
          ? size.width
          : (station.hasWeather ? 60 : 34),
      height: 44 + (thumb != null && size != null ? size.extent : 0),
      // Bottom of the box (the pointer tip) sits on the coordinate.
      alignment: Alignment.topCenter,
      child: TemperatureMarker(
        station: station,
        thumbnailUrl: thumb,
        thumbnailSize: size ?? ThumbnailSize.small,
        onTap: () => onTap(station),
      ),
    );
  }
}

class _DrsiLayer extends StatelessWidget {
  const _DrsiLayer();

  @override
  Widget build(BuildContext context) {
    final items = context.select<DrsiProvider, List<DrsiStation>>(
      (p) => p.items,
    );
    return MarkerLayer(
      markers: [
        for (final st in items)
          Marker(
            key: ValueKey('drsi:${st.id}'),
            point: st.position,
            width: 56,
            height: 26,
            child: DrsiMarker(
              station: st,
              onTap: () => showDrsiSheet(context, st),
            ),
          ),
      ],
    );
  }
}

class _EventsLayer extends StatefulWidget {
  /// Sorted severity indexes that pass the filter.
  final List<int> filterKey;
  final void Function(List<TrafficEvent>) onVisibleChanged;

  const _EventsLayer({required this.filterKey, required this.onVisibleChanged});

  @override
  State<_EventsLayer> createState() => _EventsLayerState();
}

class _EventsLayerState extends State<_EventsLayer> {
  List<TrafficEvent>? _source;
  String _filter = '';
  List<TrafficEvent> _visible = const [];

  @override
  Widget build(BuildContext context) {
    final events = context.select<EventsProvider, List<TrafficEvent>>(
      (p) => p.events,
    );
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
            child: EventMarker(
              event: event,
              hitSize: _minPinHitSize,
              onTap: () => showEventSheet(context, event),
            ),
          ),
      ],
    );
  }
}

class _UserLocationLayer extends StatelessWidget {
  const _UserLocationLayer();

  @override
  Widget build(BuildContext context) {
    // Rebuilds on GPS updates without touching the other layers.
    final pos = context.select<AlertsController, LatLng?>((a) {
      final p = a.position;
      return p == null ? null : LatLng(p.latitude, p.longitude);
    });
    if (pos == null) return const SizedBox.shrink();
    return MarkerLayer(
      markers: [
        Marker(point: pos, width: 22, height: 22, child: const _UserDot()),
      ],
    );
  }
}
