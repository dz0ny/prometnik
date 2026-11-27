import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:promet/services/webcam_store.dart';

void main() {
  group('parseServerHistory', () {
    test('parses frames oldest first as UTC instants', () {
      final list = parseServerHistory('''
        {"camera": "https://kamere.dars.si/x.jpg", "frames": [
          {"at": "2026-11-26T20:00:00Z", "url": "https://prometnik-cams.dz0ny.workers.dev/snap?k=a"},
          {"at": "2026-11-26T21:00:00Z", "url": "https://prometnik-cams.dz0ny.workers.dev/snap?k=b"}
        ]}''');
      expect(list, hasLength(2));
      expect(list[0].at, DateTime.utc(2026, 11, 26, 20));
      expect(list[0].at.isUtc, isTrue);
      expect(list[1].url, endsWith('k=b'));
    });

    test('bad or unexpected bodies give an empty list', () {
      expect(parseServerHistory(''), isEmpty);
      expect(parseServerHistory('not json'), isEmpty);
      expect(parseServerHistory('<html>404</html>'), isEmpty);
      expect(parseServerHistory('[]'), isEmpty);
      expect(parseServerHistory('{"frames": []}'), isEmpty);
      expect(parseServerHistory('{"frames": "x"}'), isEmpty);
      expect(parseServerHistory('{}'), isEmpty);
    });

    test('malformed entries are skipped', () {
      final list = parseServerHistory('''
        {"frames": [
          {"at": "nope", "url": "https://a/snap?k=1"},
          {"at": "2026-11-26T21:00:00Z"},
          {"at": "2026-11-26T21:00:00Z", "url": "javascript:alert(1)"},
          {"at": 5, "url": "https://a/snap?k=2"},
          "x",
          {"at": "2026-11-26T22:00:00Z", "url": "https://a/snap?k=3"}
        ]}''');
      expect(list.map((s) => s.url), ['https://a/snap?k=3']);
    });
  });

  group('mergeWebcamHistory', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final now = DateTime(2026, 11, 26, 22, 30); // local
    DateTime localHour(int hoursAgo) {
      final t = now.subtract(Duration(hours: hoursAgo));
      return DateTime(t.year, t.month, t.day, t.hour);
    }

    ServerSnapshot server(int hoursAgo, String k) =>
        ServerSnapshot(localHour(hoursAgo).toUtc(), 'https://w/snap?k=$k');

    test('server only, sorted oldest first, times local', () {
      final out = mergeWebcamHistory(const [], [
        server(1, 'b'),
        server(3, 'a'),
      ], now: now);
      expect(out.map((e) => e.url), [
        'https://w/snap?k=a',
        'https://w/snap?k=b',
      ]);
      expect(out.first.at, localHour(3));
      expect(out.first.at.isUtc, isFalse);
      expect(out.first.isLocal, isFalse);
    });

    test('the worker snapshot wins for an hour both have', () {
      final out = mergeWebcamHistory(
        [WebcamFrame(bytes, localHour(1)), WebcamFrame(bytes, localHour(3))],
        [server(1, 'x'), server(2, 'y')],
        now: now,
      );
      expect(out, hasLength(3));
      expect(out[0].isLocal, isTrue);
      expect(out[0].frame!.at, localHour(3));
      expect(out[1].url, 'https://w/snap?k=y');
      expect(out[2].url, 'https://w/snap?k=x');
      expect(out[2].isLocal, isFalse);
    });

    test('only the last 24 hours, nothing from the future', () {
      final out = mergeWebcamHistory(
        [WebcamFrame(bytes, localHour(30))],
        [
          server(24, 'old'),
          server(23, 'first'),
          server(0, 'current'),
          ServerSnapshot(
            localHour(0).add(const Duration(hours: 1)).toUtc(),
            'https://w/snap?k=future',
          ),
        ],
        now: now,
      );
      expect(out.map((e) => e.url), [
        'https://w/snap?k=first',
        'https://w/snap?k=current',
      ]);
    });

    test('a non-zero minute on the server still matches its hour', () {
      final out = mergeWebcamHistory(
        [WebcamFrame(bytes, localHour(2))],
        [
          ServerSnapshot(
            localHour(2).add(const Duration(minutes: 7)).toUtc(),
            'https://w/snap?k=z',
          ),
        ],
        now: now,
      );
      expect(out, hasLength(1));
      expect(out.single.url, 'https://w/snap?k=z');
    });
  });
}
