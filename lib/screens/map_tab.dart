import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/traffic_event.dart';
import '../models/weather_station.dart';
import '../providers/cameras_provider.dart';
import '../providers/events_provider.dart';
import '../providers/weather_provider.dart';
import '../services/prefs.dart';
import '../services/roads_service.dart';
import '../widgets/camera_sheet.dart';
import '../widgets/event_marker.dart';
import '../widgets/event_sheet.dart';
import '../widgets/event_visuals.dart';
import '../widgets/filter_sheet.dart';
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
  static const List<EventSource> _sources = [
    EventSource.drsi,
    EventSource.dars,
    EventSource.other,
  ];
  bool _showWeather = true;
  bool _showCameras = true;
  bool _showDarsCameras = true;
  final Set<EventSeverity> _eventFilter = {..._severities};
  final Set<EventSource> _sourceFilter = {..._sources};

  // Affected-area road highlights for the visible events.
  List<Polyline> _eventRoads = const [];
  String _roadsSig = '';

  @override
  void initState() {
    super.initState();
    _showWeather = Prefs.getBool('map.showWeather', true);
    _showCameras = Prefs.getBool('map.showCameras', true);
    _showDarsCameras = Prefs.getBool('map.darsCameras', true);
    if (Prefs.has('map.severities')) {
      final saved = Prefs.getStringList('map.severities', const []);
      _eventFilter
        ..clear()
        ..addAll(saved.map(_severityByName).whereType<EventSeverity>());
    }
    if (Prefs.has('map.sources')) {
      final saved = Prefs.getStringList('map.sources', const []);
      _sourceFilter
        ..clear()
        ..addAll(saved.map(_sourceByName).whereType<EventSource>());
    }
  }

  void _saveMapFilters() {
    Prefs.setBool('map.showWeather', _showWeather);
    Prefs.setBool('map.showCameras', _showCameras);
    Prefs.setBool('map.darsCameras', _showDarsCameras);
    Prefs.setStringList(
      'map.severities',
      _eventFilter.map((s) => s.name).toList(),
    );
    Prefs.setStringList(
      'map.sources',
      _sourceFilter.map((s) => s.name).toList(),
    );
  }

  static EventSeverity? _severityByName(String n) {
    for (final s in _severities) {
      if (s.name == n) return s;
    }
    return null;
  }

  static EventSource? _sourceByName(String n) {
    for (final s in _sources) {
      if (s.name == n) return s;
    }
    return null;
  }

  /// Recompute the highlighted roads inside each visible event's affected area
  /// when the visible event set changes.
  Future<void> _refreshEventRoads(List<TrafficEvent> events) async {
    final lines = <Polyline>[];
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
            ),
          );
        }
      }
    }
    if (mounted) setState(() => _eventRoads = lines);
  }

  bool _stationVisible(WeatherStation s) =>
      s.hasWeather ? _showWeather : _showCameras;

  int get _activeMapFilterCount =>
      (_showWeather ? 0 : 1) +
      (_showCameras ? 0 : 1) +
      (_showDarsCameras ? 0 : 1) +
      (_severities.length - _eventFilter.length) +
      (_sources.length - _sourceFilter.length);

  void _openMapFilters() {
    var pendingWeather = _showWeather;
    var pendingCameras = _showCameras;
    var pendingDarsCameras = _showDarsCameras;
    final pendingEvents = {..._eventFilter};
    final pendingSources = {..._sourceFilter};
    final events = context.read<EventsProvider>().events;
    int count(EventSeverity s) => events.where((e) => e.severity == s).length;
    int srcCount(EventSource s) => events.where((e) => e.source == s).length;

    showFilterSheet(
      context: context,
      title: 'Prikaz na karti',
      onReset: () {
        pendingWeather = true;
        pendingCameras = true;
        pendingDarsCameras = true;
        pendingEvents
          ..clear()
          ..addAll(_severities);
        pendingSources
          ..clear()
          ..addAll(_sources);
      },
      onApply: () {
        setState(() {
          _showWeather = pendingWeather;
          _showCameras = pendingCameras;
          _showDarsCameras = pendingDarsCameras;
          _eventFilter
            ..clear()
            ..addAll(pendingEvents);
          _sourceFilter
            ..clear()
            ..addAll(pendingSources);
        });
        _saveMapFilters();
      },
      contentBuilder: (setSheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FilterSectionLabel('Postaje'),
          _switchRow(
            Icons.thermostat,
            'Vremenske postaje',
            pendingWeather,
            (v) => setSheet(() => pendingWeather = v),
          ),
          _switchRow(
            Icons.videocam,
            'Kamere',
            pendingCameras,
            (v) => setSheet(() => pendingCameras = v),
          ),
          _switchRow(
            Icons.photo_camera,
            'DARS kamere',
            pendingDarsCameras,
            (v) => setSheet(() => pendingDarsCameras = v),
          ),
          const FilterSectionLabel('Dogodki'),
          for (final s in _severities)
            _switchRow(
              EventVisuals.icon(s),
              '${EventVisuals.label(s)} (${count(s)})',
              pendingEvents.contains(s),
              (v) => setSheet(() {
                if (v) {
                  pendingEvents.add(s);
                } else {
                  pendingEvents.remove(s);
                }
              }),
              iconColor: EventVisuals.color(s),
            ),
          const FilterSectionLabel('Vir'),
          for (final s in _sources)
            _switchRow(
              EventVisuals.sourceIcon(s),
              '${EventVisuals.sourceLabel(s)} (${srcCount(s)})',
              pendingSources.contains(s),
              (v) => setSheet(() {
                if (v) {
                  pendingSources.add(s);
                } else {
                  pendingSources.remove(s);
                }
              }),
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
          AdaptiveSwitch(value: value, onChanged: onChanged),
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
              .where(
                (e) =>
                    _eventFilter.contains(e.severity) &&
                    _sourceFilter.contains(e.source),
              )
              .toList();
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
                    subdomains: isDark
                        ? const ['a', 'b', 'c', 'd']
                        : const [],
                    retinaMode: isDark && RetinaMode.isHighDensity(context),
                    userAgentPackageName: 'dev.dz0ny.promet',
                    maxZoom: 19,
                  ),
                  // Affected-area roads for the visible events (under markers).
                  if (_eventRoads.isNotEmpty)
                    PolylineLayer(polylines: _eventRoads),
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
