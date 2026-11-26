import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
import '../services/prefs.dart';
import '../services/roads_service.dart';
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
  static const double _thumbnailZoom = 11;
  bool _showThumbnails = false;

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
                      'Izberi počivališče',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: areas.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: cs.outline.withValues(alpha: 0.2),
                      ),
                      itemBuilder: (context, index) {
                        final area = areas[index];
                        final color = restAreaColor(area);
                        return ListTile(
                          leading: Icon(Icons.local_parking, color: color),
                          title: Text(
                            area.title.isEmpty ? 'Počivališče' : area.title,
                          ),
                          subtitle: area.hasLiveAvailability
                              ? Text(
                                  '${area.available} / ${area.total} prostih',
                                )
                              : const Text('Ni podatkov o zasedenosti'),
                          onTap: () {
                            Navigator.of(context).pop();
                            showRestAreaSheet(context, area);
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
                  // Only rebuild when crossing the thumbnail threshold, not
                  // on every pan/zoom frame.
                  onPositionChanged: (camera, _) {
                    final show = camera.zoom >= _thumbnailZoom;
                    if (show != _showThumbnails) {
                      setState(() => _showThumbnails = show);
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
                  if (_showDarsCameras) const _DarsCamerasLayer(),
                  if (_showRestAreas)
                    _RestAreasLayer(onTapGroup: _openRestAreaGroup),
                  if (_showBurja) const _BurjaLayer(),
                  _WeatherStationsLayer(
                    showWeather: _showWeather,
                    showCameras: _showCameras,
                    showThumbnails: _showThumbnails,
                    onTap: _openStation,
                  ),
                  // DRSI road stations sit above the weather pins, which
                  // often share the spot.
                  if (_showDrsi && DrsiService.isSupported) const _DrsiLayer(),
                  // Traffic events render on top of the weather markers.
                  _EventsLayer(
                    filterKey: _eventFilter.map((e) => e.index).toList()
                      ..sort(),
                    onVisibleChanged: _onVisibleEventsChanged,
                  ),
                  const _UserLocationLayer(),
                  buildBaseMapAttribution(_baseMap),
                ],
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
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (BaseMap.seznamAvailable) ...[
                          _MapButton(icon: Icons.layers, onTap: _toggleBaseMap),
                          const SizedBox(height: 10),
                        ],
                        _MapButton(
                          icon: Icons.my_location,
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

// ── Marker layers ────────────────────────────────────────────────────────
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
  const _DarsCamerasLayer();

  @override
  State<_DarsCamerasLayer> createState() => _DarsCamerasLayerState();
}

class _DarsCamerasLayerState extends State<_DarsCamerasLayer> {
  final _memo =
      _Memo<List<TrafficCamera>, List<WeatherStation>, List<Marker>>();

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
    final markers = _memo(
      cameras,
      stations,
      (_, st) => [
        for (final cam in context.read<CamerasProvider>().visibleCameras(st))
          Marker(
            point: cam.position,
            width: 26,
            height: 26,
            child: _CameraMarker(onTap: () => showCameraSheet(context, cam)),
          ),
      ],
    );
    return MarkerLayer(markers: markers);
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
            point: st.position,
            width: 28,
            height: 28,
            child: _BurjaMarker(
              color: burjaColor(st.level),
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
  final bool showThumbnails;
  final void Function(WeatherStation) onTap;

  const _WeatherStationsLayer({
    required this.showWeather,
    required this.showCameras,
    required this.showThumbnails,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stations = context.select<WeatherProvider, List<WeatherStation>>(
      (p) => p.stations,
    );
    // Frames refresh in 5-minute steps so rebuilds reuse the cached image.
    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 300000 * 300000;
    return MarkerLayer(
      markers: [
        for (final station in stations)
          if (station.hasWeather ? showWeather : showCameras)
            _stationMarker(station, bucket),
      ],
    );
  }

  Marker _stationMarker(WeatherStation station, int bucket) {
    final thumb = showThumbnails && station.cameraLink.isNotEmpty
        ? station.cameraUrlWithBuster(bucket)
        : null;
    return Marker(
      point: station.position,
      width: thumb != null
          ? TemperatureMarker.thumbnailWidth
          : (station.hasWeather ? 60 : 34),
      height: 44 + (thumb != null ? TemperatureMarker.thumbnailHeight : 0),
      alignment: Alignment.topCenter,
      child: TemperatureMarker(
        station: station,
        thumbnailUrl: thumb,
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
            point: event.position,
            width: 28,
            height: 28,
            child: EventMarker(
              event: event,
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
