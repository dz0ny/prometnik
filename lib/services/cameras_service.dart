import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/traffic_camera.dart';

/// Fetches DARS traffic cameras from the public promet.si data channel
/// `GET https://www.promet.si/dc/agg.kamere.v2` (GeoJSON FeatureCollection).
class CamerasService {
  static final CamerasService _instance = CamerasService._internal();
  factory CamerasService() => _instance;
  CamerasService._internal();

  static const String _endpoint = 'https://www.promet.si/dc/agg.kamere.v2';
  static const Duration _timeout = Duration(seconds: 20);

  Future<List<TrafficCamera>> fetchCameras() async {
    final response = await http.get(
      Uri.parse(_endpoint),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'promet-flutter/1.0 (+https://www.promet.si/)',
      },
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw CamerasServiceException(
        'Strežnik je vrnil napako ${response.statusCode}.',
      );
    }

    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['features'] is! List) {
        throw const CamerasServiceException('Nepričakovana oblika podatkov.');
      }
      final cameras = <TrafficCamera>[];
      for (final feature in decoded['features'] as List) {
        if (feature is Map<String, dynamic>) {
          try {
            final cam = TrafficCamera.fromFeature(feature);
            if (cam.imageUrl.isNotEmpty) cameras.add(cam);
          } catch (e) {
            debugPrint('CamerasService: preskočena kamera: $e');
          }
        }
      }
      return cameras;
    } on FormatException catch (e) {
      throw CamerasServiceException('Podatkov ni bilo mogoče prebrati: $e');
    }
  }
}

class CamerasServiceException implements Exception {
  final String message;
  const CamerasServiceException(this.message);
  @override
  String toString() => message;
}
