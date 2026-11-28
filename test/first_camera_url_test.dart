import 'package:flutter_test/flutter_test.dart';
import 'package:promet/models/weather_station.dart';

void main() {
  test('firstCameraUrl takes the first of several cameras', () {
    expect(
      firstCameraUrl('https://a/x.jpg;https://a/y.jpg'),
      'https://a/x.jpg',
    );
    expect(firstCameraUrl(' ;https://a/y.jpg'), 'https://a/y.jpg');
    expect(firstCameraUrl('https://a/x.jpg'), 'https://a/x.jpg');
    expect(firstCameraUrl(null), '');
    expect(firstCameraUrl(''), '');
    expect(cameraUrls('https://a/x.jpg; https://a/y.jpg;'), [
      'https://a/x.jpg',
      'https://a/y.jpg',
    ]);
  });
}
