import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/user_error.dart';

/// Immutable snapshot of a polled data feed.
///
/// [items] keeps its identity until new data arrives, so widgets can memoize
/// derived lists on it and `select` on it without spurious rebuilds.
@immutable
class FeedState<T> {
  final List<T> items;
  final bool isLoading;

  /// User-facing (Slovenian) message of the last failed refresh, or null.
  final String? error;
  final DateTime? lastUpdated;

  const FeedState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.lastUpdated,
  });

  bool get hasData => items.isNotEmpty;

  FeedState<T> copyWith({bool? isLoading, String? error}) => FeedState<T>(
    items: items,
    isLoading: isLoading ?? this.isLoading,
    error: error ?? this.error,
    lastUpdated: lastUpdated,
  );

  @override
  bool operator ==(Object other) =>
      other is FeedState<T> &&
      identical(other.items, items) &&
      other.isLoading == isLoading &&
      other.error == error &&
      other.lastUpdated == lastUpdated;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(items), isLoading, error, lastUpdated);
}

/// A feed that loads on first read and then polls every [refreshInterval].
///
/// The app pauses polling in the background ([stop]) and resumes it on
/// foreground ([start]); tabs call [refreshIfStale] when they appear.
abstract class FeedNotifier<T> extends Notifier<FeedState<T>> {
  Duration get refreshInterval;
  Duration get staleAfter;

  /// Loads the current items; throws on failure.
  Future<List<T>> fetchItems();

  /// False on platforms where the source can't be reached (e.g. web).
  bool get enabled => true;

  Timer? _timer;
  bool _loading = false;

  @override
  FeedState<T> build() {
    ref.onDispose(() => _timer?.cancel());
    if (!enabled) return FeedState<T>();
    // Start after build returns: state can't be assigned during build.
    scheduleMicrotask(start);
    return FeedState<T>(isLoading: true);
  }

  /// Load now and keep polling.
  void start() {
    if (!enabled || !ref.mounted) return;
    unawaited(refresh());
    _timer ??= Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
  }

  /// Stop polling (app backgrounded). [start] resumes and refreshes.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Refresh only if the data is missing or older than [maxAge].
  Future<void> refreshIfStale([Duration? maxAge]) {
    final updated = state.lastUpdated;
    if (updated == null ||
        DateTime.now().difference(updated) > (maxAge ?? staleAfter)) {
      return refresh();
    }
    return Future.value();
  }

  Future<void> refresh() async {
    if (_loading || !enabled) return;
    _loading = true;
    if (!state.hasData && !state.isLoading) {
      state = state.copyWith(isLoading: true);
    }
    try {
      final items = UnmodifiableListView<T>(await fetchItems());
      if (!ref.mounted) return;
      state = FeedState<T>(items: items, lastUpdated: DateTime.now());
    } on Exception catch (e) {
      debugPrint('$runtimeType.refresh error: $e');
      if (!ref.mounted) return;
      state = FeedState<T>(
        items: state.items,
        error: userErrorMessage(e),
        lastUpdated: state.lastUpdated,
      );
    } finally {
      _loading = false;
    }
  }
}
