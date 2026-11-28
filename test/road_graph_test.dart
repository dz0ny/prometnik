import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:promet/routing/road_graph.dart';

Float64List line(List<List<double>> latLon) => Float64List.fromList([
  for (final p in latLon) ...[p[1], p[0]],
]);

void main() {
  test('takes the faster motorway over the shorter local road', () {
    // A square: A→B→C on a motorway, A→C directly on an unnumbered road.
    final g = RoadGraph.build(
      ['A1', 'A1', ''],
      [
        line([
          [46.0, 14.0],
          [46.0, 14.1],
        ]),
        line([
          [46.0, 14.1],
          [46.05, 14.1],
        ]),
        line([
          [46.0, 14.0],
          [46.05, 14.1],
        ]),
      ],
    );
    final r = g.routes([const LatLng(46.0, 14.0), const LatLng(46.05, 14.1)]);
    expect(r, isNotEmpty);
    expect(r.first.roadRefs, ['A1']);
    // The local road is offered as an alternative.
    expect(r.length, 2);
    expect(r[1].roadRefs, isEmpty);
  });

  test('unconnected points give no route', () {
    final g = RoadGraph.build(
      ['1', '2'],
      [
        line([
          [46.0, 14.0],
          [46.0, 14.01],
        ]),
        line([
          [46.5, 15.0],
          [46.5, 15.01],
        ]),
      ],
    );
    expect(
      g.routes([const LatLng(46.0, 14.0), const LatLng(46.5, 15.0)]),
      isEmpty,
    );
  });

  test('speedKmh by road number', () {
    expect(RoadGraph.speedKmh('A1'), 120);
    expect(RoadGraph.speedKmh('H4'), 95);
    expect(RoadGraph.speedKmh('409'), 60);
    expect(RoadGraph.speedKmh(''), 35);
  });

  test('Ljubljana → Koper on the bundled roads uses the A1', () {
    final raw =
        jsonDecode(File('assets/roads.json').readAsStringSync()) as List;
    final refs = <String>[];
    final coords = <Float64List>[];
    for (final item in raw) {
      final l = item as List;
      refs.add(l[0] as String);
      coords.add(
        Float64List.fromList([
          for (final v in l[2] as List) (v as num).toDouble(),
        ]),
      );
    }
    final sw = Stopwatch()..start();
    final g = RoadGraph.build(refs, coords);
    final built = sw.elapsedMilliseconds;
    sw.reset();
    final r = g.routes([
      const LatLng(46.0569, 14.5058), // Ljubljana centre
      const LatLng(45.5481, 13.7302), // Koper
    ]);
    // ignore: avoid_print
    print(
      'build ${built}ms, route ${sw.elapsedMilliseconds}ms, '
      '${(r.first.meters / 1000).toStringAsFixed(1)} km, '
      '${(r.first.seconds / 60).round()} min, ${r.length} routes, '
      'roads ${r.first.roadRefs.take(8).toList()}',
    );
    expect(r, isNotEmpty);
    expect(r.first.roadRefs, contains('A1'));
    expect(r.first.meters, inInclusiveRange(95000, 130000));
  });
}
