import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/travel_time.dart';

/// Fetches travel times ("potovalni časi") from the public promet.si data
/// channel `GET https://www.promet.si/dc/agg.potovalnicasi.v2` (GeoJSON-style
/// FeatureCollection without geometry; no auth, ~60s cache).
class TravelTimesService {
  static final TravelTimesService _instance = TravelTimesService._internal();
  factory TravelTimesService() => _instance;
  TravelTimesService._internal();

  static const String _endpoint =
      'https://www.promet.si/dc/agg.potovalnicasi.v2';
  static const Duration _timeout = Duration(seconds: 20);

  Future<List<TravelTime>> fetchTravelTimes() async {
    final response = await http.get(
      Uri.parse(_endpoint),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'promet-flutter/1.0 (+https://www.promet.si/)',
      },
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw TravelTimesServiceException(
        'Strežnik je vrnil napako ${response.statusCode}.',
      );
    }

    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['features'] is! List) {
        throw const TravelTimesServiceException('Nepričakovana oblika podatkov.');
      }
      final items = <TravelTime>[];
      for (final feature in decoded['features'] as List) {
        if (feature is Map<String, dynamic>) {
          try {
            items.add(TravelTime.fromFeature(feature));
          } catch (e) {
            debugPrint('TravelTimesService: preskočena pot: $e');
          }
        }
      }
      return items;
    } on FormatException catch (e) {
      throw TravelTimesServiceException('Podatkov ni bilo mogoče prebrati: $e');
    }
  }
}

class TravelTimesServiceException implements Exception {
  final String message;
  const TravelTimesServiceException(this.message);
  @override
  String toString() => message;
}
