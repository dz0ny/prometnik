import 'package:latlong2/latlong.dart';

/// Live weather reading for a station (from the `weather` object of the
/// `/Vremenske/Vreme/KamereInVreme` endpoint). May be absent for camera-only
/// stations.
class WeatherReading {
  final DateTime? timestamp;
  final double? outdoorTemperatureC;
  final int? pressureHpa;
  final int? humidityPercentage;
  final String? windDirection;
  final double? windSpeedKmh;
  final double? windGustKmh;
  final double? auxC;
  final double? dailyRainMm;
  final double? dewPointC;
  final double? minOutdoorTemperatureC;
  final double? maxOutdoorTemperatureC;

  const WeatherReading({
    this.timestamp,
    this.outdoorTemperatureC,
    this.pressureHpa,
    this.humidityPercentage,
    this.windDirection,
    this.windSpeedKmh,
    this.windGustKmh,
    this.auxC,
    this.dailyRainMm,
    this.dewPointC,
    this.minOutdoorTemperatureC,
    this.maxOutdoorTemperatureC,
  });

  factory WeatherReading.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    double? toDouble(dynamic v) => v == null ? null : (v as num).toDouble();
    int? toInt(dynamic v) => v == null ? null : (v as num).toInt();

    return WeatherReading(
      timestamp: parseTs(json['timestamp']),
      outdoorTemperatureC: toDouble(json['outdoorTemperatureC']),
      pressureHpa: toInt(json['pressureHpa']),
      humidityPercentage: toInt(json['humidityPercentage']),
      windDirection: (json['windDirection'] as String?)?.trim(),
      windSpeedKmh: toDouble(json['windSpeedKmh']),
      windGustKmh: toDouble(json['windGustKmh']),
      auxC: toDouble(json['auxC']),
      dailyRainMm: toDouble(json['dailyRainMm']),
      dewPointC: toDouble(json['dewPointC']),
      minOutdoorTemperatureC: toDouble(json['minOutdoorTemperatureC']),
      maxOutdoorTemperatureC: toDouble(json['maxOutdoorTemperatureC']),
    );
  }
}

/// A road weather + camera station from ceste.si / DARS.
class WeatherStation {
  final int stationId;
  final String name;

  /// `coordinateX` is latitude, `coordinateY` is longitude in the source data.
  final LatLng position;
  final String cameraLink;
  final WeatherReading? weather;

  const WeatherStation({
    required this.stationId,
    required this.name,
    required this.position,
    required this.cameraLink,
    required this.weather,
  });

  double? get temperatureC => weather?.outdoorTemperatureC;
  bool get hasWeather => weather != null;

  /// Cache-busting camera URL so each refresh fetches a fresh frame.
  String cameraUrlWithBuster(int epochMillis) {
    final sep = cameraLink.contains('?') ? '&' : '?';
    return '$cameraLink${sep}t=$epochMillis';
  }

  factory WeatherStation.fromJson(Map<String, dynamic> json) {
    // Some records ship coordinates with a misplaced decimal point
    // (e.g. 45957236.0). Normalise back into the WGS84 range.
    double normalize(num raw, {required double max}) {
      var v = raw.toDouble().abs();
      while (v > max) {
        v /= 10;
      }
      return v;
    }

    final lat = normalize(json['coordinateX'] as num, max: 90);
    final lng = normalize(json['coordinateY'] as num, max: 180);

    return WeatherStation(
      stationId: (json['stationId'] as num).toInt(),
      name: (json['name'] as String? ?? '').trim(),
      position: LatLng(lat, lng),
      cameraLink: json['cameraLink'] as String? ?? '',
      weather: json['weather'] == null
          ? null
          : WeatherReading.fromJson(json['weather'] as Map<String, dynamic>),
    );
  }
}
