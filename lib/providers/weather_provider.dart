import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weather_station.dart';
import '../services/weather_service.dart';
import 'feed.dart';

final weatherServiceProvider = Provider<WeatherService>(
  (ref) => WeatherService(),
);

/// Weather/camera stations from ceste.si, polled every 10 minutes like the official web app.
class WeatherFeed extends FeedNotifier<WeatherStation> {
  @override
  Duration get refreshInterval => const Duration(minutes: 10);

  @override
  Duration get staleAfter => const Duration(minutes: 5);

  @override
  Future<List<WeatherStation>> fetchItems() =>
      ref.read(weatherServiceProvider).fetchStations();
}

final weatherProvider =
    NotifierProvider<WeatherFeed, FeedState<WeatherStation>>(WeatherFeed.new);

/// Lookups on the stations feed.
extension WeatherStations on FeedState<WeatherStation> {
  WeatherStation? byId(int id) {
    for (final s in items) {
      if (s.stationId == id) return s;
    }
    return null;
  }
}
