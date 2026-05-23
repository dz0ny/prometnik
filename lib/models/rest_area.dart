import 'package:latlong2/latlong.dart';

/// A motorway rest area / service area from promet.si `agg.pocivalisca.v2`,
/// including live parking availability and amenities.
class RestArea {
  final String id;
  final String title;
  final LatLng position;
  final String locationDescription;
  final String workingHours;

  /// Live availability of the monitored spaces.
  final int total;
  final int available;
  final double takenPercentage;

  /// "red" / "orange" / "green" / "gray" from the feed.
  final String availabilityColor;
  final String availabilityText;

  final int carSpaces;
  final int truckSpaces;

  /// Amenity keys present (e.g. 'fuel', 'store', 'food', 'wc', 'rv', 'atm',
  /// 'shower', 'wifi', 'playground', 'rest').
  final Set<String> amenities;

  const RestArea({
    required this.id,
    required this.title,
    required this.position,
    required this.locationDescription,
    required this.workingHours,
    required this.total,
    required this.available,
    required this.takenPercentage,
    required this.availabilityColor,
    required this.availabilityText,
    required this.carSpaces,
    required this.truckSpaces,
    required this.amenities,
  });

  bool get hasLiveAvailability => total > 0;

  factory RestArea.fromFeature(Map<String, dynamic> feature) {
    final p = (feature['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    final g = (feature['geometry'] as Map?)?.cast<String, dynamic>() ?? {};

    LatLng point() {
      final c = g['coordinates'];
      if (c is List && c.length >= 2) {
        return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
      }
      return const LatLng(46.1512, 14.9955);
    }

    String s(dynamic v) => (v as String?)?.trim() ?? '';
    int i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    double d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    bool b(dynamic v) => v == true || v == 'true' || v == 1;

    final amenities = <String>{};
    void add(String key, dynamic v) {
      if (b(v)) amenities.add(key);
    }

    add('fuel', p['HasBencinskiServis']);
    add('store', p['HasTrgovina']);
    if (b(p['HasRestavracija']) || b(p['HasBar'])) amenities.add('food');
    add('wc', p['HasStranisce']);
    add('rv', p['HasOskrbaAvtodomov']);
    add('atm', p['HasBankomat']);
    add('shower', p['HasTus']);
    add('wifi', p['HasWiFi']);
    add('playground', p['HasOtroskaIgrala']);
    add('rest', p['HasProstorZaPocitek']);

    return RestArea(
      id: s(p['Id']),
      title: s(p['Title']),
      position: point(),
      locationDescription: s(p['LocationDescription']),
      workingHours: s(p['WorkingHours']),
      total: i(p['nParkSpacesTotal']),
      available: i(p['nParkSpacesAvailable']),
      takenPercentage: d(p['nParkSpacesTakenPercentage']),
      availabilityColor: s(p['ColorAvailability']).toLowerCase(),
      availabilityText: s(p['DescriptionAvailability']),
      carSpaces: i(p['ParkingSpaces']),
      truckSpaces: i(p['TruckParkingSpaces']),
      amenities: amenities,
    );
  }
}
