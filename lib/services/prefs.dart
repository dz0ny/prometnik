import 'package:shared_preferences/shared_preferences.dart';

/// Tiny synchronous wrapper around SharedPreferences for persisting UI state
/// (filters). Call [init] once at startup before reading.
class Prefs {
  Prefs._();

  static late final SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static bool has(String key) => _p.containsKey(key);

  static bool getBool(String key, bool def) => _p.getBool(key) ?? def;
  static void setBool(String key, bool v) => _p.setBool(key, v);

  static int getInt(String key, int def) => _p.getInt(key) ?? def;
  static void setInt(String key, int v) => _p.setInt(key, v);

  static List<String> getStringList(String key, List<String> def) =>
      _p.getStringList(key) ?? def;
  static void setStringList(String key, List<String> v) =>
      _p.setStringList(key, v);
}
