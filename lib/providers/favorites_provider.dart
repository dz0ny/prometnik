import 'package:flutter/foundation.dart';
import '../services/prefs.dart';

/// Persists the user's favourite (priljubljene) station IDs in
/// SharedPreferences and exposes them reactively to the UI.
///
/// Reads synchronously through [Prefs] (initialised before runApp), so the
/// favourites are already there the first time a screen reads this provider.
/// An async load used to land after the list screen had decided its default
/// filter, which overwrote the user's saved "only favourites" choice.
class FavoritesProvider extends ChangeNotifier {
  static const String _key = 'favorite_station_ids';

  final Set<int> _ids = {};

  Set<int> get ids => Set.unmodifiable(_ids);
  bool get hasAny => _ids.isNotEmpty;
  int get count => _ids.length;

  bool isFavorite(int id) => _ids.contains(id);

  void load() {
    final stored = Prefs.getStringList(_key, const []);
    _ids
      ..clear()
      ..addAll(stored.map(int.tryParse).whereType<int>());
  }

  void toggle(int id) {
    if (!_ids.remove(id)) {
      _ids.add(id);
    }
    notifyListeners();
    Prefs.setStringList(
      _key,
      _ids.map((e) => e.toString()).toList(growable: false),
    );
  }
}
