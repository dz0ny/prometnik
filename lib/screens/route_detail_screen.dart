import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/routes_provider.dart';
import '../routing/route_warnings.dart';
import '../widgets/base_tile_layer.dart';
import '../widgets/my_routes_section.dart' show departureLabel, severityColor;
import 'route_editor_screen.dart';

Future<void> showRouteDetail(BuildContext context, String id) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => RouteDetailScreen(routeId: id)));

/// A saved route on the map with what is on it now.
class RouteDetailScreen extends ConsumerStatefulWidget {
  final String routeId;
  const RouteDetailScreen({super.key, required this.routeId});

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  final _map = MapController();

  Future<void> _delete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izbrišem pot?'),
        content: Text('Pot »$name« in njena opozorila bodo odstranjena.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Prekliči'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Izbriši'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ref.read(savedRoutesProvider.notifier).remove(widget.routeId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final route = ref
        .watch(savedRoutesProvider)
        .where((r) => r.id == widget.routeId)
        .firstOrNull;
    if (route == null) {
      return const AdaptiveScaffold(
        body: Center(child: Text('Pot ne obstaja.')),
      );
    }
    final warnings =
        ref.watch(routeWarningsProvider.select((m) => m[widget.routeId])) ??
        const <RouteWarning>[];
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final next = route.nextDeparture(DateTime.now());
    final min = (route.seconds / 60).round();

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: route.name,
        actions: [
          AdaptiveAppBarAction(
            icon: Icons.edit_outlined,
            iosSymbol: 'pencil',
            label: 'Uredi',
            onPressed: () => showRouteEditor(context, route: route),
          ),
          AdaptiveAppBarAction(
            icon: Icons.delete_outline,
            iosSymbol: 'trash',
            label: 'Izbriši',
            onPressed: () => _delete(route.name),
          ),
        ],
      ),
      body: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.42,
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(route.points),
                    padding: EdgeInsets.fromLTRB(
                      28,
                      MediaQuery.paddingOf(context).top + 64,
                      28,
                      28,
                    ),
                  ),
                  minZoom: 6,
                  maxZoom: 17,
                  backgroundColor: cs.surface,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  buildBaseTileLayer(
                    context,
                    base: BaseMap.saved,
                    isDark: isDark,
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: route.points,
                        color: cs.primary,
                        strokeWidth: 6,
                        borderColor: Colors.white.withValues(alpha: .7),
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final w in warnings)
                        if (w.position != null)
                          Marker(
                            point: w.position!,
                            width: 30,
                            height: 30,
                            child: _WarningDot(warning: w),
                          ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      [
                        '${route.places.first.name} → ${route.places.last.name}',
                        '${(route.meters / 1000).round()} km',
                        min >= 60
                            ? '${min ~/ 60} h ${min % 60} min'
                            : '$min min',
                        if (next != null) 'odhod ${departureLabel(next)}',
                      ].join(' · '),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (warnings.isEmpty)
                    _ClearCard(color: severityColor(cs, 0))
                  else
                    for (final w in warnings)
                      _WarningTile(
                        warning: w,
                        onTap: w.position == null
                            ? null
                            : () => _map.move(w.position!, 13),
                      ),
                  const SizedBox(height: 12),
                  Text(
                    'Pot je izračunana na glavnih cestah (OSM). Opozorila '
                    'vključujejo dogodke DARS, stanje cestišča DRSI, burjo in '
                    'potovalne čase na avtocestah.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _icon(RouteWarningKind k) => switch (k) {
  RouteWarningKind.closure => Icons.do_not_disturb_on,
  RouteWarningKind.jam => Icons.traffic,
  RouteWarningKind.roadworks => Icons.construction,
  RouteWarningKind.event => Icons.info_outline,
  RouteWarningKind.roadWeather => Icons.ac_unit,
  RouteWarningKind.wind => Icons.air,
  RouteWarningKind.delay => Icons.schedule,
};

class _WarningDot extends StatelessWidget {
  final RouteWarning warning;
  const _WarningDot({required this.warning});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: severityColor(cs, warning.severity),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(_icon(warning.kind), size: 16, color: Colors.white),
    );
  }
}

class _WarningTile extends StatelessWidget {
  final RouteWarning warning;
  final VoidCallback? onTap;
  const _WarningTile({required this.warning, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = severityColor(cs, warning.severity);
    return Card(
      elevation: 0,
      color: color.withValues(alpha: .1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: .4)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(_icon(warning.kind), color: color),
        title: Text(
          warning.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: warning.detail.isEmpty
            ? null
            : Text(
                warning.detail,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}

class _ClearCard extends StatelessWidget {
  final Color color;
  const _ClearCard({required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: .1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(Icons.check_circle, color: color),
        title: const Text('Na poti ni opozoril'),
        subtitle: const Text('Ni zastojev, zapor, poledice, burje ali zamud.'),
      ),
    );
  }
}
