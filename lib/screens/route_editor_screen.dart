import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../providers/routes_provider.dart';
import '../routing/road_graph.dart';
import '../routing/saved_route.dart';
import '../services/notifications_service.dart';
import '../theme/app_theme.dart';
import '../widgets/base_tile_layer.dart';
import '../widgets/sheet_snack.dart';
import 'place_search_screen.dart';

/// Opens the editor for a new route, or for [route].
Future<void> showRouteEditor(BuildContext context, {SavedRoute? route}) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => RouteEditorScreen(route: route)),
    );

/// Create or change a saved route: start, stops and end by search, a choice
/// of alternatives on the map, a name and when it is driven.
class RouteEditorScreen extends ConsumerStatefulWidget {
  final SavedRoute? route;
  const RouteEditorScreen({super.key, this.route});

  @override
  ConsumerState<RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends ConsumerState<RouteEditorScreen> {
  final _map = MapController();
  late final TextEditingController _name;

  /// Start, stops and end; null = not picked yet.
  late List<RoutePlace?> _places;
  List<RoadRoute> _routes = const [];
  int _chosen = 0;
  bool _routing = false;
  String? _routeError;
  late Set<int> _days;
  int? _departure;

  static const _dayNames = ['Po', 'To', 'Sr', 'Če', 'Pe', 'So', 'Ne'];

  @override
  void initState() {
    super.initState();
    final r = widget.route;
    _name = TextEditingController(text: r?.name ?? '');
    _places = r == null ? [null, null] : [...r.places];
    _days = {...?r?.days};
    _departure = r?.departureMinutes;
    if (r != null) {
      // Show the saved route at once; alternatives are recomputed.
      _routes = [
        RoadRoute(
          points: r.points,
          edges: const [0],
          meters: r.meters,
          seconds: r.seconds,
          roadRefs: r.roadRefs,
        ),
      ];
      unawaited(_recompute(keep: r.points));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick(int i) async {
    final label = i == 0
        ? 'Od'
        : (i == _places.length - 1 ? 'Do' : 'Vmesna točka');
    final place = await Navigator.of(context).push<RoutePlace>(
      MaterialPageRoute(builder: (_) => PlaceSearchScreen(title: label)),
    );
    if (place == null || !mounted) return;
    setState(() {
      _places[i] = place;
      // The old line no longer goes through these places.
      _routes = const [];
    });
    await _recompute();
  }

  void _addStop() {
    setState(() => _places.insert(_places.length - 1, null));
    unawaited(_pick(_places.length - 2));
  }

  void _removeStop(int i) {
    setState(() {
      _places.removeAt(i);
      _routes = const [];
    });
    unawaited(_recompute());
  }

  /// Routes for the picked places; [keep] preselects the alternative that
  /// matches a saved geometry.
  Future<void> _recompute({List<LatLng>? keep}) async {
    final stops = _places.whereType<RoutePlace>().toList();
    if (stops.length != _places.length || stops.length < 2) return;
    setState(() {
      _routing = true;
      _routeError = null;
    });
    try {
      final graph = await ref.read(roadGraphProvider.future);
      final routes = await computeRoutes(graph, [
        for (final p in stops) p.position,
      ]);
      if (!mounted) return;
      var chosen = 0;
      if (keep != null && routes.isNotEmpty) {
        final saved = RoadRoute(
          points: keep,
          edges: const [0],
          meters: 0,
          seconds: 0,
          roadRefs: const [],
        );
        var best = -1.0;
        for (var i = 0; i < routes.length; i++) {
          final o = saved.overlap(routes[i]);
          if (o > best) {
            best = o;
            chosen = i;
          }
        }
      }
      setState(() {
        _routing = false;
        if (routes.isEmpty) {
          _routeError =
              'Poti ni bilo mogoče najti. Začetek in cilj sta lahko '
              'preblizu ali predaleč od ceste.';
        } else if (keep == null || _routes.length <= 1) {
          _routes = routes;
          _chosen = chosen;
        }
      });
      if (routes.isNotEmpty) _fit();
    } on Object {
      if (!mounted) return;
      setState(() {
        _routing = false;
        _routeError = 'Ceste se niso naložile.';
      });
    }
  }

  void _fit() {
    final pts = [for (final r in _routes) ...r.points];
    if (pts.length < 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: EdgeInsets.fromLTRB(
            32,
            MediaQuery.paddingOf(context).top + 64,
            32,
            24,
          ),
        ),
      );
    });
  }

  Future<void> _pickTime() async {
    final m = _departure ?? 7 * 60 + 30;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      helpText: 'Čas odhoda',
    );
    if (t == null || !mounted) return;
    setState(() => _departure = t.hour * 60 + t.minute);
  }

  void _save() {
    if (_routing) return;
    final route = _routes.isEmpty || _routeError != null
        ? null
        : _routes[_chosen];
    final places = _places.whereType<RoutePlace>().toList();
    if (route == null || places.length != _places.length) {
      showSheetSnack(context, message: 'Najprej izberite začetek in cilj.');
      return;
    }
    final name = _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : '${places.first.name} – ${places.last.name}';
    ref
        .read(savedRoutesProvider.notifier)
        .save(
          SavedRoute(
            id: widget.route?.id ?? newRouteId(),
            name: name,
            places: places,
            points: route.points,
            roadRefs: route.roadRefs,
            meters: route.meters,
            seconds: route.seconds,
            days: _departure == null ? const {} : _days,
            departureMinutes: _days.isEmpty ? null : _departure,
          ),
        );
    // Warnings before departure come as notifications.
    if (_days.isNotEmpty && _departure != null) {
      unawaited(
        NotificationsService.instance.requestPermission().catchError((
          Object e,
        ) {
          debugPrint('notification permission failed: $e');
          return false;
        }),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: widget.route == null ? 'Nova pot' : 'Uredi pot',
        actions: [
          AdaptiveAppBarAction(
            icon: Icons.check,
            iosSymbol: 'checkmark',
            label: 'Shrani',
            onPressed: _save,
          ),
        ],
      ),
      body: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.36,
              child: _RouteMap(
                controller: _map,
                routes: _routes,
                chosen: _chosen,
                places: _places,
                isDark: isDark,
              ),
            ),
            if (_routing) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  24 + AppTheme.bottomBarContentInset(context),
                ),
                children: [
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Ime poti',
                      hintText: 'npr. Služba',
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _places.length; i++)
                    _PlaceTile(
                      label: i == 0
                          ? 'Od'
                          : (i == _places.length - 1 ? 'Do' : 'Prek'),
                      place: _places[i],
                      onTap: () => unawaited(_pick(i)),
                      onRemove: i == 0 || i == _places.length - 1
                          ? null
                          : () => _removeStop(i),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _places.length >= 6 ? null : _addStop,
                      icon: const Icon(Icons.add),
                      label: const Text('Dodaj vmesno točko'),
                    ),
                  ),
                  if (_routeError != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _routeError!,
                        style: TextStyle(color: cs.error),
                      ),
                    ),
                  if (_routes.length > 1 ||
                      (_routes.isNotEmpty && widget.route == null))
                    ..._alternatives(cs),
                  const SizedBox(height: 16),
                  _sectionTitle(context, 'Kdaj potujete'),
                  const SizedBox(height: 4),
                  Text(
                    'Opozorila pred odhodom pridejo na izbrane dni.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(_dayNames[d - 1]),
                          selected: _days.contains(d),
                          onSelected: (on) => setState(() {
                            on ? _days.add(d) : _days.remove(d);
                            _departure ??= 7 * 60 + 30;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: const Text('Čas odhoda'),
                    trailing: Text(
                      _departure == null
                          ? 'ni nastavljen'
                          : '${(_departure! ~/ 60).toString().padLeft(2, '0')}:${(_departure! % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => unawaited(_pickTime()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String t) => Text(
    t,
    style: Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w800),
  );

  List<Widget> _alternatives(ColorScheme cs) => [
    const SizedBox(height: 8),
    _sectionTitle(context, _routes.length > 1 ? 'Izberite pot' : 'Pot'),
    const SizedBox(height: 6),
    for (var i = 0; i < _routes.length; i++)
      _AlternativeTile(
        route: _routes[i],
        index: i,
        selected: i == _chosen,
        onTap: () => setState(() => _chosen = i),
      ),
  ];
}

class _PlaceTile extends StatelessWidget {
  final String label;
  final RoutePlace? place;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _PlaceTile({
    required this.label,
    required this.place,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = place;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 44,
        child: Text(
          label,
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(
        p?.name ?? 'Izberite kraj',
        style: TextStyle(
          color: p == null ? cs.onSurfaceVariant : cs.onSurface,
          fontWeight: p == null ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
      trailing: onRemove == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: 'Odstrani',
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
      onTap: onTap,
    );
  }
}

/// Colours of the alternatives on the map and in the list.
Color _altColor(ColorScheme cs, int i) =>
    [cs.primary, const Color(0xFFFF8F00), const Color(0xFF8E24AA)][i % 3];

class _AlternativeTile extends StatelessWidget {
  final RoadRoute route;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  const _AlternativeTile({
    required this.route,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final km = (route.meters / 1000).toStringAsFixed(0);
    final min = (route.seconds / 60).round();
    final time = min >= 60 ? '${min ~/ 60} h ${min % 60} min' : '$min min';
    final roads = route.roadRefs
        .map((r) => r.split(';').first)
        .toSet()
        .take(6)
        .join(', ');
    return Card(
      elevation: 0,
      color: selected
          ? _altColor(cs, index).withValues(alpha: .14)
          : cs.surfaceContainerHighest.withValues(alpha: .5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? _altColor(cs, index) : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        selectedColor: cs.onSurface,
        leading: Icon(Icons.alt_route, color: _altColor(cs, index)),
        title: Text('$km km · $time'),
        subtitle: roads.isEmpty ? null : Text('Ceste: $roads'),
        trailing: selected ? Icon(Icons.check_circle, color: cs.primary) : null,
      ),
    );
  }
}

class _RouteMap extends StatelessWidget {
  final MapController controller;
  final List<RoadRoute> routes;
  final int chosen;
  final List<RoutePlace?> places;
  final bool isDark;

  const _RouteMap({
    required this.controller,
    required this.routes,
    required this.chosen,
    required this.places,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final order = [
      for (var i = 0; i < routes.length; i++)
        if (i != chosen) i,
      if (chosen < routes.length) chosen,
    ];
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: const LatLng(46.12, 14.82),
        initialZoom: 7.3,
        minZoom: 6,
        maxZoom: 17,
        backgroundColor: cs.surface,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        buildBaseTileLayer(context, base: BaseMap.saved, isDark: isDark),
        PolylineLayer(
          polylines: [
            for (final i in order)
              Polyline(
                points: routes[i].points,
                color: i == chosen
                    ? _altColor(cs, i)
                    : _altColor(cs, i).withValues(alpha: .55),
                strokeWidth: i == chosen ? 6 : 4,
                borderColor: Colors.white.withValues(alpha: .7),
                borderStrokeWidth: i == chosen ? 1.5 : 0,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (var i = 0; i < places.length; i++)
              if (places[i] != null)
                Marker(
                  point: places[i]!.position,
                  width: 26,
                  height: 26,
                  child: _PlaceDot(
                    label: i == 0 ? 'A' : (i == places.length - 1 ? 'B' : '$i'),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class _PlaceDot extends StatelessWidget {
  final String label;
  const _PlaceDot({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: cs.onPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
