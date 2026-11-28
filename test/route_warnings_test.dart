import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:promet/models/burja_station.dart';
import 'package:promet/models/drsi_station.dart';
import 'package:promet/models/traffic_event.dart';
import 'package:promet/models/travel_time.dart';
import 'package:promet/routing/corridors.dart';
import 'package:promet/routing/road_graph.dart';
import 'package:promet/routing/route_warnings.dart';
import 'package:promet/routing/saved_route.dart';

RoadGraph loadGraph() {
  final raw = jsonDecode(File('assets/roads.json').readAsStringSync()) as List;
  return RoadGraph.build(
    [for (final l in raw) (l as List)[0] as String],
    [
      for (final l in raw)
        Float64List.fromList([
          for (final v in (l as List)[2] as List) (v as num).toDouble(),
        ]),
    ],
  );
}

TrafficEvent event(
  String id,
  LatLng at, {
  bool closed = false,
  bool jam = false,
  String road = '',
}) => TrafficEvent(
  id: id,
  position: at,
  title: 'Dogodek',
  description: 'opis',
  road: road,
  category: '',
  cause: closed ? 'Zapora' : 'Zastoj',
  iconName: '',
  sideContent: '',
  isRoadClosed: closed,
  isJam: jam,
  isRoadworks: false,
  isBorderCrossing: false,
  queueLength: 0,
  delaySeconds: 0,
  priority: 0,
  validFrom: null,
  validTo: null,
  updated: null,
  estimatedEnd: null,
  noticeText: '',
  infoUrl: '',
  areaSouthWest: null,
  areaNorthEast: null,
);

DrsiStation station(String id, LatLng at, String state, double roadTemp) =>
    DrsiStation(
      id: id,
      name: 'Postaja $id',
      position: at,
      measuredAt: null,
      airTemp: null,
      roadTemp: roadTemp,
      dewPoint: null,
      freezePoint: null,
      humidity: null,
      windKmh: null,
      gustKmh: null,
      waterFilmMm: null,
      salinity: null,
      salinityUnit: '',
      roadStateId: null,
      roadState: state,
      precipitation: '',
      alarms: const [],
      webcamUrl: '',
      outage: false,
    );

TravelTime tt(String route, int delayMin) => TravelTime(
  id: route,
  route: route,
  actualMs: 3600000,
  actualText: '60 min',
  delayMs: delayMin * 60000,
  delayText: '$delayMin min',
  isClosed: false,
  status: delayMin > 10 ? TravelStatus.congested : TravelStatus.slow,
);

void main() {
  late RoadGraph graph;
  late List<Corridor> corridors;
  setUpAll(() {
    graph = loadGraph();
    corridors = buildCorridors(graph);
  });

  test('corridors are routed', () {
    for (final c in corridors) {
      expect(c.points.length, greaterThan(10), reason: c.forward);
    }
  });

  test('Vrhnika → Ljubljana: events, ice, burja and the KP - LJ delay', () {
    final r = graph.routes([
      const LatLng(45.9640, 14.2960), // Vrhnika
      const LatLng(46.0569, 14.5058), // Ljubljana
    ]).first;
    final idx = RouteIndex(r.points);
    final mid = r.points[r.points.length ~/ 2];
    final w = routeWarnings(
      idx,
      events: [
        event('on', mid, jam: true),
        event('far', const LatLng(46.5, 15.6), closed: true),
      ],
      roadStations: [
        station('ice', r.points[r.points.length ~/ 3], 'Poledica', -2),
        station('dry', r.points[r.points.length ~/ 4], 'Suho', 5),
      ],
      wind: [
        BurjaStation(
          id: 'b',
          title: 'Razdrto',
          description: '',
          position: const LatLng(45.75, 14.07),
          wind: 60,
          gust: 90,
        ),
      ],
      travelTimes: [tt('KP - LJ', 12), tt('LJ - KP', 30)],
      corridors: corridors,
      roadRefs: r.roadRefs.toSet(),
      now: DateTime(2026, 11, 28, 8),
    );
    final ids = w.map((x) => x.id).toList();
    expect(ids, contains('ev:on'));
    expect(ids, isNot(contains('ev:far')));
    expect(ids, contains('rw:ice:ice'));
    expect(ids.where((i) => i.startsWith('rw:dry')), isEmpty);
    // Razdrto is ~30 km away from this route.
    expect(ids.where((i) => i.startsWith('wd:')), isEmpty);
    // Driving towards Ljubljana: the KP - LJ direction, not LJ - KP.
    expect(ids.where((i) => i.startsWith('tt:KP - LJ')), hasLength(1));
    expect(ids.where((i) => i.startsWith('tt:LJ - KP')), isEmpty);
    // Most serious first: the ice.
    expect(w.first.id, 'rw:ice:ice');
  });

  test('polyline encoding round-trips', () {
    final pts = [
      const LatLng(46.05691, 14.50583),
      const LatLng(45.54812, 13.73021),
      const LatLng(-1.5, -0.00001),
    ];
    final back = decodePolyline(encodePolyline(pts));
    for (var i = 0; i < pts.length; i++) {
      expect(back[i].latitude, closeTo(pts[i].latitude, 1e-5));
      expect(back[i].longitude, closeTo(pts[i].longitude, 1e-5));
    }
  });

  test('nextDeparture follows days and time', () {
    final r = SavedRoute(
      id: 'x',
      name: 'Služba',
      places: const [
        RoutePlace('a', LatLng(46, 14)),
        RoutePlace('b', LatLng(46, 15)),
      ],
      points: const [LatLng(46, 14), LatLng(46, 15)],
      roadRefs: const [],
      meters: 1,
      seconds: 1,
      days: const {1, 2, 3, 4, 5},
      departureMinutes: 7 * 60 + 30,
    );
    // Saturday 28 Nov 2026 → Monday 30 Nov 07:30.
    expect(
      r.nextDeparture(DateTime(2026, 11, 28, 9)),
      DateTime(2026, 11, 30, 7, 30),
    );
    // Monday before 07:30 → the same day.
    expect(
      r.nextDeparture(DateTime(2026, 11, 30, 7)),
      DateTime(2026, 11, 30, 7, 30),
    );
    final back = SavedRoute.decodeList(SavedRoute.encodeList([r])).single;
    expect(back.days, r.days);
    expect(back.departureMinutes, 450);
    expect(back.places.last.name, 'b');
  });

  test('isOppositeDirection from "v smeri" and the route ends', () {
    const lj = 'Ljubljana', kp = 'Koper / Capodistria';
    expect(
      isOppositeDirection(
        'uvoz Kastelec v smeri Ljubljane, veter',
        from: lj,
        to: kp,
      ),
      isTrue,
    );
    expect(
      isOppositeDirection(
        'uvoz Postojna v smeri Kopra, dela',
        from: lj,
        to: kp,
      ),
      isFalse,
    );
    expect(isOppositeDirection('dela na cesti', from: lj, to: kp), isFalse);
    expect(isOppositeDirection('v smeri Maribora', from: lj, to: kp), isFalse);
  });
}
