import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../routing/saved_route.dart';

/// A place found by name, with a line saying where it is.
@immutable
class PlaceHit {
  final RoutePlace place;

  /// e.g. "Ulica, Ljubljana" or "naselje, Vrhnika".
  final String subtitle;
  const PlaceHit(this.place, this.subtitle);
}

/// Searches places in Slovenia by name with Photon (komoot's free OSM
/// search). Only used while editing a route; routes themselves are computed
/// on the device.
class PlaceSearchService {
  PlaceSearchService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// Slovenia, slightly padded (lon/lat).
  static const _bbox = '13.3,45.4,16.7,46.9';

  Future<List<PlaceHit>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': q,
      'limit': '10',
      'lang': 'default',
      'bbox': _bbox,
    });
    final res = await _http
        .get(uri, headers: const {'User-Agent': 'prometnik-app/1.0'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw http.ClientException('Iskanje ni uspelo (${res.statusCode}).');
    }
    return parsePhoton(utf8.decode(res.bodyBytes));
  }
}

/// Parses a Photon GeoJSON response; malformed features are skipped and
/// duplicates (same name, ~same spot) dropped.
@visibleForTesting
List<PlaceHit> parsePhoton(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  if (json is! Map || json['features'] is! List) return const [];
  final out = <PlaceHit>[];
  final seen = <String>{};
  for (final f in json['features'] as List) {
    if (f is! Map) continue;
    final p = f['properties'];
    final c = (f['geometry'] as Map?)?['coordinates'];
    if (p is! Map || c is! List || c.length < 2) continue;
    final lon = c[0], lat = c[1];
    if (lon is! num || lat is! num) continue;
    String s(String k) => p[k] is String ? (p[k] as String).trim() : '';
    final street = [
      s('street'),
      s('housenumber'),
    ].where((x) => x.isNotEmpty).join(' ');
    final name = s('name').isNotEmpty ? s('name') : street;
    if (name.isEmpty) continue;
    final key = '$name|${lat.toStringAsFixed(2)}|${lon.toStringAsFixed(2)}';
    if (!seen.add(key)) continue;
    final city = s('city');
    final subtitle = [
      if (street.isNotEmpty && street != name) street,
      if (city.isNotEmpty && city != name) city,
      ?placeKind(s('osm_key'), s('osm_value'), s('type')),
    ].join(', ');
    out.add(
      PlaceHit(
        RoutePlace(name, LatLng(lat.toDouble(), lon.toDouble())),
        subtitle,
      ),
    );
  }
  return out;
}

/// A Slovenian word for what a Photon result is ("občina", "naselje",
/// "ulica"), or null when it adds nothing.
@visibleForTesting
String? placeKind(String key, String value, String type) {
  if (value == 'municipality' || value == 'administrative') return 'občina';
  if (const {'city', 'town'}.contains(value)) return 'mesto';
  if (const {
    'village',
    'hamlet',
    'suburb',
    'neighbourhood',
    'quarter',
  }.contains(value)) {
    return 'naselje';
  }
  if (key == 'highway' || type == 'street') return 'ulica';
  if (type == 'house') return 'naslov';
  if (key == 'amenity' || key == 'shop' || key == 'tourism') return 'kraj';
  return null;
}
