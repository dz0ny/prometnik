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
}
