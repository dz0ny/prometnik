import 'package:flutter_test/flutter_test.dart';
import 'package:promet/models/traffic_event.dart';
import 'package:promet/screens/list_tab.dart' show compareSlovenian;
import 'package:promet/services/roads_service.dart';

Map<String, dynamic> _feature(
  Map<String, dynamic> props, {
  bool point = true,
}) => {
  'properties': props,
  'geometry': point
      ? {
          'type': 'Point',
          'coordinates': [14.5, 46.05],
        }
      : null,
};

void main() {
  group('TrafficEvent.fromFeature', () {
    test('offset timestamps are converted to local time', () {
      final e = TrafficEvent.fromFeature(
        _feature({'Id': 'x', 'Updated': '2026-11-26T20:53:39+01:00'}),
      );
      expect(e.updated!.isUtc, isFalse);
      expect(e.updated!.toUtc(), DateTime.utc(2026, 11, 26, 19, 53, 39));
    });

    test('non-string fields do not drop the record', () {
      final e = TrafficEvent.fromFeature(_feature({'Id': 42, 'Title': 7}));
      expect(e.id, '42');
      expect(e.title, '7');
    });

    test('events without geometry have no position', () {
      final e = TrafficEvent.fromFeature(_feature({'Id': 'x'}, point: false));
      expect(e.hasPosition, isFalse);
      final p = TrafficEvent.fromFeature(_feature({'Id': 'y'}));
      expect(p.hasPosition, isTrue);
    });
  });

  test('combined OSM refs match each road', () {
    expect(roadRefMatches(eventRoadRef('A1'), 'A1;A2'), isTrue);
    expect(roadRefMatches(eventRoadRef('A2'), 'A1;A2'), isTrue);
    expect(roadRefMatches(eventRoadRef('A3'), 'A1;A2'), isFalse);
  });

  test('Slovenian sort puts Č/Š/Ž after C/S/Z', () {
    final names = ['Žalec', 'Zagorje', 'Šentjur', 'Celje', 'Sežana', 'Črnomelj']
      ..sort(compareSlovenian);
    expect(names, [
      'Celje',
      'Črnomelj',
      'Sežana',
      'Šentjur',
      'Zagorje',
      'Žalec',
    ]);
  });
}
