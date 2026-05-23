import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/rest_area.dart';

/// Fetches motorway rest areas + live parking from promet.si
/// `GET https://www.promet.si/dc/agg.pocivalisca.v2`.
class RestAreasService {
  static final RestAreasService _instance = RestAreasService._internal();
  factory RestAreasService() => _instance;
  RestAreasService._internal();

  static const String _endpoint = 'https://www.promet.si/dc/agg.pocivalisca.v2';
  static const Duration _timeout = Duration(seconds: 20);

  Future<List<RestArea>> fetch() async {
    final response = await http.get(
      Uri.parse(_endpoint),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'promet-flutter/1.0 (+https://www.promet.si/)',
      },
    ).timeout(_timeout);
    if (response.statusCode != 200) {
      throw RestAreasServiceException(
        'Strežnik je vrnil napako ${response.statusCode}.',
      );
    }
    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['features'] is! List) {
        throw const RestAreasServiceException('Nepričakovana oblika podatkov.');
      }
      final out = <RestArea>[];
      for (final f in decoded['features'] as List) {
        if (f is Map<String, dynamic>) {
          try {
            out.add(RestArea.fromFeature(f));
          } catch (e) {
            debugPrint('RestAreasService: preskočeno: $e');
          }
        }
      }
      out.sort((a, b) => a.title.compareTo(b.title));
      return out;
    } on FormatException catch (e) {
      throw RestAreasServiceException('Podatkov ni bilo mogoče prebrati: $e');
    }
  }
}

class RestAreasServiceException implements Exception {
  final String message;
  const RestAreasServiceException(this.message);
  @override
  String toString() => message;
}
