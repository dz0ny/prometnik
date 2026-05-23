import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/traffic_event.dart';

/// Fetches traffic events ("dogodki") from the public promet.si data channel.
///
/// `GET https://www.promet.si/dc/agg.dogodki.v2` returns a GeoJSON
/// FeatureCollection of Point features (no auth, ~60s cache). This is the open
/// equivalent of the authenticated NAP b2b events feed.
class EventsService {
  static final EventsService _instance = EventsService._internal();
  factory EventsService() => _instance;
  EventsService._internal();

  static const String _endpoint = 'https://www.promet.si/dc/agg.dogodki.v2';
  static const Duration _timeout = Duration(seconds: 20);

  Future<List<TrafficEvent>> fetchEvents() async {
    final response = await http.get(
      Uri.parse(_endpoint),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'promet-flutter/1.0 (+https://www.promet.si/)',
      },
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw EventsServiceException(
        'Strežnik je vrnil napako ${response.statusCode}.',
      );
    }

    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['features'] is! List) {
        throw const EventsServiceException('Nepričakovana oblika podatkov.');
      }
      final events = <TrafficEvent>[];
      for (final feature in decoded['features'] as List) {
        if (feature is Map<String, dynamic>) {
          try {
            events.add(TrafficEvent.fromFeature(feature));
          } catch (e) {
            debugPrint('EventsService: preskočen dogodek: $e');
          }
        }
      }
      // Highest priority (lowest number) first, then by road.
      events.sort((a, b) {
        final p = a.priority.compareTo(b.priority);
        return p != 0 ? p : a.road.compareTo(b.road);
      });
      return events;
    } on FormatException catch (e) {
      throw EventsServiceException('Podatkov ni bilo mogoče prebrati: $e');
    }
  }
}

class EventsServiceException implements Exception {
  final String message;
  const EventsServiceException(this.message);
  @override
  String toString() => message;
}
