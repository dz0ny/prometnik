import 'package:flutter_map/flutter_map.dart';

class MapTileCacheService {
  MapTileCacheService._();

  static final instance = MapTileCacheService._();

  BuiltInMapCachingProvider? _cacheProvider;

  Future<void> initialize() async {
    _cacheProvider ??= BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: 1_000_000_000,
      overrideFreshAge: const Duration(days: 365),
    );
  }

  TileProvider createTileProvider() {
    return NetworkTileProvider(cachingProvider: _cacheProvider);
  }
}
