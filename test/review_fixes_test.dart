import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:promet/routing/road_graph.dart';
import 'package:promet/routing/route_warnings.dart';
import 'package:promet/routing/saved_route.dart';
import 'package:promet/widgets/my_routes_section.dart';

Float64List line(List<List<double>> latLon) => Float64List.fromList([
  for (final p in latLon) ...[p[1], p[0]],
]);

SavedRoute daily(int minutes) => SavedRoute(
  id: 'x',
  name: 'x',
  places: const [
    RoutePlace('a', LatLng(46, 14)),
    RoutePlace('b', LatLng(46, 15)),
  ],
  points: const [LatLng(46, 14), LatLng(46, 15)],
  roadRefs: const [],
  meters: 1,
  seconds: 1,
  days: const {1, 2, 3, 4, 5, 6, 7},
  departureMinutes: minutes,
);

void main() {
  test('nextDeparture keeps the clock time on DST days', () {
    // 29 Mar 2026 and 25 Oct 2026 change the clocks in Slovenia.
    expect(
      daily(450).nextDeparture(DateTime(2026, 3, 29, 1)),
      DateTime(2026, 3, 29, 7, 30),
    );
    expect(
      daily(450).nextDeparture(DateTime(2026, 10, 25, 1)),
      DateTime(2026, 10, 25, 7, 30),
    );
  });

  test('departureLabel says "jutri" across a DST change', () {
    expect(
      departureLabel(
        DateTime(2026, 3, 29, 7, 30),
        now: DateTime(2026, 3, 28, 22),
      ),
      'jutri 07:30',
    );
  });

  test('speedKmh of a shared section is the faster road', () {
    expect(RoadGraph.speedKmh('409;410'), 60);
    expect(RoadGraph.speedKmh('A1;409'), 120);
  });

  test('start and end on the same spot give no route', () {
    final g = RoadGraph.build(
      ['1'],
      [
        line([
          [46.0, 14.0],
          [46.0, 14.1],
        ]),
      ],
    );
    expect(
      g.routes([const LatLng(46.0, 14.0), const LatLng(46.0, 14.0)]),
      isEmpty,
    );
  });

  test('crossesBox catches a box between two far vertices', () {
    final idx = RouteIndex(const [LatLng(46.0, 14.0), LatLng(46.0, 14.2)]);
    expect(
      idx.crossesBox(
        const LatLng(45.999, 14.099),
        const LatLng(46.001, 14.101),
        margin: 0,
      ),
      isTrue,
    );
    expect(
      idx.crossesBox(
        const LatLng(46.05, 14.099),
        const LatLng(46.06, 14.101),
        margin: 0,
      ),
      isFalse,
    );
  });

  test('a ring route across the seam keeps its direction', () {
    // A square ring, clockwise from its first point (which is also last).
    const ring = [
      LatLng(46.00, 14.00),
      LatLng(46.10, 14.00),
      LatLng(46.10, 14.10),
      LatLng(46.00, 14.10),
      LatLng(46.00, 14.00),
    ];
    final c = Corridor('notranji', 'zunanji', ring);
    // Clockwise across the start: last side, then the first.
    final route = RouteIndex(const [
      LatLng(46.00, 14.08),
      LatLng(46.00, 14.00),
      LatLng(46.08, 14.00),
    ]);
    expect(corridorDirection(route, c), isTrue);
  });

  test('isOppositeDirection ignores street words in the place name', () {
    expect(
      isOppositeDirection(
        'v smeri Ljubljane',
        from: 'Ljubljanska cesta, Maribor',
        to: 'Ljubljana',
      ),
      isFalse,
    );
  });
}
