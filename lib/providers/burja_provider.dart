import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/burja_station.dart';
import '../services/burja_service.dart';
import 'feed.dart';

final burjaServiceProvider = Provider<BurjaService>((ref) => BurjaService());

/// Crosswind (burja) measurement points.
class BurjaFeed extends FeedNotifier<BurjaStation> {
  @override
  Duration get refreshInterval => const Duration(minutes: 5);

  @override
  Duration get staleAfter => const Duration(minutes: 3);

  @override
  Future<List<BurjaStation>> fetchItems() =>
      ref.read(burjaServiceProvider).fetch();
}

final burjaProvider = NotifierProvider<BurjaFeed, FeedState<BurjaStation>>(
  BurjaFeed.new,
);
