import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/traffic_event.dart';
import '../models/weather_station.dart';
import '../providers/alerts_controller.dart';
import '../providers/burja_provider.dart';
import '../providers/cameras_provider.dart';
import '../providers/events_provider.dart';
import '../providers/rest_areas_provider.dart';
import '../providers/weather_provider.dart';
import '../services/map_tile_cache_service.dart';
import '../services/prefs.dart';
import '../services/roads_service.dart';
import '../widgets/burja_sheet.dart';
import '../widgets/camera_sheet.dart';
import '../widgets/event_marker.dart';
import '../widgets/event_sheet.dart';
import '../widgets/event_visuals.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/rest_area_sheet.dart';
import '../widgets/station_sheet.dart';
import '../widgets/temperature_marker.dart';

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
  final Set<EventSeverity> _eventFilter = {..._severities};

  // Affected-area road highlights for the visible events.
  List<Polyline<TrafficEvent>> _eventRoads = const [];
  String _roadsSig = '';

  @override
  void dispose() {
    _eventRoadHitNotifier.dispose();
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

  /// Recompute the highlighted roads inside each visible event's affected area
  /// when the visible event set changes.
  Future<void> _refreshEventRoads(List<TrafficEvent> events) async {
    final lines = <Polyline<TrafficEvent>>[];
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
    if (mounted) setState(() => _eventRoads = lines);
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

  void _showEventChooser(List<TrafficEvent> events) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Text(
                      'Izberi obvestilo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: events.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: cs.outline.withValues(alpha: 0.2),
                      ),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        final color = EventVisuals.color(event.severity);
                        final title = event.title.isEmpty
                            ? event.cause
                            : event.title;
                        return ListTile(
                          leading: Icon(
                            EventVisuals.causeIcon(event),
                            color: color,
                          ),
                          title: Text(title),
                          subtitle: Text(event.road),
                          onTap: () {
                            Navigator.of(context).pop();
                            showEventSheet(context, event);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _stationVisible(WeatherStation s) =>
      s.hasWeather ? _showWeather : _showCameras;

  int get _activeMapFilterCount =>
      (_showWeather ? 0 : 1) +
      (_showCameras ? 0 : 1) +
      (_showDarsCameras ? 0 : 1) +
      (_showRestAreas ? 0 : 1) +
      (_showBurja ? 0 : 1) +
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
          const FilterSectionLabel('Postaje'),
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
            'Kamere',
            _showCameras,
            (v) => setSheet(() {
              setState(() => _showCameras = v);
              _saveMapFilters();
            }),
          ),
          _switchRow(
            Icons.photo_camera,
            'DARS kamere',
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
        ],
      ),
    );
  }

  Widget _switchRow(
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
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

  /// Centre the map on an arbitrary location (e.g. a tapped traffic event).
  void focusLocation(LatLng location) {
    if (_mapReady) _mapController.move(location, 13.0);
  }

  Future<void> _goToMyLocation() async {
    final alerts = context.read<AlertsController>();
    if (!alerts.locationEnabled) await alerts.enableLocation();
    final p = alerts.position;
    if (p != null && _mapReady) {
      _mapController.move(LatLng(p.latitude, p.longitude), 13);
    }
  }

  void _openStation(WeatherStation station) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StationSheet(stationId: station.stationId),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No app bar: the map fills the whole screen for maximum map area.
    return AdaptiveScaffold(
      body: Consumer<WeatherProvider>(
        builder: (context, provider, _) {
          final cs = Theme.of(context).colorScheme;
          final isDark = Theme.of(context).brightness == Brightness.dark;

          // Events shown on the map (after the severity filter).
          final visibleEvents = context
              .watch<EventsProvider>()
              .events
              .where((e) => _eventFilter.contains(e.severity))
              .toList()
            ..sort(_compareMapDrawOrder);
          final myPos = context.watch<AlertsController>().position;
          final myLocation = myPos == null
              ? null
              : LatLng(myPos.latitude, myPos.longitude);

          // Recompute affected-road highlights only when the visible set changes.
          final sig = visibleEvents
              .map((e) => '${e.id}:${e.severity.index}')
              .join('|');
          if (sig != _roadsSig) {
            _roadsSig = sig;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _refreshEventRoads(visibleEvents),
            );
          }

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
                ),
                children: [
                  TileLayer(
                    // Light: OpenStreetMap. Dark: CARTO Dark Matter basemap.
                    urlTemplate: isDark
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    tileProvider: MapTileCacheService.instance.createTileProvider(),
                    subdomains: isDark
                        ? const ['a', 'b', 'c', 'd']
                        : const [],
                    retinaMode: isDark && RetinaMode.isHighDensity(context),
                    userAgentPackageName: 'dev.dz0ny.promet',
                    maxZoom: 19,
                  ),
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
                  // DARS cameras.
                  if (_showDarsCameras)
                    MarkerLayer(
                      markers: [
                        for (final cam
                            in context.watch<CamerasProvider>().cameras)
                          Marker(
                            point: cam.position,
                            width: 26,
                            height: 26,
                            child: _CameraMarker(
                              onTap: () => showCameraSheet(context, cam),
                            ),
                          ),
                      ],
                    ),
                  // Rest areas with live parking availability.
                  if (_showRestAreas)
                    MarkerLayer(
                      markers: [
                        for (final area
                            in context.watch<RestAreasProvider>().items)
                          Marker(
                            point: area.position,
                            width: area.hasLiveAvailability ? 78 : 26,
                            height: 26,
                            child: _RestAreaMarker(
                              color: restAreaColor(area),
                              available: area.available,
                              total: area.total,
                              onTap: () => showRestAreaSheet(context, area),
                            ),
                          ),
                      ],
                    ),
                  // Burja (crosswind) measurement points.
                  if (_showBurja)
                    MarkerLayer(
                      markers: [
                        for (final st
                            in context.watch<BurjaProvider>().items)
                          Marker(
                            point: st.position,
                            width: 28,
                            height: 28,
                            child: _BurjaMarker(
                              color: burjaColor(st.level),
                              onTap: () => showBurjaSheet(context, st),
                            ),
                          ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      for (final station in provider.stations)
                        if (_stationVisible(station))
                          Marker(
                            point: station.position,
                            width: station.hasWeather ? 60 : 34,
                            height: 44,
                            alignment: Alignment.topCenter,
                            child: TemperatureMarker(
                              station: station,
                              onTap: () => _openStation(station),
                            ),
                          ),
                    ],
                  ),
                  // Traffic events render on top of the weather markers.
                  MarkerLayer(
                    markers: [
                      for (final event in visibleEvents)
                        Marker(
                          point: event.position,
                          width: 28,
                          height: 28,
                          child: EventMarker(
                            event: event,
                            onTap: () => showEventSheet(context, event),
                          ),
                        ),
                    ],
                  ),
                  // The user's current location.
                  if (myLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: myLocation,
                          width: 22,
                          height: 22,
                          child: const _UserDot(),
                        ),
                      ],
                    ),
                ],
              ),
              if (provider.error != null && !provider.hasData)
                _errorBanner(context, provider),
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
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _MapButton(
                      icon: Icons.my_location,
                      onTap: _goToMyLocation,
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

/// A small circular pin for a DARS camera.
class _CameraMarker extends StatelessWidget {
  final VoidCallback onTap;

  const _CameraMarker({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF455A64),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
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
  final Color color;
  final int available;
  final int total;
  final VoidCallback onTap;

  const _RestAreaMarker({
    required this.color,
    required this.available,
    required this.total,
    required this.onTap,
  });

  bool get _live => total > 0;

  @override
  Widget build(BuildContext context) {
    const shadow = [
      BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
    ];

    if (!_live) {
      return GestureDetector(
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
          child: const Icon(Icons.local_parking, size: 15, color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // "P" badge in a white circle.
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  'P',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Free count, emphasised, over the total.
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$available'),
                    TextSpan(
                      text: '/$total',
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
        ),
      ),
    );
  }
}

/// A circular pin for a burja measurement point, tinted by severity.
class _BurjaMarker extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _BurjaMarker({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
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
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
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
    );
  }
}
