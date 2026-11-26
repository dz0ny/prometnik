import 'package:flutter_test/flutter_test.dart';
import 'package:promet/models/weather_station.dart';

void main() {
  group('WeatherStation.fromJson', () {
    test('parses a station with a weather reading', () {
      final station = WeatherStation.fromJson({
        'stationId': 2,
        'name': 'Pijava Gorica',
        'coordinateX': 45.950867,
        'coordinateY': 14.571847,
        'cameraLink': 'https://kamere.dars.si/kamere/x.jpg',
        'weather': {
          'timestamp': '2026-05-22T14:10:29',
          'outdoorTemperatureC': 25.0,
          'pressureHpa': 1025,
          'humidityPercentage': 40,
          'windDirection': 'SE        ',
          'windSpeedKmh': 5.0,
        },
      });

      expect(station.stationId, 2);
      expect(station.name, 'Pijava Gorica');
      expect(station.temperatureC, 25.0);
      expect(station.hasWeather, isTrue);
      expect(station.position.latitude, closeTo(45.950867, 1e-6));
      expect(station.position.longitude, closeTo(14.571847, 1e-6));
      expect(station.weather!.windDirection, 'SE'); // trimmed
    });

    test('handles a camera-only station (null weather)', () {
      final station = WeatherStation.fromJson({
        'stationId': 99,
        'name': 'Panovec',
        'coordinateX': 45.9,
        'coordinateY': 13.6,
        'cameraLink': 'https://kamere.dars.si/kamere/y.jpg',
        'weather': null,
      });

      expect(station.hasWeather, isFalse);
      expect(station.temperatureC, isNull);
    });

    test('normalises malformed coordinates back into WGS84 range', () {
      final station = WeatherStation.fromJson({
        'stationId': 1,
        'name': 'Krško 2',
        'coordinateX': 45957236.0,
        'coordinateY': 154892240.0,
        'cameraLink': '',
        'weather': null,
      });

      expect(station.position.latitude, lessThanOrEqualTo(90));
      expect(station.position.longitude, lessThanOrEqualTo(180));
      expect(station.position.latitude, closeTo(45.957236, 1e-3));
      expect(station.position.longitude, closeTo(15.489224, 1e-3));
    });

    test('cache-busting URL appends a timestamp param for unknown hosts', () {
      final station = WeatherStation.fromJson({
        'stationId': 1,
        'name': 'X',
        'coordinateX': 46.0,
        'coordinateY': 14.0,
        'cameraLink': 'https://example.com/cam.jpg',
        'weather': null,
      });

      expect(
        station.cameraUrlWithBuster(123),
        'https://example.com/cam.jpg?t=123',
      );
    });

    test('camera URL on a known host goes through the edge cache', () {
      final station = WeatherStation.fromJson({
        'stationId': 1,
        'name': 'X',
        'coordinateX': 46.0,
        'coordinateY': 14.0,
        'cameraLink': 'https://kamere.dars.si/kamere/x.jpg',
        'weather': null,
      });

      final uri = Uri.parse(station.cameraUrlWithBuster(123));
      expect(uri.host, 'prometnik-cams.dz0ny.workers.dev');
      expect(uri.queryParameters['u'], 'https://kamere.dars.si/kamere/x.jpg');
      expect(uri.queryParameters['t'], '123');
    });
  });
}
