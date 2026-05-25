import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/traffic_event.dart';
import '../models/travel_time.dart';
import '../providers/alerts_controller.dart';
import '../providers/events_provider.dart';
import '../providers/travel_times_provider.dart';
import '../services/map_tile_cache_service.dart';
import '../services/road_preview_simplifier.dart';
import '../services/roads_service.dart';
import '../widgets/event_marker.dart';
import '../widgets/event_sheet.dart';
import '../widgets/event_visuals.dart';
import '../theme/app_theme.dart';

/// Lists travel times ("potovalni časi") for the main routes, with the current
/// duration and any delay, from the promet.si data channel.
class TravelTimesTab extends StatelessWidget {
  const TravelTimesTab({super.key});

  static Color _statusColor(TravelStatus s) => switch (s) {
    TravelStatus.normal => const Color(0xFF66BB6A), // green
    TravelStatus.slow => const Color(0xFFFFB300), // amber
    TravelStatus.congested => const Color(0xFFFB8C00), // orange
    TravelStatus.closed => const Color(0xFFE53935), // red
  };

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      body: SafeArea(
        bottom: false,
        child: Consumer<TravelTimesProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading && !provider.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.error != null && !provider.hasData) {
              return _error(context, provider);
            }
            if (provider.items.isEmpty) {
              return _empty(context);
            }

            return RefreshIndicator(
              onRefresh: provider.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  top: 4,
                  bottom: 16 + AppTheme.bottomBarContentInset(context),
                ),
                children: [
                  AdaptiveFormSection.insetGrouped(
                    header: Text(
                      'POTOVALNI ČASI',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    children: [
                      for (var i = 0; i < provider.items.length; i++) ...[
                        _TravelRow(item: provider.items[i]),
                        if (!PlatformInfo.isIOS &&
                            i < provider.items.length - 1)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 28,
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.3),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Ni podatkov o potovalnih časih.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _error(BuildContext context, TravelTimesProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(provider.error ?? '', textAlign: TextAlign.center),
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

class _TravelRow extends StatelessWidget {
  final TravelTime item;

  const _TravelRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = TravelTimesTab._statusColor(item.status);
    final alerts = context.watch<AlertsController>();
    final events = context.watch<EventsProvider>().events;
    final watched = alerts.isTravelTimeWatched(item.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.route,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              if (item.isClosed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Zaprto',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.actualText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.hasDelay)
                      Text(
                        '+${item.delayText}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      )
                    else
                      Text(
                        'tekoče',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              const SizedBox(width: 4),
              AdaptiveButton.icon(
                icon: watched ? Icons.notifications_active : Icons.notifications_none,
                iconColor: watched ? cs.primary : cs.onSurfaceVariant,
                style: AdaptiveButtonStyle.plain,
                onPressed: () => alerts.toggleTravelTime(item.id),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TravelRouteMap(item: item, color: color, events: events),
        ],
      ),
    );
  }
}

class _TravelRouteSpec {
  final Set<String> refs;
  final LatLngBounds bounds;

  const _TravelRouteSpec(this.refs, this.bounds);
}

class _TravelRouteMap extends StatefulWidget {
  final TravelTime item;
  final Color color;
  final List<TrafficEvent> events;

  const _TravelRouteMap({
    required this.item,
    required this.color,
    required this.events,
  });

  @override
  State<_TravelRouteMap> createState() => _TravelRouteMapState();
}

class _TravelRouteMapState extends State<_TravelRouteMap>
    with AutomaticKeepAliveClientMixin {
  static final Map<String, _TravelRouteSpec> _specCache = {};

  late final _TravelRouteSpec _spec;
  List<RoadLine> _roads = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final key = widget.item.route.toLowerCase();
    _spec = _specCache.putIfAbsent(key, () => _routeSpec(widget.item.route));
    _loadRoads().then((roads) {
      if (mounted) setState(() => _roads = roads);
    });
  }

  Future<List<RoadLine>> _loadRoads() {
    return RoadPreviewSimplifier.roadsByRefsIn(
      _spec.refs,
      _spec.bounds.west,
      _spec.bounds.south,
      _spec.bounds.east,
      _spec.bounds.north,
    );
  }

  static _TravelRouteSpec _routeSpec(String route) {
    final normalized = route.toLowerCase();
    if (normalized.contains('obv')) {
      return _TravelRouteSpec(
        const {'A1', 'A2', 'H3'},
        LatLngBounds(
          const LatLng(45.985, 14.390),
          const LatLng(46.130, 14.650),
        ),
      );
    }
    if (normalized.contains('karavanke')) {
      return _TravelRouteSpec(
        const {'A2'},
        LatLngBounds(
          const LatLng(46.000, 14.030),
          const LatLng(46.510, 14.560),
        ),
      );
    }
    if (normalized.contains('mb')) {
      return _TravelRouteSpec(
        const {'A1'},
        LatLngBounds(
          const LatLng(46.000, 14.450),
          const LatLng(46.610, 15.720),
        ),
      );
    }
    if (normalized.contains('kp')) {
      return _TravelRouteSpec(
        const {'A1'},
        LatLngBounds(
          const LatLng(45.520, 13.710),
          const LatLng(46.090, 14.560),
        ),
      );
    }
    if (normalized.contains('obrežje')) {
      return _TravelRouteSpec(
        const {'A2'},
        LatLngBounds(
          const LatLng(45.760, 14.450),
          const LatLng(46.090, 15.730),
        ),
      );
    }
    return _TravelRouteSpec(
      const {'A1', 'A2', 'H3', 'H4', 'H5', 'H6'},
      LatLngBounds(
        const LatLng(45.400, 13.350),
        const LatLng(46.900, 16.650),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final events = _routeEvents(widget.events);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showEvents(context, events),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 112,
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: _spec.bounds.center,
                  initialZoom: 9,
                  initialCameraFit: CameraFit.bounds(
                    bounds: _spec.bounds,
                    padding: const EdgeInsets.all(18),
                    maxZoom: 11,
                  ),
                  backgroundColor: cs.surfaceContainerHighest,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
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
                  if (_roads.isNotEmpty)
                    PolylineLayer(
                      simplificationTolerance: 2,
                      polylines: [
                        for (final road in _roads)
                          Polyline(
                            points: road.points,
                            color: widget.color,
                            strokeWidth: 4,
                            borderColor: Colors.white.withValues(alpha: 0.75),
                            borderStrokeWidth: 1,
                          ),
                      ],
                    ),
                  if (events.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        for (final event in events)
                          Marker(
                            point: event.position,
                            width: 24,
                            height: 24,
                            child: EventMarker(
                              event: event,
                              onTap: () => _showEvents(context, events),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: cs.outline.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: events.isEmpty ? cs.onSurfaceVariant : widget.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${events.length}',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TrafficEvent> _routeEvents(List<TrafficEvent> events) {
    final routeEvents = [
      for (final event in events)
        if (event.isActive() &&
            _spec.refs.any((ref) => roadRefMatches(ref, event.roadDesignation)) &&
            _contains(_spec.bounds, event.position))
          event,
    ]..sort(_compareEvents);
    return routeEvents;
  }

  static bool _contains(LatLngBounds bounds, LatLng point) =>
      point.latitude >= bounds.south &&
      point.latitude <= bounds.north &&
      point.longitude >= bounds.west &&
      point.longitude <= bounds.east;

  static int _compareEvents(TrafficEvent a, TrafficEvent b) {
    final pa = _priority(a);
    final pb = _priority(b);
    if (pa != pb) return pa.compareTo(pb);
    return a.road.compareTo(b.road);
  }

  static int _priority(TrafficEvent event) => switch (event.severity) {
    EventSeverity.jam => 0,
    EventSeverity.closed => 1,
    EventSeverity.roadworks => 2,
    EventSeverity.other => 3,
  };

  void _showEvents(BuildContext context, List<TrafficEvent> events) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: events.isEmpty ? 0.32 : 0.72,
        minChildSize: 0.28,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.item.route,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: events.isEmpty
                      ? ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
                          children: [
                            Text(
                              'Ni aktivnih dogodkov na tej poti.',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                          itemCount: events.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: cs.outline.withValues(alpha: 0.25),
                          ),
                          itemBuilder: (context, index) {
                            final event = events[index];
                            final color = EventVisuals.color(event.severity);
                            return ListTile(
                              leading: Icon(
                                EventVisuals.causeIcon(event),
                                color: color,
                              ),
                              title: Text(
                                event.title.isEmpty ? event.cause : event.title,
                              ),
                              subtitle: Text(
                                [
                                  if (event.road.isNotEmpty) event.road,
                                  if (event.description.isNotEmpty)
                                    event.description,
                                ].join(' · '),
                              ),
                              onTap: () {
                                Navigator.of(sheetContext).pop();
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
      ),
    );
  }
}
