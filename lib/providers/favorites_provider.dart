import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/prefs.dart';

/// The user's favourite (priljubljene) station ids, persisted in Prefs.
class FavoritesNotifier extends Notifier<Set<int>> {
  static const String _key = 'favorite_station_ids';

  @override
  Set<int> build() => Set.unmodifiable(
    Prefs.getStringList(_key, const []).map(int.tryParse).whereType<int>(),
  );

  void toggle(int id) {
    final next = state.contains(id)
        ? state.difference({id})
        : state.union({id});
    // Persist first, then publish.
    Prefs.setStringList(_key, [for (final i in next) '$i']);
    state = Set.unmodifiable(next);
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, Set<int>>(
  FavoritesNotifier.new,
);
