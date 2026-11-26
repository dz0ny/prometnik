import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/map_tile_cache_service.dart';
import '../services/prefs.dart';

/// Base map tile sources, as used in gozdar (`MapLayer.openStreetMap` and
/// `MapLayer.openTopoMap`, the Seznam.cz / Mapy.cz tourist map).
enum BaseMap {
  openStreetMap(
    label: 'OpenStreetMap',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: 'OpenStreetMap contributors',
  ),
  seznam(
    label: 'Mapy.cz Turist',
    urlTemplate: 'https://mapserver.mapy.cz/turist-en/retina/{z}-{x}-{y}',
    attribution: 'Seznam.cz, © OpenStreetMap contributors',
    // mapy.cz answers 403 without a mapy.com Referer.
    headers: {'Referer': 'https://mapy.com/'},
  );

  const BaseMap({
    required this.label,
    required this.urlTemplate,
    required this.attribution,
    this.headers = const {},
  });

  final String label;
  final String urlTemplate;
  final String attribution;
  final Map<String, String> headers;

  /// Browsers do not let a page set the Referer mapy.cz requires, so the
  /// Seznam map only works in the native apps.
  static bool get seznamAvailable => !kIsWeb;

  static const _prefKey = 'map.baseSeznam';

  /// The user's saved base map choice (OpenStreetMap by default).
  static BaseMap get saved => seznamAvailable && Prefs.getBool(_prefKey, false)
      ? seznam
      : openStreetMap;

  static set saved(BaseMap v) => Prefs.setBool(_prefKey, v == seznam);
}

/// Native max zoom of the tile servers; the map may overzoom beyond it.
const double _nativeMaxZoom = 19;

/// The base tile layer for [base]. In dark mode OpenStreetMap is drawn with
/// flutter_map's dark (inverted) filter.
TileLayer buildBaseTileLayer(
  BuildContext context, {
  BaseMap base = BaseMap.openStreetMap,
  required bool isDark,
}) {
  if (base == BaseMap.seznam && !BaseMap.seznamAvailable) {
    base = BaseMap.openStreetMap;
  }
  return TileLayer(
    urlTemplate: base.urlTemplate,
    tileProvider: MapTileCacheService.instance.createTileProvider(
      headers: base.headers,
    ),
    userAgentPackageName: 'dev.dz0ny.promet',
    maxNativeZoom: _nativeMaxZoom.toInt(),
    tileBuilder: isDark && base == BaseMap.openStreetMap
        ? darkModeTileBuilder
        : null,
  );
}

/// Attribution for [base], collapsed behind an info button. [bottomInset]
/// lifts it above overlays such as the floating iOS tab bar.
Widget buildBaseMapAttribution(
  BaseMap base, {
  AttributionAlignment alignment = AttributionAlignment.bottomLeft,
  double bottomInset = 0,
}) {
  return Padding(
    padding: EdgeInsets.only(bottom: bottomInset),
    child: RichAttributionWidget(
      alignment: alignment,
      showFlutterMapAttribution: false,
      attributions: [TextSourceAttribution(base.attribution)],
    ),
  );
}
