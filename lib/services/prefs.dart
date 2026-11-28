import 'package:shared_preferences/shared_preferences.dart';

/// Tiny synchronous wrapper around SharedPreferences for persisting UI state
/// (filters). Call [init] once at startup before reading.
class Prefs {
  Prefs._();

  static late SharedPreferences _p;
  static bool _ready = false;

  /// Safe to call more than once (the background task may run twice in one
  /// isolate).
  static Future<void> init() async {
    if (_ready) return;
    _p = await SharedPreferences.getInstance();
    _ready = true;
  }

  /// Re-read values another isolate (the background task) wrote; each
  /// isolate keeps its own cached copy.
  static Future<void> reload() => _p.reload();

  static bool has(String key) => _p.containsKey(key);

  static bool getBool(String key, bool def) => _p.getBool(key) ?? def;
  static void setBool(String key, bool v) => _p.setBool(key, v);

  static int getInt(String key, int def) => _p.getInt(key) ?? def;
  static void setInt(String key, int v) => _p.setInt(key, v);

  static String? getString(String key) => _p.getString(key);
  static void setString(String key, String v) => _p.setString(key, v);

  static List<String> getStringList(String key, List<String> def) =>
      _p.getStringList(key) ?? def;
  static Future<bool> setStringList(String key, List<String> v) =>
      _p.setStringList(key, v);
}
