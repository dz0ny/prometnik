import 'dart:async';
import 'dart:collection';

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
    return _inFlight[url] ??= _download(url)
        .whenComplete(() => _inFlight.remove(url));
  }

  /// Whether a fresh download is worth it ([maxAge] since the last one).
  bool isFresh(String url, Duration maxAge) {
    final last = _lastFetch[cameraKey(url)];
    return last != null && DateTime.now().difference(last) < maxAge;
  }

  Future<WebcamFrame?> _download(String url) async {
    final key = cameraKey(url);
    try {
      final res = await _http.get(Uri.parse(url)).timeout(_timeout);
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode != 200 || !type.startsWith('image/')) {
        debugPrint('WebcamStore: $key answered ${res.statusCode} $type');
        return null;
      }
      final now = DateTime.now();
      final frame = WebcamFrame(res.bodyBytes, now);
      _remember(key, frame);
      _lastFetch[key] = now;
      unawaited(_persist(key, frame));
      return frame;
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

@visibleForTesting
String latestKey(String cameraKey) => 'latest|$cameraKey';

@visibleForTesting
String hourlyKey(String cameraKey, DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'hour|$cameraKey|${at.year}${two(at.month)}${two(at.day)}${two(at.hour)}';
}
