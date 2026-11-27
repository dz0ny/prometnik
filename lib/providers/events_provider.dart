import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/traffic_event.dart';
import '../services/events_service.dart';
import 'feed.dart';

final eventsServiceProvider = Provider<EventsService>((ref) => EventsService());

/// Traffic events from promet.si (its data channel caches for ~60 s).
class EventsFeed extends FeedNotifier<TrafficEvent> {
  @override
  Duration get refreshInterval => const Duration(minutes: 2);

  @override
  Duration get staleAfter => const Duration(minutes: 1);

  @override
  Future<List<TrafficEvent>> fetchItems() =>
      ref.read(eventsServiceProvider).fetchEvents();
}

final eventsProvider = NotifierProvider<EventsFeed, FeedState<TrafficEvent>>(
  EventsFeed.new,
);

/// Lookups on the events feed.
extension TrafficEvents on FeedState<TrafficEvent> {
  TrafficEvent? byId(String id) {
    for (final e in items) {
      if (e.id == id) return e;
    }
    return null;
  }
}
