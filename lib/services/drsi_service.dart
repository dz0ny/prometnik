import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/drsi_station.dart';
import 'user_error.dart';

/// Road weather stations from DRSI's public CVIS site
/// (http://drsi.cgs-labs.si/CVIS).
///
/// The JSON handler only answers with a session: CVIS signs anonymous
/// visitors in as guests automatically when they open its login page (no
/// credentials), the same way a browser gets the public station table. We do
/// that once, keep the two cookies, and redo it when the session expires.
///
/// The site is plain HTTP without CORS, so it is unavailable on the web build.
class DrsiService {
  static final DrsiService _instance = DrsiService._internal();
  factory DrsiService() => _instance;
  DrsiService._internal();

  static const String _base = 'http://drsi.cgs-labs.si/CVIS';
  static const Duration _timeout = Duration(seconds: 20);
  static const Map<String, String> _headers = {
    'User-Agent': 'promet-flutter/1.0 (+https://github.com/dz0ny/prometnik)',
  };

  static bool get isSupported => !kIsWeb;

  final http.Client _client = http.Client();
  String? _cookie;

  Future<List<DrsiStation>> fetch() async {
    if (!isSupported) return const [];
    _cookie ??= await _signInAsGuest();
    var response = await _getData();
    if (_isLoginRedirect(response)) {
      // Session expired: sign in again once.
      _cookie = await _signInAsGuest();
      response = await _getData();
    }
    if (response.statusCode != 200) {
      throw DrsiServiceException(
        'Strežnik DRSI je vrnil napako ${response.statusCode}.',
      );
    }
    return parseDrsiTable(utf8.decode(response.bodyBytes));
  }

  bool _isLoginRedirect(http.BaseResponse r) =>
      r.statusCode == 302 &&
      (r.headers['location'] ?? '').toLowerCase().contains('login');

  Future<http.Response> _getData() =>
      _send(Uri.parse('$_base/Handlers/CurrentData.ashx'), cookie: _cookie);

  Future<String> _signInAsGuest() async {
    final r = await _send(
      Uri.parse(
        '$_base/Login.aspx?ReturnUrl=%2fCVIS%2fmodule%2fmapguide%2fdefault.aspx',
      ),
    );
    final cookie = cookieHeaderFrom(r.headers['set-cookie'] ?? '');
    if (cookie == null) {
      throw const DrsiServiceException('DRSI ni vrnil seje.');
    }
    return cookie;
  }

  Future<http.Response> _send(Uri uri, {String? cookie}) async {
    final req = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll(_headers);
    if (cookie != null) req.headers['Cookie'] = cookie;
    final streamed = await _client.send(req).timeout(_timeout);
    return http.Response.fromStream(streamed).timeout(_timeout);
  }
}

/// Builds a `Cookie` header from a (comma-joined) `Set-Cookie` header,
/// keeping the last value of the session and forms-auth cookies.
@visibleForTesting
String? cookieHeaderFrom(String setCookie) {
  final found = <String, String>{};
  final re = RegExp(r'(ASP\.NET_SessionId|\.ASPXFORMSAUTH)=([^;,\s]*)');
  for (final m in re.allMatches(setCookie)) {
    if (m.group(2)!.isNotEmpty) found[m.group(1)!] = m.group(2)!;
  }
  if (!found.containsKey('.ASPXFORMSAUTH')) return null;
  return found.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

/// Parses the DataTable JSON into stations that measure the road surface
/// and are online. Air-only stations mostly duplicate the weather layer.
@visibleForTesting
List<DrsiStation> parseDrsiTable(String body) {
  final Object? decoded;
  try {
    decoded = json.decode(body);
  } on FormatException catch (e) {
    throw DrsiServiceException('Podatkov DRSI ni bilo mogoče prebrati: $e');
  }
  if (decoded is! Map || decoded['cols'] is! List || decoded['rows'] is! List) {
    throw const DrsiServiceException('Nepričakovana oblika podatkov DRSI.');
  }
  final columns = <String, int>{
    for (final (i, c) in (decoded['cols'] as List).indexed)
      if (c is Map && c['id'] is String) c['id'] as String: i,
  };
  final out = <DrsiStation>[];
  for (final row in decoded['rows'] as List) {
    if (row is! Map<String, dynamic>) continue;
    try {
      final s = DrsiStation.fromRow(row, columns);
      if (s.hasRoadData && !s.outage) out.add(s);
    } on FormatException catch (e) {
      debugPrint('DrsiService: preskočeno: $e');
    }
  }
  return out;
}

class DrsiServiceException implements AppServiceException {
  @override
  final String message;
  const DrsiServiceException(this.message);
  @override
  String toString() => message;
}
