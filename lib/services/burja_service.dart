import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/burja_station.dart';

/// Fetches crosswind (burja) measurements from promet.si
/// `GET https://www.promet.si/dc/agg.burja.v2`.
class BurjaService {
  static final BurjaService _instance = BurjaService._internal();
  factory BurjaService() => _instance;
  BurjaService._internal();

  static const String _endpoint = 'https://www.promet.si/dc/agg.burja.v2';
  static const Duration _timeout = Duration(seconds: 20);

  Future<List<BurjaStation>> fetch() async {
    final response = await http.get(
      Uri.parse(_endpoint),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'promet-flutter/1.0 (+https://www.promet.si/)',
      },
    ).timeout(_timeout);
    if (response.statusCode != 200) {
      throw BurjaServiceException(
        'Strežnik je vrnil napako ${response.statusCode}.',
      );
    }
    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['features'] is! List) {
        throw const BurjaServiceException('Nepričakovana oblika podatkov.');
      }
      final out = <BurjaStation>[];
      for (final f in decoded['features'] as List) {
        if (f is Map<String, dynamic>) {
          try {
            out.add(BurjaStation.fromFeature(f));
          } catch (e) {
            debugPrint('BurjaService: preskočeno: $e');
          }
        }
      }
      return out;
    } on FormatException catch (e) {
      throw BurjaServiceException('Podatkov ni bilo mogoče prebrati: $e');
    }
  }
}

class BurjaServiceException implements Exception {
  final String message;
  const BurjaServiceException(this.message);
  @override
  String toString() => message;
}
