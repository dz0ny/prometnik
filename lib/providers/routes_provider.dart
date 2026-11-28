import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The DARS travel-time corridors routed on the graph.
final corridorsProvider = FutureProvider<List<Corridor>>((ref) async {
  final graph = await ref.watch(roadGraphProvider.future);
  return buildCorridors(graph);
});

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
        _index(r),
        events: events,
        roadStations: stations,
        wind: wind,
        travelTimes: times,
        corridors: corridors,
        roadRefs: r.roadRefs.toSet(),
        now: now,
        fromName: r.places.first.name,
        toName: r.places.last.name,
      ),
  };
});

// Indexing is cheap but feeds refresh often: keep one index per geometry.
final Map<String, (String, RouteIndex)> _indexes = {};

RouteIndex _index(SavedRoute r) {
  final key = encodePolyline(r.points);
  final hit = _indexes[r.id];
  if (hit != null && hit.$1 == key) return hit.$2;
  final idx = RouteIndex(r.points);
  _indexes[r.id] = (key, idx);
  return idx;
}

/// A new route id.
String newRouteId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${UniqueKey().hashCode.toRadixString(36)}';
