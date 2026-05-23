import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/weather_station.dart';

/// Fetches road weather + camera stations from the public ceste.si (DARS) API.
///
/// The web app at https://www.ceste.si/Vreme/ polls
/// `GET /Vremenske/Vreme/KamereInVreme` every 10 minutes; we use the same
/// endpoint. It returns a JSON array of stations, each with an optional
/// `weather` object and a `cameraLink`.
class WeatherService {
  static final WeatherService _instance = WeatherService._internal();
  factory WeatherService() => _instance;
  WeatherService._internal();

  static const String _endpoint =
      'https://www.ceste.si/Vremenske/Vreme/KamereInVreme';

  static const Duration _timeout = Duration(seconds: 20);

  Future<List<WeatherStation>> fetchStations() async {
    final uri = Uri.parse(_endpoint);
    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'promet-flutter/1.0 (+https://www.ceste.si/Vreme/)',
      },
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw WeatherServiceException(
        'Strežnik je vrnil napako ${response.statusCode}.',
      );
    }

    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        throw const WeatherServiceException('Nepričakovana oblika podatkov.');
      }
      final stations = <WeatherStation>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            stations.add(WeatherStation.fromJson(item));
          } catch (e) {
            debugPrint('WeatherService: preskočena postaja: $e');
          }
        }
      }
      stations.sort((a, b) => a.name.compareTo(b.name));
      return stations;
    } on FormatException catch (e) {
      throw WeatherServiceException('Podatkov ni bilo mogoče prebrati: $e');
    }
  }
}

class WeatherServiceException implements Exception {
  final String message;
  const WeatherServiceException(this.message);
  @override
  String toString() => message;
}
