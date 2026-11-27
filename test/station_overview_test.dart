import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promet/models/weather_station.dart';
import 'package:promet/services/weather_history_service.dart';
import 'package:promet/widgets/station_overview.dart';

void main() {
  test('parseWeatherHistory reads points oldest first and tolerates junk', () {
    final points = parseWeatherHistory(
      '{"station":2,"points":['
      '{"at":"2026-11-26T21:00:00Z","t":1.5,"h":90,"w":3,"g":null,"r":6,"d":"ESE"},'
      '{"at":"2026-11-26T20:00:00Z","t":2},'
      '{"at":"nope","t":9}, 7]}',
    );
    expect(points.map((p) => p.tempC), [2.0, 1.5]);
    expect(points.last.humidity, 90);
    expect(points.last.gustKmh, isNull);
    expect(points.last.windDir, 'ESE');
    expect(points.first.windDir, isNull);
    expect(points.first.at.isUtc, isFalse);
    expect(parseWeatherHistory('not json'), isEmpty);
    expect(parseWeatherHistory('{"points":3}'), isEmpty);
  });

  testWidgets('overview renders without overflow, also at large text', (
    tester,
  ) async {
    final station = WeatherStation.fromJson({
      'stationId': 999001,
      'name': 'Test',
      'coordinateX': 46.0,
      'coordinateY': 14.5,
      'cameraLink': '',
      'weather': {
        'timestamp': '2026-11-26T22:00:00',
        'outdoorTemperatureC': -0.4,
        'pressureHpa': 1017,
        'humidityPercentage': 95,
        'windDirection': 'ENE',
        'windSpeedKmh': 4.0,
        'windGustKmh': 12.0,
        'dailyRainMm': 6,
        'dewPointC': -1.2,
        'minOutdoorTemperatureC': -0.6,
        'maxOutdoorTemperatureC': 4.0,
      },
    });
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StationOverview(station: station),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Zrak'), findsOneWidget);
      expect(find.text('Temperatura danes'), findsOneWidget);
      expect(find.text('Veter'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tapping the chart selects an hour and shows its value', (
    tester,
  ) async {
    final station = WeatherStation.fromJson({
      'stationId': 999002,
      'name': 'Test',
      'coordinateX': 46.0,
      'coordinateY': 14.5,
      'cameraLink': '',
      'weather': {
        'outdoorTemperatureC': 2.0,
        'minOutdoorTemperatureC': -1.0,
        'maxOutdoorTemperatureC': 4.0,
      },
    });
    final now = DateTime.now();
    DateTime h(int back) => DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).subtract(Duration(hours: back));
    final history = [
      WeatherPoint(at: h(3), tempC: -1.0, humidity: 90, windKmh: 5),
      WeatherPoint(at: h(2), tempC: 0.5),
      WeatherPoint(at: h(1), tempC: 1.5),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StationOverview(station: station, historyOverride: history),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('zdaj'), findsOneWidget);
    // Tap the far left of the chart: the oldest hour.
    final chart = find.byKey(const ValueKey('temp-chart'));
    final topLeft = tester.getTopLeft(chart);
    await tester.tapAt(topLeft + const Offset(32, 40));
    await tester.pump();
    final hh = '${h(3).hour.toString().padLeft(2, '0')}:00';
    expect(find.textContaining(hh), findsOneWidget);
    expect(find.textContaining('-1,0 °C'), findsOneWidget);
    expect(find.textContaining('90 %'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wind and rain charts read gusts and hourly rain', (
    tester,
  ) async {
    final station = WeatherStation.fromJson({
      'stationId': 999003,
      'name': 'Test',
      'coordinateX': 46.0,
      'coordinateY': 14.5,
      'cameraLink': '',
      'weather': {
        'outdoorTemperatureC': 2.0,
        'windSpeedKmh': 8.0,
        'windGustKmh': 30.0,
        'windDirection': 'NE        ',
        'dailyRainMm': 4.0,
      },
    });
    final now = DateTime.now();
    DateTime h(int back) => DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).subtract(Duration(hours: back));
    final history = [
      WeatherPoint(at: h(3), tempC: 1, windKmh: 5, gustKmh: 12, rainMm: 1),
      WeatherPoint(at: h(2), tempC: 1, windKmh: 6, gustKmh: 20, rainMm: 1.5),
      WeatherPoint(
        at: h(1),
        tempC: 2,
        windKmh: 9,
        gustKmh: 25,
        rainMm: 3.5,
        windDir: 'SW',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StationOverview(
                station: station,
                historyOverride: history,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('metric-wind')));
    await tester.pump();
    expect(find.text('Veter · 24 ur'), findsOneWidget);
    expect(
      find.textContaining('iz severovzhoda · sunki 30 km/h'),
      findsOneWidget,
    );

    // Fullscreen keeps the series and fills the screen.
    await tester.tap(find.byKey(const ValueKey('chart-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.text('Veter · 24 ur'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('wind-chart'))).height,
      greaterThan(300),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Zapri'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('metric-rain')));
    await tester.pump();
    // 1 → 1,5 → 3,5 → 4 mm through the day: 3 mm fell in the window.
    expect(find.text('Padavine · 24 ur: 3,0 mm'), findsOneWidget);
    // Daily total 3,5 mm an hour ago and 4 mm now: 0,5 mm since.
    expect(find.textContaining('0,5 mm'), findsOneWidget);
    // The hour before that: 1,5 → 3,5 mm.
    final chart = find.byKey(const ValueKey('rain-chart'));
    final rect = tester.getRect(chart);
    final hourAgo = 30 + (rect.width - 30) * (2 / 3);
    await tester.tapAt(rect.topLeft + Offset(hourAgo, 40));
    await tester.pump();
    expect(find.textContaining('2,0 mm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('hourly trend compares with the reading about an hour ago', () {
    final at = DateTime(2026, 11, 27, 20, 10);
    final history = [
      WeatherPoint(at: DateTime(2026, 11, 27, 17), tempC: -5),
      WeatherPoint(at: DateTime(2026, 11, 27, 19), tempC: 1.0),
      WeatherPoint(at: DateTime(2026, 11, 27, 20), tempC: 9),
    ];
    expect(hourlyTrend(1.6, history, at), closeTo(0.6, 1e-9));
    expect(hourlyTrend(1.6, [history.first, history.last], at), isNull);
  });
}
