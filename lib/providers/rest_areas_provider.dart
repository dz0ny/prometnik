import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rest_area.dart';
import '../services/rest_areas_service.dart';
import 'feed.dart';

final restAreasServiceProvider = Provider<RestAreasService>(
  (ref) => RestAreasService(),
);

/// Rest areas with live parking availability.
class RestAreasFeed extends FeedNotifier<RestArea> {
  @override
  Duration get refreshInterval => const Duration(minutes: 5);

  @override
  Duration get staleAfter => const Duration(minutes: 3);

  @override
  Future<List<RestArea>> fetchItems() =>
      ref.read(restAreasServiceProvider).fetch();
}

final restAreasProvider = NotifierProvider<RestAreasFeed, FeedState<RestArea>>(
  RestAreasFeed.new,
);
