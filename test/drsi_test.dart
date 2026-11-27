import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promet/models/drsi_station.dart';
import 'package:promet/providers/drsi_provider.dart';
import 'package:promet/providers/feed.dart';
import 'package:promet/services/drsi_service.dart';
import 'package:promet/widgets/drsi_sheet.dart';
import 'package:promet/widgets/event_sheet.dart' show eventRoadLabel;
import 'package:promet/widgets/station_sheet.dart';
import 'package:promet/widgets/weather_details.dart' show WeatherFormat;

void main() {
  final fixture = File('test/fixtures/drsi_current.json').readAsStringSync();

  group('parseDrsiTable (real CVIS snapshot)', () {
    final stations = parseDrsiTable(fixture);

    test('keeps online stations with road data only', () {
      // Fixture: 2 road stations, 1 air-only, 2 offline.
      expect(stations.map((s) => s.id), ['1', '4']);
    });

    test('parses decimal commas, names and time', () {
      final kranj = stations.firstWhere((s) => s.id == '1');
      expect(kranj.name, 'Kranj - most');
      expect(kranj.roadTemp, closeTo(-0.4, 1e-9));
      expect(kranj.freezePoint, closeTo(-0.1, 1e-9));
      expect(kranj.roadState, 'led');
      expect(kranj.position.latitude, closeTo(46.2286, 1e-4));
      expect(kranj.measuredAt, isNotNull);
      expect(kranj.measuredAt!.isUtc, isFalse);
    });

    test('ice is the highest risk, dry road is ok', () {
      expect(stations.firstWhere((s) => s.id == '1').risk, RoadRisk.ice);
      expect(stations.firstWhere((s) => s.id == '4').risk, RoadRisk.ok);
    });
  });

  group('DrsiStation', () {
    const cols = {
      'id': 0,
      'title': 1,
      'tempCeste': 2,
      'tempZmrz': 3,
      'stanjeOpis': 4,
      'lat': 5,
      'lon': 6,
      'mesTime': 7,
      'olddata': 8,
    };
    DrsiStation row(List<Object?> v) => DrsiStation.fromRow({
      'c': [
        for (final x in v) x == null ? null : {'v': x},
      ],
    }, cols);

    test('wet unsalted road at freezing point is slippery', () {
      final s = row([
        '9', 'CVP - X', '-0,2', '-0,1', 'mokro', '46,1', '14,5', '', 0, //
      ]);
      expect(s.position.latitude, closeTo(46.1, 1e-9));
      expect(s.risk, RoadRisk.slippery);
    });

    test('salted wet road is not flagged slippery', () {
      final s = row([
        '9', 'CVP - X', '-0,2', '-3,0', 'mokro / soljeno', '46.1', '14.5', //
        '', 0,
      ]);
      expect(s.risk, isNot(RoadRisk.slippery));
    });

    test('missing coordinates are rejected', () {
      expect(
        () => row(['9', 'CVP - X', '1,0', '', 'suho', '', '', '', 0]),
        throwsFormatException,
      );
    });
  });

  test('parseDrsiTime', () {
    expect(parseDrsiTime('26.11.2026 20:56'), DateTime(2026, 11, 26, 20, 56));
    expect(parseDrsiTime(''), isNull);
  });

  test('cookieHeaderFrom keeps the last auth cookie', () {
    const header =
        'ASP.NET_SessionId=abc; path=/; HttpOnly; SameSite=Lax,'
        '.ASPXFORMSAUTH=; path=/; HttpOnly,'
        '.ASPXFORMSAUTH=TOKEN123; path=/; HttpOnly';
    expect(
      cookieHeaderFrom(header),
      'ASP.NET_SessionId=abc; .ASPXFORMSAUTH=TOKEN123',
    );
    expect(cookieHeaderFrom('ASP.NET_SessionId=abc; path=/'), isNull);
  });

  testWidgets('marker and sheet render without overflow', (tester) async {
    // Tall window so the whole (lazily built) sheet body is on screen.
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final station = parseDrsiTable(fixture).first;
    await tester.pumpWidget(
      _withStation(
        station,
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  SizedBox(
                    width: 56,
                    height: 26,
                    child: DrsiMarker(station: station, onTap: () {}),
                  ),
                  TextButton(
                    onPressed: () => showRoadStationSheet(context, station),
                    child: const Text('open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('0°'), findsOneWidget); // -0.4 must not show as -0°
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Kranj - most'), findsOneWidget);
    expect(find.textContaining('Poledica', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet fits at 2x text scale', (tester) async {
    // Tall window so the whole (lazily built) sheet body is on screen.
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final station = parseDrsiTable(fixture).first;
    await tester.pumpWidget(
      _withStation(
        station,
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoadStationSheet(context, station),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Kranj - most'), findsOneWidget);
    expect(find.text('Vlažnost'), findsOneWidget);
    expect(find.text('-0,4 °C'), findsWidgets); // decimal comma
    expect(tester.takeException(), isNull);
  });

  test('WeatherFormat uses Slovenian decimals and compass', () {
    expect(WeatherFormat.temp(-0.04), '0,0 °C');
    expect(WeatherFormat.temp(-1.25), '-1,3 °C');
    expect(WeatherFormat.windDirection('ENE'), 'VSV');
    expect(WeatherFormat.windDirection('S'), 'J');
    expect(WeatherFormat.windDirection('N'), 'S');
    expect(WeatherFormat.bearing('N'), 0);
    expect(WeatherFormat.windFrom('ESE       '), 'iz vzhoda-jugovzhoda');
    expect(WeatherFormat.windFrom('?'), '');
  });

  test('eventRoadLabel hides internal ids', () {
    expect(eventRoadLabel('LZ-212840'), isNull);
    expect(eventRoadLabel('A1-E57'), 'A1');
    expect(eventRoadLabel('R3-651'), 'R3-651');
    expect(eventRoadLabel('Celovška cesta'), 'Celovška cesta');
  });
}

/// The road-station sheet reads its station from [drsiProvider].
Widget _withStation(DrsiStation station, Widget child) => ProviderScope(
  overrides: [drsiProvider.overrideWith(() => _FixedDrsi(station))],
  child: child,
);

class _FixedDrsi extends DrsiFeed {
  _FixedDrsi(this.station);
  final DrsiStation station;

  @override
  FeedState<DrsiStation> build() => FeedState(items: [station]);
}
