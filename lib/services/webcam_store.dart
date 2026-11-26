import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import 'webcam_proxy.dart';

/// One stored webcam frame.
class WebcamFrame {
  final Uint8List bytes;
  final DateTime at;
  const WebcamFrame(this.bytes, this.at);
}

/// One hour of a camera's history: either a frame already on the device
/// ([bytes]) or an hourly snapshot kept by the edge worker ([url]).
class WebcamHistoryEntry {
  /// Local start of the hour.
  final DateTime at;
  final Uint8List? bytes;
  final String? url;
  const WebcamHistoryEntry({required this.at, this.bytes, this.url})
    : assert(bytes != null || url != null);

  bool get isLocal => bytes != null;

  /// The entry as a frame, when its bytes are on the device.
  WebcamFrame? get frame => bytes == null ? null : WebcamFrame(bytes!, at);
}

/// An hourly snapshot listed by the worker's `/history` endpoint.
class ServerSnapshot {
  /// Start of the hour (UTC as sent by the worker).
  final DateTime at;
  final String url;
  const ServerSnapshot(this.at, this.url);
}

/// Keeps webcam frames on the device so images appear instantly and a short
/// history is available:
///
/// * the **latest** frame per camera (memory + disk), shown immediately while
///   a fresh frame downloads, then replaced;
/// * one **hourly** snapshot per camera for the last [historyHours] hours,
///   captured whenever the app downloads a frame in an hour it has none for.
///
/// Cameras are identified by their original URL (proxy wrapper and the
/// cache-buster stripped), so the same camera shares frames across screens.
class WebcamStore {
  WebcamStore._();
  static final WebcamStore instance = WebcamStore._();

  static const int historyHours = 24;
  static const Duration _timeout = Duration(seconds: 20);
  static const int _memLimit = 120;

  final CacheManager _disk = CacheManager(
    Config(
      'webcamFrames',
      stalePeriod: const Duration(hours: historyHours + 1),
      maxNrOfCacheObjects: 4000,
    ),
  );
  final http.Client _http = http.Client();

  // Latest frames in memory (LRU) so a re-mounted widget can paint at once.
  final LinkedHashMap<String, WebcamFrame> _latest = LinkedHashMap();
  final Map<String, Future<WebcamFrame?>> _inFlight = {};
  final Map<String, DateTime> _lastFetch = {};

  /// The frame currently known for [url] without waiting, if any.
  WebcamFrame? latestSync(String url) {
    final key = cameraKey(url);
    final f = _latest.remove(key);
    if (f != null) _latest[key] = f; // refresh LRU position
    return f;
  }

  /// The last stored frame for [url] (memory, then disk), if any.
  Future<WebcamFrame?> latest(String url) async {
    final mem = latestSync(url);
    if (mem != null) return mem;
    final key = cameraKey(url);
    try {
      final info = await _disk.getFileFromCache(latestKey(key));
      if (info == null) return null;
      final frame = WebcamFrame(
        await info.file.readAsBytes(),
        info.validTill.subtract(const Duration(hours: historyHours + 1)),
      );
      _remember(key, frame);
      return frame;
    } on Exception catch (e) {
      debugPrint('WebcamStore.latest($key): $e');
      return null;
    }
  }

  /// Downloads the current frame for [url] (the proxied, cache-busted URL),
  /// stores it as the latest frame and, if this hour has none yet, as the
  /// hourly snapshot. Concurrent calls for the same URL share one download.
  /// Returns null when the camera can't be reached.
  Future<WebcamFrame?> fetch(String url) {
    // Block body on purpose: `=> _inFlight.remove(url)` would return the
    // in-flight future itself, and whenComplete would then wait on it forever.
    return _inFlight[url] ??= _download(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  /// Whether a fresh download is worth it ([maxAge] since the last one).
  bool isFresh(String url, Duration maxAge) {
    final last = _lastFetch[cameraKey(url)];
    return last != null && DateTime.now().difference(last) < maxAge;
  }

  Future<WebcamFrame?> _download(String url) async {
    final key = cameraKey(url);
    // The edge cache answers first; the camera itself is only a fallback for
    // when the proxy is unreachable or failing.
    var bytes = await _getImage(url, key);
    final direct = directWebcamUrl(url);
    if (bytes == null && direct != null) {
      debugPrint('WebcamStore: proxy failed for $key, trying the camera');
      bytes = await _getImage(direct, key);
    }
    if (bytes == null) return null;
    final now = DateTime.now();
    final frame = WebcamFrame(bytes, now);
    _remember(key, frame);
    _lastFetch[key] = now;
    unawaited(_persist(key, frame));
    return frame;
  }

  Future<Uint8List?> _getImage(String url, String key) async {
    try {
      final res = await _http.get(Uri.parse(url)).timeout(_timeout);
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode != 200 || !type.startsWith('image/')) {
        debugPrint('WebcamStore: $key answered ${res.statusCode} $type');
        return null;
      }
      return res.bodyBytes;
    } on Exception catch (e) {
      debugPrint('WebcamStore.fetch($key): $e');
      return null;
    }
  }

  Future<void> _persist(String key, WebcamFrame frame) async {
    const maxAge = Duration(hours: historyHours + 1);
    try {
      await _disk.putFile(
        latestKey(key),
        frame.bytes,
        key: latestKey(key),
        maxAge: maxAge,
        fileExtension: 'jpg',
      );
      final hourKey = hourlyKey(key, frame.at);
      if (await _disk.getFileFromCache(hourKey) == null) {
        await _disk.putFile(
          hourKey,
          frame.bytes,
          key: hourKey,
          maxAge: maxAge,
          fileExtension: 'jpg',
        );
      }
    } on Exception catch (e) {
      debugPrint('WebcamStore persist($key): $e');
    }
  }

  /// Hourly snapshots for [url] over the last [historyHours] hours, oldest
  /// first. Only hours in which the app loaded this camera are present.
  Future<List<WebcamFrame>> history(String url) async {
    final key = cameraKey(url);
    final now = DateTime.now();
    final out = <WebcamFrame>[];
    for (var h = historyHours - 1; h >= 0; h--) {
      final hour = now.subtract(Duration(hours: h));
      try {
        final info = await _disk.getFileFromCache(hourlyKey(key, hour));
        if (info == null) continue;
        out.add(
          WebcamFrame(
            await info.file.readAsBytes(),
            DateTime(hour.year, hour.month, hour.day, hour.hour),
          ),
        );
      } on Exception catch (e) {
        debugPrint('WebcamStore.history($key): $e');
      }
    }
    return out;
  }

  /// Local hourly snapshots merged with the worker's hourly snapshots for
  /// [url], oldest first. Local bytes win for an hour both have; when the
  /// worker can't be reached this is just the local history.
  Future<List<WebcamHistoryEntry>> mergedHistory(String url) async {
    final results = await Future.wait([
      history(url),
      _serverHistory(cameraKey(url)),
    ]);
    return mergeWebcamHistory(
      results[0] as List<WebcamFrame>,
      results[1] as List<ServerSnapshot>,
      now: DateTime.now(),
    );
  }

  /// Cache for the worker's snapshot images (thumbnails and full frames).
  final CacheManager snapshotCache = CacheManager(
    Config(
      'webcamServerSnaps',
      stalePeriod: const Duration(hours: historyHours + 1),
      maxNrOfCacheObjects: 2000,
    ),
  );

  static const Duration _serverTimeout = Duration(seconds: 10);
  static const Duration _serverListTtl = Duration(minutes: 5);
  static const Duration _serverFailTtl = Duration(minutes: 1);
  static const int _snapMemLimit = 48;

  final Map<String, ({DateTime fetched, List<ServerSnapshot> list, bool ok})>
  _serverLists = {};
  final Map<String, Future<List<ServerSnapshot>>> _serverInFlight = {};
  final LinkedHashMap<String, WebcamFrame> _snaps = LinkedHashMap();
  final Map<String, Future<WebcamFrame?>> _snapInFlight = {};

  Future<List<ServerSnapshot>> _serverHistory(String key) {
    final cam = Uri.tryParse(key);
    if (cam == null || !webcamProxyHosts.contains(cam.host.toLowerCase())) {
      return Future.value(const []);
    }
    final cached = _serverLists[key];
    if (cached != null &&
        DateTime.now().difference(cached.fetched) <
            (cached.ok ? _serverListTtl : _serverFailTtl)) {
      return Future.value(cached.list);
    }
    return _serverInFlight[key] ??= _fetchServerHistory(key).whenComplete(() {
      _serverInFlight.remove(key);
    });
  }

  Future<List<ServerSnapshot>> _fetchServerHistory(String key) async {
    var ok = false;
    var list = const <ServerSnapshot>[];
    try {
      final uri = Uri.https(webcamProxyHost, '/history', {'u': key});
      final res = await _http.get(uri).timeout(_serverTimeout);
      if (res.statusCode == 200) {
        list = parseServerHistory(res.body);
        ok = true;
      } else {
        debugPrint('WebcamStore: history $key answered ${res.statusCode}');
      }
    } on Exception catch (e) {
      debugPrint('WebcamStore.serverHistory($key): $e');
    }
    _serverLists[key] = (fetched: DateTime.now(), list: list, ok: ok);
    return list;
  }

  /// The frame for a history [entry]: its local bytes, or the worker's
  /// snapshot downloaded (cached in memory and on disk). Null on failure.
  Future<WebcamFrame?> snapshotFrame(WebcamHistoryEntry entry) {
    final local = entry.frame;
    if (local != null) return Future.value(local);
    final url = entry.url!;
    final mem = _snaps.remove(url);
    if (mem != null) {
      _snaps[url] = mem;
      return Future.value(mem);
    }
    return _snapInFlight[url] ??= _downloadSnap(url, entry.at).whenComplete(() {
      _snapInFlight.remove(url);
    });
  }

  Future<WebcamFrame?> _downloadSnap(String url, DateTime at) async {
    try {
      final file = await snapshotCache.getSingleFile(url).timeout(_timeout);
      final frame = WebcamFrame(await file.readAsBytes(), at);
      _snaps[url] = frame;
      while (_snaps.length > _snapMemLimit) {
        _snaps.remove(_snaps.keys.first);
      }
      return frame;
    } on Exception catch (e) {
      debugPrint('WebcamStore.snapshot($url): $e');
      return null;
    }
  }

  void _remember(String key, WebcamFrame frame) {
    _latest.remove(key);
    _latest[key] = frame;
    while (_latest.length > _memLimit) {
      _latest.remove(_latest.keys.first);
    }
  }
}

/// Identity of a camera: its original URL, unwrapped from the edge proxy
/// and without the app's `t` cache-buster.
String cameraKey(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final original = uri.host == webcamProxyHost
      ? uri.queryParameters['u']
      : null;
  final cam = Uri.tryParse(original ?? url);
  if (cam == null) return original ?? url;
  final params = Map.of(cam.queryParameters)..remove('t');
  // replace(queryParameters: null) would keep the old query, so clear it
  // explicitly when `t` was the only parameter.
  final stripped = params.isEmpty
      ? cam.replace(query: '')
      : cam.replace(queryParameters: params);
  return stripped.removeFragment().toString().replaceAll(RegExp(r'\?$'), '');
}

/// Parses the worker's `/history` response. Anything malformed (bad JSON,
/// missing fields, unparsable times, non-http URLs) is dropped; a broken
/// body gives an empty list.
List<ServerSnapshot> parseServerHistory(String body) {
  Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  if (json is! Map) return const [];
  final frames = json['frames'];
  if (frames is! List) return const [];
  final out = <ServerSnapshot>[];
  for (final f in frames) {
    if (f is! Map) continue;
    final at = f['at'];
    final url = f['url'];
    if (at is! String || url is! String) continue;
    final time = DateTime.tryParse(at);
    final uri = Uri.tryParse(url);
    if (time == null || uri == null || !uri.isScheme('https')) continue;
    out.add(ServerSnapshot(time, url));
  }
  return out;
}

/// Merges device-local hourly [local] frames with the worker's [server]
/// snapshots into one entry per hour, oldest first, covering the
/// [WebcamStore.historyHours] hours up to [now]. Hours are matched as
/// instants (server UTC hour vs local hour); local bytes win when both
/// have an hour. Entry times are local.
List<WebcamHistoryEntry> mergeWebcamHistory(
  List<WebcamFrame> local,
  List<ServerSnapshot> server, {
  required DateTime now,
}) {
  const hourMs = Duration.millisecondsPerHour;
  int bucket(DateTime t) {
    final ms = t.millisecondsSinceEpoch;
    return ms - ms % hourMs;
  }

  final newest = bucket(now);
  final oldest = newest - (WebcamStore.historyHours - 1) * hourMs;
  bool inRange(int b) => b >= oldest && b <= newest;
  DateTime localAt(int b) => DateTime.fromMillisecondsSinceEpoch(b);

  final byHour = <int, WebcamHistoryEntry>{};
  for (final s in server) {
    final b = bucket(s.at);
    if (!inRange(b)) continue;
    byHour[b] = WebcamHistoryEntry(at: localAt(b), url: s.url);
  }
  for (final f in local) {
    final b = bucket(f.at);
    if (!inRange(b)) continue;
    byHour[b] = WebcamHistoryEntry(at: localAt(b), bytes: f.bytes);
  }
  final keys = byHour.keys.toList()..sort();
  return [for (final k in keys) byHour[k]!];
}

@visibleForTesting
String latestKey(String cameraKey) => 'latest|$cameraKey';

@visibleForTesting
String hourlyKey(String cameraKey, DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'hour|$cameraKey|${at.year}${two(at.month)}${two(at.day)}${two(at.hour)}';
}

/// For a URL that goes through the edge proxy, the camera's own URL (with a
/// fresh cache-buster) to fall back to; null when [url] isn't proxied.
String? directWebcamUrl(String url, {int? buster}) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host != webcamProxyHost) return null;
  final original = uri.queryParameters['u'];
  if (original == null || original.isEmpty) return null;
  final t = buster ?? DateTime.now().millisecondsSinceEpoch;
  final sep = original.contains('?') ? '&' : '?';
  return '$original${sep}t=$t';
}
