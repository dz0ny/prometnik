import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:promet/routing/route_check.dart';
import 'package:promet/routing/route_warnings.dart';
import 'package:promet/routing/saved_route.dart';

SavedRoute route({Set<int> days = const {1, 2, 3, 4, 5}, int? dep = 450}) =>
    SavedRoute(
      id: 'r',
      name: 'Služba',
      places: const [
        RoutePlace('Vrhnika', LatLng(45.96, 14.29)),
        RoutePlace('Ljubljana', LatLng(46.05, 14.5)),
      ],
      points: const [LatLng(45.96, 14.29), LatLng(46.05, 14.5)],
      roadRefs: const ['A1'],
      meters: 20000,
      seconds: 1200,
      days: days,
      departureMinutes: dep,
    );

RouteWarning w(String id, int severity, {bool opposite = false}) =>
    RouteWarning(
      id: id,
      kind: RouteWarningKind.jam,
      severity: severity,
      title: 'Zastoj $id',
      detail: '',
      position: null,
      along: 0,
      opposite: opposite,
    );

void main() {
  // Monday 30 Nov 2026.
  final before = DateTime(2026, 11, 30, 7);

  test('nothing outside the hour before departure', () {
    expect(
      routeNotices(
        [route()],
        {
          'r': [w('a', 3)],
        },
        DateTime(2026, 11, 30, 6),
        {},
      ),
      isEmpty,
    );
    // Saturday: not a travel day.
    expect(
      routeNotices(
        [route()],
        {
          'r': [w('a', 3)],
        },
        DateTime(2026, 11, 28, 7),
        {},
      ),
      isEmpty,
    );
  });

  test('a summary first, then only new serious warnings', () {
    final first = routeNotices(
      [route()],
      {
        'r': [w('a', 3), w('b', 1), w('back', 3, opposite: true)],
      },
      before,
      {},
    );
    final shown = first.where((n) => n.title.isNotEmpty).toList();
    expect(shown, hasLength(1));
    expect(shown.single.title, 'Služba: 2 opozorili pred odhodom ob 07:30');
    final sent = first.map((n) => n.key).toSet();

    final later = routeNotices(
      [route()],
      {
        'r': [w('a', 3), w('b', 1), w('c', 1), w('d', 2)],
      },
      before.add(const Duration(minutes: 15)),
      sent,
    );
    expect(later.map((n) => n.title), ['Služba: Zastoj d']);
  });

  test('warningCount uses Slovenian plurals', () {
    expect(warningCount(1), '1 opozorilo');
    expect(warningCount(2), '2 opozorili');
    expect(warningCount(4), '4 opozorila');
    expect(warningCount(5), '5 opozoril');
    expect(warningCount(101), '101 opozorilo');
  });
}
