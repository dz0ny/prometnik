import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/map_tile_cache_service.dart';
import '../services/prefs.dart';

/// Base map tile sources: Esri satellite imagery with road and place-name
/// overlays (the default), and the OpenStreetMap and Seznam.cz / Mapy.cz tourist maps from gozdar
/// (`MapLayer.openStreetMap`, `MapLayer.openTopoMap`).
enum BaseMap {
  /// Esri World Imagery, with Esri's road and place-name reference layers
  /// drawn on top (see [buildBaseOverlayLayers]).
  satellite(
    id: 3,
    label: 'Satelit',
    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    overlayUrlTemplates: [
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
    ],
    attribution:
        'Esri, Maxar, Earthstar Geographics, and the GIS User Community',
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
    this.overlayUrlTemplates = const [],
    this.headers = const {},
  });

  /// Stable id stored in preferences (independent of declaration order).
  final int id;
  final String label;
  final String urlTemplate;

  /// Transparent label/road layers drawn above the base tiles.
  final List<String> overlayUrlTemplates;
  final String attribution;
  final Map<String, String> headers;

  /// Browsers do not let a page set the Referer mapy.cz requires, so the
  /// Seznam map only works in the native apps.
  static bool get seznamAvailable => !kIsWeb;

  /// Base maps the user can pick on this platform.
  static List<BaseMap> get selectable => [
    for (final b in values)
      if (b != seznam || seznamAvailable) b,
  ];

  static const _prefKey = 'map.base';

  /// The user's saved base map choice ([satellite] when nothing was chosen).
  /// The older Seznam/OSM flag (`map.baseSeznam`) and the retired CARTO map
  /// (id 2) are deliberately not carried over: everyone starts on satellite.
  static BaseMap get saved => resolveSaved(
    id: Prefs.has(_prefKey) ? Prefs.getInt(_prefKey, satellite.id) : null,
    legacySeznam: null,
    seznamAvailable: seznamAvailable,
  );

  static set saved(BaseMap v) => Prefs.setInt(_prefKey, v.id);

  /// Picks the base map from the stored [id], falling back to the legacy
  /// Seznam/OpenStreetMap flag so an older explicit choice keeps working,
  /// and to [satellite] for new users or an unavailable map.
  @visibleForTesting
  static BaseMap resolveSaved({
    required int? id,
    required bool? legacySeznam,
    required bool seznamAvailable,
  }) {
    BaseMap choice;
    if (id != null) {
      choice = values.firstWhere((b) => b.id == id, orElse: () => satellite);
    } else if (legacySeznam != null) {
      choice = legacySeznam ? seznam : openStreetMap;
    } else {
      choice = satellite;
    }
    if (choice == seznam && !seznamAvailable) return satellite;
    return choice;
  }
}

/// Native max zoom of the tile servers; the map may overzoom beyond it.
const double _nativeMaxZoom = 19;

/// The base tile layer for [base]. In dark mode OpenStreetMap is drawn with
/// flutter_map's dark (inverted) filter; satellite imagery stays as it is.
TileLayer buildBaseTileLayer(
  BuildContext context, {
  BaseMap base = BaseMap.satellite,
  required bool isDark,
}) {
  if (base == BaseMap.seznam && !BaseMap.seznamAvailable) {
    base = BaseMap.satellite;
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

/// Reference overlays (roads, place names) for [base]; empty for most maps.
List<TileLayer> buildBaseOverlayLayers(BaseMap base) => [
  for (final url in base.overlayUrlTemplates)
    TileLayer(
      urlTemplate: url,
      tileProvider: MapTileCacheService.instance.createTileProvider(),
      userAgentPackageName: 'dev.dz0ny.promet',
      maxNativeZoom: _nativeMaxZoom.toInt(),
    ),
];
