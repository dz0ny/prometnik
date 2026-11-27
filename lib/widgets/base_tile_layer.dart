import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/map_tile_cache_service.dart';
import '../services/prefs.dart';

/// Base map tile sources: a muted CARTO map (the default, so pins stand out),
/// and the OpenStreetMap and Seznam.cz / Mapy.cz tourist maps from gozdar
/// (`MapLayer.openStreetMap`, `MapLayer.openTopoMap`).
enum BaseMap {
  /// CARTO Voyager in light mode, CARTO Dark Matter in dark mode.
  calm(
    id: 2,
    label: 'Umirjena',
    urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
    darkUrlTemplate:
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    attribution: '© OpenStreetMap, © CARTO',
    subdomains: ['a', 'b', 'c', 'd'],
    retina: true,
  ),
  openStreetMap(
    id: 0,
    label: 'OpenStreetMap',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: 'OpenStreetMap contributors',
  ),
  seznam(
    id: 1,
    label: 'Mapy.cz Turist',
    urlTemplate: 'https://mapserver.mapy.cz/turist-en/retina/{z}-{x}-{y}',
    attribution: 'Seznam.cz, © OpenStreetMap contributors',
    // mapy.cz answers 403 without a mapy.com Referer.
    headers: {'Referer': 'https://mapy.com/'},
  );

  const BaseMap({
    required this.id,
    required this.label,
    required this.urlTemplate,
    required this.attribution,
    this.darkUrlTemplate,
    this.headers = const {},
    this.subdomains = const [],
    this.retina = false,
  });

  /// Stable id stored in preferences (independent of declaration order).
  final int id;
  final String label;
  final String urlTemplate;

  /// Tiles drawn for dark mode instead of [urlTemplate], when the source has
  /// its own dark style (otherwise the tiles are inverted, see
  /// [buildBaseTileLayer]).
  final String? darkUrlTemplate;
  final String attribution;
  final Map<String, String> headers;
  final List<String> subdomains;

  /// The server has `@2x` tiles behind the `{r}` placeholder.
  final bool retina;

  /// Browsers do not let a page set the Referer mapy.cz requires, so the
  /// Seznam map only works in the native apps.
  static bool get seznamAvailable => !kIsWeb;

  /// Base maps the user can pick on this platform.
  static List<BaseMap> get selectable => [
    for (final b in values)
      if (b != seznam || seznamAvailable) b,
  ];

  static const _prefKey = 'map.base';

  /// The user's saved base map choice ([calm] when nothing was chosen).
  /// The pre-calm Seznam/OSM flag (`map.baseSeznam`) is deliberately not
  /// carried over: everyone starts on the calm map once.
  static BaseMap get saved => resolveSaved(
    id: Prefs.has(_prefKey) ? Prefs.getInt(_prefKey, calm.id) : null,
    legacySeznam: null,
    seznamAvailable: seznamAvailable,
  );

  static set saved(BaseMap v) => Prefs.setInt(_prefKey, v.id);

  /// Picks the base map from the stored [id], falling back to the legacy
  /// Seznam/OpenStreetMap flag so an older explicit choice keeps working,
  /// and to [calm] for new users or an unavailable map.
  @visibleForTesting
  static BaseMap resolveSaved({
    required int? id,
    required bool? legacySeznam,
    required bool seznamAvailable,
  }) {
    BaseMap choice;
    if (id != null) {
      choice = values.firstWhere((b) => b.id == id, orElse: () => calm);
    } else if (legacySeznam != null) {
      choice = legacySeznam ? seznam : openStreetMap;
    } else {
      choice = calm;
    }
    if (choice == seznam && !seznamAvailable) return calm;
    return choice;
  }
}

/// Native max zoom of the tile servers; the map may overzoom beyond it.
const double _nativeMaxZoom = 19;

/// The base tile layer for [base]. CARTO has its own dark style; in dark
/// mode OpenStreetMap is drawn with flutter_map's dark (inverted) filter.
TileLayer buildBaseTileLayer(
  BuildContext context, {
  BaseMap base = BaseMap.calm,
  required bool isDark,
}) {
  if (base == BaseMap.seznam && !BaseMap.seznamAvailable) {
    base = BaseMap.calm;
  }
  return TileLayer(
    urlTemplate: isDark
        ? base.darkUrlTemplate ?? base.urlTemplate
        : base.urlTemplate,
    subdomains: base.subdomains,
    // Only for servers with real @2x tiles: on others flutter_map would
    // simulate retina by fetching one zoom level deeper.
    retinaMode: base.retina && RetinaMode.isHighDensity(context),
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
