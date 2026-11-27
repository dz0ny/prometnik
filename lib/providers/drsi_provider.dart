import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/drsi_station.dart';
import '../services/drsi_service.dart';
import 'feed.dart';

final drsiServiceProvider = Provider<DrsiService>((ref) => DrsiService());

/// DRSI road weather stations (stations report every ~5 minutes).
class DrsiFeed extends FeedNotifier<DrsiStation> {
  @override
  Duration get refreshInterval => const Duration(minutes: 5);

  @override
  Duration get staleAfter => const Duration(minutes: 3);

  @override
  bool get enabled => DrsiService.isSupported;

  @override
  Future<List<DrsiStation>> fetchItems() =>
      ref.read(drsiServiceProvider).fetch();
}

final drsiProvider = NotifierProvider<DrsiFeed, FeedState<DrsiStation>>(
  DrsiFeed.new,
);
