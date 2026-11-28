import 'package:flutter_test/flutter_test.dart';
import 'package:promet/services/webcam_proxy.dart';
import 'package:promet/services/webcam_store.dart';

void main() {
  const cam = 'https://kamere.dars.si/kamere/x/Cam_0001.jpg';

  test('proxied and direct URLs of a camera share one identity', () {
    final proxied = proxiedWebcamUrl(cam, buster: 123);
    expect(cameraKey(proxied), cam);
    expect(cameraKey(proxiedWebcamUrl(cam, buster: 456)), cam);
    expect(cameraKey('$cam?t=99'), cam);
    expect(cameraKey(cam), cam);
  });

  test('other query params are kept in the identity', () {
    expect(
      cameraKey('https://example.com/cam.jpg?id=7&t=5'),
      'https://example.com/cam.jpg?id=7',
    );
  });

  test('hourly keys bucket by local hour', () {
    final a = hourlyKey(cam, DateTime(2026, 11, 26, 21, 5));
    final b = hourlyKey(cam, DateTime(2026, 11, 26, 21, 59));
    final c = hourlyKey(cam, DateTime(2026, 11, 26, 22, 0));
    expect(a, b);
    expect(a, isNot(c));
    expect(a, endsWith('2026112621'));
    expect(latestKey(cam), isNot(a));
  });

  test(
    'proxied URLs fall back to the camera itself, others have no fallback',
    () {
      final proxied = proxiedWebcamUrl(cam, buster: 1);
      expect(directWebcamUrl(proxied, buster: 7), '$cam?t=7');
      expect(directWebcamUrl('$cam?t=1'), isNull);
      expect(directWebcamUrl('https://example.com/a.jpg'), isNull);
    },
  );

  test('frames are dated by the proxy capture time when given', () {
    final at = frameTakenAt({'x-cam-at': '2026-11-27T07:15:57.000Z'});
    expect(at, DateTime.utc(2026, 11, 27, 7, 15, 57).toLocal());
    expect(at!.isUtc, isFalse);
    expect(frameTakenAt({}), isNull);
    expect(frameTakenAt({'x-cam-at': 'nope'}), isNull);
    final future = DateTime.now().add(const Duration(hours: 2));
    expect(
      frameTakenAt({'x-cam-at': future.toUtc().toIso8601String()}),
      isNull,
    );
  });

  test('isOldProxyFrame: only a dated frame older than 10 minutes', () {
    final now = DateTime(2026, 11, 28, 9);
    expect(isOldProxyFrame(null, now), isFalse);
    expect(
      isOldProxyFrame(now.subtract(const Duration(minutes: 9)), now),
      isFalse,
    );
    expect(
      isOldProxyFrame(now.subtract(const Duration(hours: 8)), now),
      isTrue,
    );
  });
}
