import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's favourite (priljubljene) station IDs in
/// SharedPreferences and exposes them reactively to the UI.
class FavoritesProvider extends ChangeNotifier {
  static const String _key = 'favorite_station_ids';

  final Set<int> _ids = {};
  SharedPreferences? _prefs;

  Set<int> get ids => Set.unmodifiable(_ids);
  bool get hasAny => _ids.isNotEmpty;
  int get count => _ids.length;

  bool isFavorite(int id) => _ids.contains(id);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs?.getStringList(_key) ?? const [];
    _ids
      ..clear()
      ..addAll(stored.map(int.tryParse).whereType<int>());
    notifyListeners();
  }

  Future<void> toggle(int id) async {
    if (!_ids.remove(id)) {
      _ids.add(id);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await _prefs?.setStringList(
      _key,
      _ids.map((e) => e.toString()).toList(growable: false),
    );
  }
}
