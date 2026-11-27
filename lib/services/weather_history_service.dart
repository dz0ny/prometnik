import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/weather_station.dart';
import 'webcam_proxy.dart';

/// One hourly reading of a weather station.
class WeatherPoint {
  /// Local time of the reading (start of the hour for stored points).
  final DateTime at;
  final double? tempC;
  final double? humidity;
  final double? windKmh;
  final double? gustKmh;
  final double? rainMm;

  /// Compass code the wind blows from ("ESE"); null in older hours.
  final String? windDir;

  const WeatherPoint({
    required this.at,
    this.tempC,
    this.humidity,
    this.windKmh,
    this.gustKmh,
    this.rainMm,
    this.windDir,
  });
}

/// Last-24-hours readings per weather station, collected hourly by the
/// Prometnik worker (`GET /weather?id=<stationId>`); the feed itself only
/// carries the current reading.
class WeatherHistoryService {
  WeatherHistoryService._();
  static final WeatherHistoryService instance = WeatherHistoryService._();

  static const Duration _ttl = Duration(minutes: 10);
  static const Duration _timeout = Duration(seconds: 10);

  final http.Client _http = http.Client();
  final Map<int, ({DateTime at, List<WeatherPoint> points})> _cache = {};
  final Map<int, Future<List<WeatherPoint>>> _inFlight = {};

  /// Cached series for [stationId], if still fresh.
  List<WeatherPoint>? cached(int stationId) {
    final hit = _cache[stationId];
    if (hit == null || DateTime.now().difference(hit.at) > _ttl) return null;
    return hit.points;
  }

  /// The station's hourly series, oldest first; empty when unavailable.
  Future<List<WeatherPoint>> fetch(int stationId) {
    final hit = cached(stationId);
    if (hit != null) return Future.value(hit);
    return _inFlight[stationId] ??= _load(stationId).whenComplete(() {
      _inFlight.remove(stationId);
    });
  }

  Future<List<WeatherPoint>> _load(int stationId) async {
    try {
      final res = await _http
          .get(Uri.https(webcamProxyHost, '/weather', {'id': '$stationId'}))
          .timeout(_timeout);
      if (res.statusCode != 200) return const [];
      final points = parseWeatherHistory(utf8.decode(res.bodyBytes));
      _cache[stationId] = (at: DateTime.now(), points: points);
      return points;
    } on Exception catch (e) {
      debugPrint('WeatherHistoryService($stationId): $e');
      return const [];
    }
  }
}

/// The reading in [history] closest to [at], if one lies within [tolerance];
/// used to show the temperature of an hourly camera snapshot.
WeatherPoint? weatherPointAt(
  List<WeatherPoint> history,
  DateTime at, {
  Duration tolerance = const Duration(minutes: 45),
}) {
  WeatherPoint? best;
  Duration? bestGap;
  for (final p in history) {
    final gap = p.at.difference(at).abs();
    if (gap <= tolerance && (bestGap == null || gap < bestGap)) {
      best = p;
      bestGap = gap;
    }
  }
  return best;
}

/// What the station measured when a camera snapshot was taken: [live] when
/// [at] is null (the live frame), the stored hour nearest [at] otherwise, and
/// null when no reading lies near [at], never a value from another time.
/// Pressure, dew point and the day's range are not stored per hour.
WeatherReading? readingForSnapshot(
  WeatherReading? live,
  List<WeatherPoint> history,
  DateTime? at,
) {
  if (at == null || live == null) return live;
  final p = weatherPointAt(history, at);
  if (p == null) return null;
  return WeatherReading(
    timestamp: p.at,
    outdoorTemperatureC: p.tempC,
    humidityPercentage: p.humidity?.round(),
    windDirection: p.windDir,
    windSpeedKmh: p.windKmh,
    windGustKmh: p.gustKmh,
    dailyRainMm: p.rainMm,
  );
}

/// Parses the worker's `/weather` response; anything unexpected → empty.
@visibleForTesting
List<WeatherPoint> parseWeatherHistory(String body) {
  final Object? decoded;
  try {
    decoded = json.decode(body);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map || decoded['points'] is! List) return const [];
  double? n(Object? v) => v is num ? v.toDouble() : null;
  final out = <WeatherPoint>[];
  for (final p in decoded['points'] as List) {
    if (p is! Map) continue;
    final at = DateTime.tryParse('${p['at']}');
    if (at == null) continue;
    out.add(
      WeatherPoint(
        at: at.toLocal(),
        tempC: n(p['t']),
        humidity: n(p['h']),
        windKmh: n(p['w']),
        gustKmh: n(p['g']),
        rainMm: n(p['r']),
        windDir: p['d'] is String && (p['d'] as String).trim().isNotEmpty
            ? (p['d'] as String).trim()
            : null,
      ),
    );
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}
