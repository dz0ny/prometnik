import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promet/models/drsi_station.dart';
import 'package:promet/services/drsi_service.dart';
import 'package:promet/widgets/drsi_sheet.dart';

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
    final station = parseDrsiTable(fixture).first;
    await tester.pumpWidget(
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
                  onPressed: () => showDrsiSheet(context, station),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('0°'), findsOneWidget); // -0.4 must not show as -0°
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Kranj - most'), findsOneWidget);
    expect(find.text('Poledica'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
