import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../routing/corridors.dart';
import '../routing/road_graph.dart';
import '../routing/route_warnings.dart';
import '../routing/saved_route.dart';
import '../services/prefs.dart';
import '../services/roads_service.dart';
import 'burja_provider.dart';
import 'drsi_provider.dart';
import 'events_provider.dart';
import 'travel_times_provider.dart';

/// The bundled roads as a routable graph (built once, off the main thread).
final roadGraphProvider = FutureProvider<RoadGraph>(
  (ref) => RoadsService.instance.graph(),
);

/// The DARS travel-time corridors routed on the graph (off the main
/// isolate: nine A* searches over the whole country).
final corridorsProvider = FutureProvider<List<Corridor>>((ref) async {
  final graph = await ref.watch(roadGraphProvider.future);
  return Isolate.run(() => buildCorridors(graph));
});

/// Routes through [stops] on the graph, computed off the main isolate.
Future<List<RoadRoute>> computeRoutes(RoadGraph graph, List<LatLng> stops) =>
    Isolate.run(() => graph.routes(stops));

/// Prefs key of the saved routes (also read by the background check).
const savedRoutesKey = 'routes.saved';

/// The user's saved routes, kept on the device only.
class SavedRoutesNotifier extends Notifier<List<SavedRoute>> {
  @override
  List<SavedRoute> build() =>
      SavedRoute.decodeList(Prefs.getString(savedRoutesKey));

  /// Adds [route], or replaces the saved route with the same id.
  void save(SavedRoute route) {
    final i = state.indexWhere((r) => r.id == route.id);
    state = i < 0
        ? [...state, route]
        : [...state.sublist(0, i), route, ...state.sublist(i + 1)];
    _persist();
  }

  void remove(String id) {
    state = [
      for (final r in state)
        if (r.id != id) r,
    ];
    _persist();
  }

  void _persist() =>
      Prefs.setString(savedRoutesKey, SavedRoute.encodeList(state));
}

final savedRoutesProvider =
    NotifierProvider<SavedRoutesNotifier, List<SavedRoute>>(
      SavedRoutesNotifier.new,
    );

/// Warnings per saved route id from the live feeds.
final routeWarningsProvider = Provider<Map<String, List<RouteWarning>>>((ref) {
  final routes = ref.watch(savedRoutesProvider);
  if (routes.isEmpty) return const {};
  final events = ref.watch(eventsProvider.select((s) => s.items));
  final stations = ref.watch(drsiProvider.select((s) => s.items));
  final wind = ref.watch(burjaProvider.select((s) => s.items));
  final times = ref.watch(travelTimesProvider.select((s) => s.items));
  final corridors = ref.watch(corridorsProvider).value ?? const <Corridor>[];
  final now = DateTime.now();
  return {
    for (final r in routes)
      r.id: routeWarnings(
        _geometry(r).index,
        events: events,
        roadStations: stations,
        wind: wind,
        travelTimes: times,
        corridors: corridors,
        roadRefs: r.roadRefs.toSet(),
        now: now,
        fromName: r.places.first.name,
        toName: r.places.last.name,
        directions: _geometry(r).directions(corridors),
      ),
  };
});

/// What depends only on a route's geometry, kept while its points live:
/// the spatial index and the corridor directions (the feeds refresh often).
class _RouteGeometry {
  final RouteIndex index;
  List<Corridor>? _for;
  Map<Corridor, bool?> _dirs = const {};
  _RouteGeometry(List<LatLng> points) : index = RouteIndex(points);

  Map<Corridor, bool?> directions(List<Corridor> corridors) {
    if (!identical(_for, corridors)) {
      _for = corridors;
      _dirs = {for (final c in corridors) c: corridorDirection(index, c)};
    }
    return _dirs;
  }
}

// Keyed by the points list itself: a SavedRoute is immutable, so a changed
// route has a new list and the old entry is collected with it.
final Expando<_RouteGeometry> _geometries = Expando('routeGeometry');

_RouteGeometry _geometry(SavedRoute r) =>
    _geometries[r.points] ??= _RouteGeometry(r.points);

/// A new route id.
String newRouteId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${UniqueKey().hashCode.toRadixString(36)}';
