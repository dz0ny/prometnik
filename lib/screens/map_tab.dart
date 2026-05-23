import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/traffic_event.dart';
import '../models/weather_station.dart';
import '../providers/events_provider.dart';
import '../providers/weather_provider.dart';
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
  bool _showWeather = true;
  bool _showCameras = true;
  final Set<EventSeverity> _eventFilter = {..._severities};

  bool _stationVisible(WeatherStation s) =>
      s.hasWeather ? _showWeather : _showCameras;

  int get _activeMapFilterCount =>
      (_showWeather ? 0 : 1) +
      (_showCameras ? 0 : 1) +
      (_severities.length - _eventFilter.length);

  void _openMapFilters() {
    var pendingWeather = _showWeather;
    var pendingCameras = _showCameras;
    final pendingEvents = {..._eventFilter};
    final events = context.read<EventsProvider>().events;
    int count(EventSeverity s) => events.where((e) => e.severity == s).length;

    showFilterSheet(
      context: context,
      title: 'Prikaz na karti',
      onReset: () {
        pendingWeather = true;
        pendingCameras = true;
        pendingEvents
          ..clear()
          ..addAll(_severities);
      },
      onApply: () => setState(() {
        _showWeather = pendingWeather;
        _showCameras = pendingCameras;
        _eventFilter
          ..clear()
          ..addAll(pendingEvents);
      }),
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
                      for (final event
                          in context.watch<EventsProvider>().events)
                        if (_eventFilter.contains(event.severity))
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
