import 'package:latlong2/latlong.dart';

import '../services/webcam_proxy.dart';

/// Road-condition risk at a DRSI road weather station, worst last.
enum RoadRisk { ok, caution, slippery, ice }

/// A road weather station (cestno vremenska postaja) on the state road
/// network, from DRSI's CVIS `Handlers/CurrentData.ashx`.
///
/// The feed is a Google Visualization DataTable whose cells are all strings
/// with Slovenian decimal commas ("-0,4"); empty strings mean "no reading".
class DrsiStation {
  final String id;

  /// Name without the "CVP - " / "VP - " prefix.
  final String name;
  final LatLng position;
  final DateTime? measuredAt;

  final double? airTemp;
  final double? roadTemp;
  final double? dewPoint;
  final double? freezePoint;
  final double? humidity;
  final double? windKmh;
  final double? gustKmh;
  final double? waterFilmMm;
  final double? salinity;
  final String salinityUnit;

  /// Road surface state code and description ("suho", "led", …).
  final int? roadStateId;
  final String roadState;

  /// Precipitation description ("ni padavin", "sneženje", …).
  final String precipitation;

  /// Active warnings (names as published, e.g. for ice or snow).
  final List<String> alarms;
  final String webcamUrl;

  /// Station is offline; its readings are stale.
  final bool outage;

  const DrsiStation({
    required this.id,
    required this.name,
    required this.position,
    required this.measuredAt,
    required this.airTemp,
    required this.roadTemp,
    required this.dewPoint,
    required this.freezePoint,
    required this.humidity,
    required this.windKmh,
    required this.gustKmh,
    required this.waterFilmMm,
    required this.salinity,
    required this.salinityUnit,
    required this.roadStateId,
    required this.roadState,
    required this.precipitation,
    required this.alarms,
    required this.webcamUrl,
    required this.outage,
  });

  /// Whether the station measures the road surface (not just the air).
  bool get hasRoadData => roadTemp != null || roadState.isNotEmpty;

  bool get _wet {
    final s = roadState.toLowerCase();
    return s.contains('mokro') || s.contains('vlažno') || s.contains('sneg');
  }

  bool get _salted => roadState.toLowerCase().contains('sol');

  /// Ice reported, or a wet unsalted surface at/below its freezing point.
  RoadRisk get risk {
    final s = roadState.toLowerCase();
    if (s.contains('led') || s.contains('poledic') || s.contains('zmrz')) {
      return RoadRisk.ice;
    }
    final t = roadTemp;
    if (t == null) return RoadRisk.ok;
    final freeze = freezePoint ?? 0;
    if (_wet && !_salted && t <= freeze + 0.5) return RoadRisk.slippery;
    if (t <= 1 && (_wet || precipitation.toLowerCase().contains('sne'))) {
      return RoadRisk.caution;
    }
    return RoadRisk.ok;
  }

  String cameraUrlWithBuster(int epochMillis) {
    return proxiedWebcamUrl(webcamUrl, buster: epochMillis);
  }

  /// Parses one DataTable row (`{"c": [{"v": ...}, ...]}`) using the column
  /// ids from [columns] so a column reorder upstream doesn't scramble fields.
  factory DrsiStation.fromRow(
    Map<String, dynamic> row,
    Map<String, int> columns,
  ) {
    final cells = (row['c'] as List?) ?? const [];

    dynamic cell(String id) {
      final i = columns[id];
      if (i == null || i >= cells.length) return null;
      final c = cells[i];
      return c is Map ? c['v'] : null;
    }

    String str(String id) {
      final v = cell(id);
      return v == null ? '' : '$v'.trim();
    }

    double? num_(String id) {
      final s = str(id).replaceAll(',', '.');
      return s.isEmpty ? null : double.tryParse(s);
    }

    final lat = num_('lat');
    final lon = num_('lon');
    if (lat == null || lon == null) {
      throw const FormatException('DRSI station without coordinates');
    }

    final names = str('alarmTNs');
    return DrsiStation(
      id: str('id'),
      name: str('title').replaceFirst(RegExp(r'^C?VP\s*-\s*'), '').trim(),
      position: LatLng(lat, lon),
      measuredAt: parseDrsiTime(str('mesTime')),
      airTemp: num_('tempZraka'),
      roadTemp: num_('tempCeste'),
      dewPoint: num_('tempRos'),
      freezePoint: num_('tempZmrz'),
      humidity: num_('vlaznost'),
      windKmh: num_('veterHitrost'),
      gustKmh: num_('vetrSunki'),
      waterFilmMm: num_('debelinaVodnegaFilma'),
      salinity: num_('slanostDrsnost'),
      salinityUnit: str('slanostDrsnostEnota'),
      roadStateId: int.tryParse(str('stanjeCestisca')),
      roadState: str('stanjeOpis'),
      precipitation: str('stanjevopis'),
      alarms: names.isEmpty
          ? const []
          : names
                .split('|')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
      webcamUrl: str('webcamurl'),
      outage: cell('olddata') == 1 || str('olddata') == '1',
    );
  }
}

/// "26.11.2026 20:56" (local Slovenian time) → [DateTime], or null.
DateTime? parseDrsiTime(String s) {
  final m = RegExp(
    r'^(\d{1,2})\.(\d{1,2})\.(\d{4})\s+(\d{1,2}):(\d{2})',
  ).firstMatch(s.trim());
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  return DateTime(g(3), g(2), g(1), g(4), g(5));
}
