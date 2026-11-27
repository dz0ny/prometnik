import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:promet/models/drsi_station.dart';
import 'package:promet/models/weather_station.dart';
import 'package:promet/screens/map_tab.dart'
    show MapCluster, cameraCountLabel, clusterByScreenDistance;
import 'package:promet/services/drsi_service.dart';
import 'package:promet/widgets/base_tile_layer.dart';
import 'package:promet/widgets/drsi_sheet.dart';
import 'package:promet/widgets/temperature_marker.dart';

WeatherStation _station({double? temp, int id = 1}) => WeatherStation.fromJson({
  'stationId': id,
  'name': 'Dragomer',
  'coordinateX': 46.02,
  'coordinateY': 14.39,
  'cameraLink': '',
  'weather': temp == null
      ? null
      : {'timestamp': '2026-11-27T20:15:00', 'outdoorTemperatureC': temp},
});

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Center(child: SizedBox(width: 68, height: 120, child: child)),
    ),
  ),
);

void main() {
  group('BaseMap.resolveSaved', () {
    test('new users get the calm map', () {
      expect(
        BaseMap.resolveSaved(
          id: null,
          legacySeznam: null,
          seznamAvailable: true,
        ),
        BaseMap.calm,
      );
    });

    test('a stored legacy choice keeps working', () {
      expect(
        BaseMap.resolveSaved(
          id: null,
          legacySeznam: true,
          seznamAvailable: true,
        ),
        BaseMap.seznam,
      );
      expect(
        BaseMap.resolveSaved(
          id: null,
          legacySeznam: false,
          seznamAvailable: true,
        ),
        BaseMap.openStreetMap,
      );
    });

    test('the new key wins over the legacy one', () {
      expect(
        BaseMap.resolveSaved(
          id: BaseMap.calm.id,
          legacySeznam: true,
          seznamAvailable: true,
        ),
        BaseMap.calm,
      );
      expect(
        BaseMap.resolveSaved(
          id: BaseMap.openStreetMap.id,
          legacySeznam: null,
          seznamAvailable: true,
        ),
        BaseMap.openStreetMap,
      );
    });

    test('unknown ids and unavailable Seznam fall back to calm', () {
      expect(
        BaseMap.resolveSaved(id: 99, legacySeznam: null, seznamAvailable: true),
        BaseMap.calm,
      );
      expect(
        BaseMap.resolveSaved(
          id: BaseMap.seznam.id,
          legacySeznam: null,
          seznamAvailable: false,
        ),
        BaseMap.calm,
      );
    });

    test('ids are unique and calm uses CARTO with a dark style', () {
      expect(BaseMap.values.map((b) => b.id).toSet(), hasLength(3));
      expect(BaseMap.calm.urlTemplate, contains('cartocdn.com'));
      expect(BaseMap.calm.darkUrlTemplate, contains('dark_all'));
      expect(BaseMap.calm.subdomains, ['a', 'b', 'c', 'd']);
    });
  });

  group('clusterByScreenDistance', () {
    // Two cameras ~150 m apart in Ljubljana, one in Maribor.
    const a = LatLng(46.0569, 14.5058);
    const b = LatLng(46.0580, 14.5070);
    const far = LatLng(46.5547, 15.6459);

    List<MapCluster<LatLng>> run(int zoom) =>
        clusterByScreenDistance([a, b, far], (p) => p, zoom: zoom);

    test('merges nearby points at a low zoom', () {
      final clusters = run(8);
      expect(clusters, hasLength(2));
      expect(clusters.first.items, [a, b]);
      expect(clusters.last.items, [far]);
      expect(clusters.first.center.latitude, closeTo(46.05745, 1e-6));
    });

    test('splits them once they no longer overlap', () {
      expect(run(16), hasLength(3));
    });

    test('co-located points always merge', () {
      final clusters = clusterByScreenDistance([a, a, a], (p) => p, zoom: 18);
      expect(clusters.single.items, hasLength(3));
    });

    test('is deterministic', () {
      final x = run(10).map((c) => c.items.length).toList();
      final y = run(10).map((c) => c.items.length).toList();
      expect(x, y);
    });
  });

  test('camera count uses Slovenian dual and plural', () {
    expect(cameraCountLabel(1), '1 kamera');
    expect(cameraCountLabel(2), '2 kameri');
    expect(cameraCountLabel(3), '3 kamere');
    expect(cameraCountLabel(4), '4 kamere');
    expect(cameraCountLabel(5), '5 kamer');
    expect(cameraCountLabel(12), '12 kamer');
    expect(cameraCountLabel(102), '102 kameri');
  });

  group('pins', () {
    final roads = parseDrsiTable(
      File('test/fixtures/drsi_current.json').readAsStringSync(),
    );
    final icyRoad = roads.firstWhere((r) => r.risk == RoadRisk.ice);

    testWidgets('weather pin is a tinted pill with an air badge', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(TemperatureMarker(station: _station(temp: 1.2), onTap: () {})),
      );
      expect(find.text('1°'), findsOneWidget);
      expect(find.byIcon(Icons.thermostat), findsOneWidget);
      expect(find.bySemanticsLabel('Dragomer, 1 °C'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('combined pin carries the road ice risk on its badge', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          TemperatureMarker(
            station: _station(temp: -3),
            road: icyRoad,
            onTap: () {},
          ),
        ),
      );
      expect(find.text('-3°'), findsOneWidget);
      expect(find.text('0°'), findsOneWidget); // -0.4 road, never "-0°"
      expect(find.byIcon(Icons.ac_unit), findsOneWidget);
      final seg = TemperatureMarker.roadSegment(icyRoad);
      expect(seg.badgeColor, drsiRiskColor(RoadRisk.ice));
      expect(tester.takeException(), isNull);
    });

    testWidgets('camera-only station is a round camera badge', (tester) async {
      await tester.pumpWidget(
        _host(TemperatureMarker(station: _station(), onTap: () {})),
      );
      expect(find.byType(MapCameraBadge), findsOneWidget);
      expect(find.byType(MapPill), findsNothing);
    });

    testWidgets('pins render at 2x text scale without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              for (final pin in <Widget>[
                TemperatureMarker(
                  station: _station(temp: -12),
                  road: icyRoad,
                  onTap: () {},
                ),
                DrsiMarker(station: icyRoad, onTap: () {}),
                // As placed by the cameras layer: sized to content.
                const OverflowBox(
                  maxWidth: double.infinity,
                  child: MapClusterBadge(count: 128),
                ),
              ])
                SizedBox(width: 68, height: 37, child: pin),
            ],
          ),
          textScale: 2,
        ),
      );
      expect(find.text('128'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cluster badge keeps the pill height in a taller box', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: OverflowBox(
                minWidth: 0,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                child: MapClusterBadge(count: 7),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(MapClusterBadge)).height,
        MapPinStyle.pillHeight,
      );
    });

    testWidgets('station pin hugs the bottom of its marker box', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 68,
              height: 80,
              child: TemperatureMarker(
                station: _station(temp: 4),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(TemperatureMarker));
      final pill = tester.getRect(find.byType(MapPill));
      // The pill and its tail end at the box bottom (the coordinate).
      expect(pill.bottom, closeTo(box.bottom, 0.5));
    });

    testWidgets('tapping a pin calls onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(DrsiMarker(station: icyRoad, onTap: () => taps++)),
      );
      await tester.tap(find.byType(DrsiMarker));
      expect(taps, 1);
    });
  });

  group('MapPopIn', () {
    testWidgets('animates only the first mount of an id', (tester) async {
      final seen = <Object>{};
      Widget pin() => _host(
        MapPopIn(
          id: 'st:1',
          seen: seen,
          child: const SizedBox(width: 10, height: 10),
        ),
      );
      double opacity() => tester.widget<Opacity>(find.byType(Opacity)).opacity;
      await tester.pumpWidget(pin());
      expect(opacity(), 0);
      await tester.pumpAndSettle();
      expect(opacity(), 1);

      // Culled and re-mounted (e.g. panned away and back): no replay.
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pumpWidget(pin());
      expect(find.byType(Opacity), findsNothing);
    });
  });
}
