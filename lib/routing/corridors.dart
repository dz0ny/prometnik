import 'package:latlong2/latlong.dart';

import 'road_graph.dart';
import 'route_warnings.dart';

/// The DARS travel-time corridors (`agg.potovalnicasi.v2`): the feed gives
/// only their titles, so their geometry is routed here between motorway
/// points. Titles must match the feed's.
const _definitions = <(String, String, List<LatLng>)>[
  ('LJ - KP', 'KP - LJ', [LatLng(46.0335, 14.4455), LatLng(45.5520, 13.7480)]),
  (
    'LJ - Karavanke',
    'Karavanke - LJ',
    [LatLng(46.0755, 14.4640), LatLng(46.4380, 14.0830)],
  ),
  ('LJ - MB', 'MB - LJ', [LatLng(46.0620, 14.5860), LatLng(46.4890, 15.6190)]),
  (
    'LJ - MP Obrežje',
    'MP Obrežje - LJ',
    [LatLng(46.0200, 14.5560), LatLng(45.8470, 15.6900)],
  ),
  // The Ljubljana ring. With right-hand traffic, going clockwise (Kozarje →
  // Koseze → Tomačevo → Zadobrova → Malence) is the inner carriageway.
  (
    'LJ obv. notranji krog',
    'LJ obv. zunanji krog',
    [
      LatLng(46.0335, 14.4455),
      LatLng(46.0755, 14.4640),
      LatLng(46.0880, 14.5300),
      LatLng(46.0620, 14.5860),
      LatLng(46.0200, 14.5560),
      LatLng(46.0335, 14.4455),
    ],
  ),
];

/// The corridors with their geometry on [graph].
List<Corridor> buildCorridors(RoadGraph graph) => [
  for (final (forward, backward, stops) in _definitions)
    Corridor(
      forward,
      backward,
      graph.routes(stops, alternatives: 0).firstOrNull?.points ?? const [],
    ),
];
