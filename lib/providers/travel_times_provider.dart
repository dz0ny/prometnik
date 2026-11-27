import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/travel_time.dart';
import '../services/travel_times_service.dart';
import 'feed.dart';

final travelTimesServiceProvider = Provider<TravelTimesService>(
  (ref) => TravelTimesService(),
);

/// Motorway travel times.
class TravelTimesFeed extends FeedNotifier<TravelTime> {
  @override
  Duration get refreshInterval => const Duration(minutes: 2);

  @override
  Duration get staleAfter => const Duration(minutes: 1);

  @override
  Future<List<TravelTime>> fetchItems() =>
      ref.read(travelTimesServiceProvider).fetchTravelTimes();
}

final travelTimesProvider =
    NotifierProvider<TravelTimesFeed, FeedState<TravelTime>>(
      TravelTimesFeed.new,
    );
