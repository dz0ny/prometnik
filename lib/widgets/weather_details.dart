import 'package:intl/intl.dart';

import '../models/weather_station.dart';

/// Formatting helpers for weather values, shared across screens.
class WeatherFormat {
  WeatherFormat._();

  /// [v] with [digits] decimals, a Slovenian decimal comma and no "-0,0"
  /// for small negatives that round to zero.
  static String decimal(double v, [int digits = 1]) {
    var s = v.toStringAsFixed(digits);
    if (double.parse(s) == 0) s = 0.0.toStringAsFixed(digits);
    return s.replaceAll('.', ',');
  }

  static String temp(double? c) => c == null ? '–' : '${decimal(c)} °C';

  /// Slovenian compass abbreviation (S = sever, V = vzhod, J = jug,
  /// Z = zahod) for the feed's English code, e.g. "ENE" → "VSV". Unknown
  /// values are returned unchanged.
  static String windDirection(String? dir) {
    if (dir == null) return '';
    final d = dir.trim().toUpperCase();
    if (bearing(d) == null) return dir.trim();
    const letters = {'N': 'S', 'E': 'V', 'S': 'J', 'W': 'Z'};
    return d.split('').map((c) => letters[c] ?? c).join();
  }

  /// Where the wind comes from, in words: "ESE" → "iz vzhoda-jugovzhoda".
  /// Empty for an unknown code.
  static String windFrom(String? dir) {
    const words = {
      'N': 'severa',
      'NNE': 'severa-severovzhoda',
      'NE': 'severovzhoda',
      'ENE': 'vzhoda-severovzhoda',
      'E': 'vzhoda',
      'ESE': 'vzhoda-jugovzhoda',
      'SE': 'jugovzhoda',
      'SSE': 'juga-jugovzhoda',
      'S': 'juga',
      'SSW': 'juga-jugozahoda',
      'SW': 'jugozahoda',
      'WSW': 'zahoda-jugozahoda',
      'W': 'zahoda',
      'WNW': 'zahoda-severozahoda',
      'NW': 'severozahoda',
      'NNW': 'severa-severozahoda',
    };
    final w = words[dir?.trim().toUpperCase()];
    return w == null ? '' : 'iz $w';
  }

  static String wind(WeatherReading w) {
    if (w.windSpeedKmh == null) return '–';
    final dir = (w.windDirection?.isNotEmpty ?? false)
        ? ' ${windDirection(w.windDirection)}'
        : '';
    final gust = w.windGustKmh != null
        ? ' (sunki ${w.windGustKmh!.round()} km/h)'
        : '';
    return '${w.windSpeedKmh!.round()} km/h$dir$gust';
  }

  static String humidity(int? p) => p == null ? '–' : '$p %';
  static String pressure(int? h) => h == null ? '–' : '$h hPa';
  static String rain(double? mm) => mm == null ? '–' : '${decimal(mm)} mm';
  static String dew(double? c) => temp(c);

  /// Degrees with one decimal and a comma, no unit: "-0,4°".
  static String degrees(double? c) => c == null ? '–' : '${decimal(c)}°';

  static String minMax(WeatherReading w) {
    final lo = w.minOutdoorTemperatureC;
    final hi = w.maxOutdoorTemperatureC;
    if (lo == null && hi == null) return '–';
    return '${degrees(lo)} / ${degrees(hi)}';
  }

  /// The app-wide date/time format, "26. 11. 2026, 20:56".
  static final dateTimeFormat = DateFormat('d. M. yyyy, HH:mm');

  /// Hour of a camera snapshot, "12.00".
  static String hour(DateTime t) => DateFormat('HH.mm').format(t);

  static String timestamp(DateTime? ts) {
    if (ts == null) return 'ni podatka';
    return dateTimeFormat.format(ts);
  }

  /// Compass bearing in degrees for a cardinal direction string (e.g. "NNE"),
  /// or null if unknown. North = 0°, clockwise.
  static double? bearing(String? dir) {
    if (dir == null) return null;
    const map = {
      'N': 0.0,
      'NNE': 22.5,
      'NE': 45.0,
      'ENE': 67.5,
      'E': 90.0,
      'ESE': 112.5,
      'SE': 135.0,
      'SSE': 157.5,
      'S': 180.0,
      'SSW': 202.5,
      'SW': 225.0,
      'WSW': 247.5,
      'W': 270.0,
      'WNW': 292.5,
      'NW': 315.0,
      'NNW': 337.5,
    };
    return map[dir.trim().toUpperCase()];
  }
}
