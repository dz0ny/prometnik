import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';

/// Shared tile providers for every FlutterMap in the app, backed by one
/// on-disk tile cache (ported from gozdar's TileCacheService).
class MapTileCacheService {
  MapTileCacheService._();

  static final instance = MapTileCacheService._();

  BuiltInMapCachingProvider? _cacheProvider;

  /// App-lifetime HTTP client. flutter_map calls `tileProvider.dispose()`
  /// whenever a TileLayer is disposed, and NetworkTileProvider then closes a
  /// client *it created*. Handing in our own client means closing one map
  /// (e.g. an event sheet) never kills tile loading in another.
  final Client _httpClient = RetryClient(Client());

  NetworkTileProvider? _provider;
  final Map<String, NetworkTileProvider> _headeredProviders = {};

  Future<void> initialize() async {
    _cacheProvider ??= BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: 1_000_000_000,
      overrideFreshAge: const Duration(days: 365),
    );
  }

  /// Provider for a tile source; [headers] are extra HTTP headers the source
  /// requires (e.g. mapy.cz needs a mapy.com Referer). Sources with different
  /// headers get separate providers so a Referer is never sent elsewhere.
  TileProvider createTileProvider({Map<String, String> headers = const {}}) {
    if (headers.isEmpty) {
      return _provider ??= NetworkTileProvider(
        httpClient: _httpClient,
        cachingProvider: _cacheProvider,
      );
    }
    final key = headers.entries.map((e) => '${e.key}:${e.value}').join('|');
    return _headeredProviders.putIfAbsent(
      key,
      // Mutable copy: TileLayer putIfAbsents a User-Agent into this map.
      () => NetworkTileProvider(
        headers: Map.of(headers),
        httpClient: _httpClient,
        cachingProvider: _cacheProvider,
      ),
    );
  }
}
