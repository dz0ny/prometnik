import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promet/models/weather_station.dart';
import 'package:promet/theme/app_theme.dart';
import 'package:promet/widgets/shimmer_box.dart';
import 'package:promet/widgets/station_overview.dart';

void main() {
  test('numberStyle uses the bundled font, its weight axis and tabular '
      'figures', () {
    final s = AppTheme.numberStyle(fontSize: 20, fontWeight: FontWeight.w800);
    expect(s.fontFamily, AppTheme.numberFontFamily);
    expect(s.fontWeight, FontWeight.w800);
    // The variable font defaults to wght 200: the axis must be set.
    expect(s.fontVariations, [const FontVariation('wght', 800)]);
    expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  test('temperatureTextColor stays readable on both themes', () {
    for (final t in [-15.0, -3.0, 2.0, 10.0, 18.0, 25.0, 30.0, 38.0]) {
      final dark = HSLColor.fromColor(
        AppTheme.temperatureTextColor(t, Brightness.dark),
      );
      final light = HSLColor.fromColor(
        AppTheme.temperatureTextColor(t, Brightness.light),
      );
      expect(dark.lightness, greaterThanOrEqualTo(0.6), reason: '$t dark');
      expect(light.lightness, lessThanOrEqualTo(0.39), reason: '$t light');
    }
  });

  testWidgets('ShimmerBox animates and disposes cleanly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: ShimmerBox(width: 120, height: 60)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(ShimmerBox), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading chips keep every value and label', (tester) async {
    final station = WeatherStation.fromJson({
      'stationId': 999101,
      'name': 'Test',
      'coordinateX': 46.0,
      'coordinateY': 14.5,
      'cameraLink': '',
      'weather': {
        'outdoorTemperatureC': 3.0,
        'pressureHpa': 1017,
        'humidityPercentage': 95,
        'windDirection': 'ENE',
        'windSpeedKmh': 4.0,
        'windGustKmh': 12.0,
        'dailyRainMm': 6,
        'dewPointC': -1.2,
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StationOverview(station: station, historyOverride: []),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (final label in [
      'Veter',
      'Sunki',
      'Vlažnost',
      'Padavine',
      'Rosišče',
      'Tlak',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('12 km/h'), findsOneWidget);
    expect(find.text('95 %'), findsOneWidget);
    expect(find.text('1017 hPa'), findsOneWidget);
    expect(find.text('-1,2 °C'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
