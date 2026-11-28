import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:promet/models/traffic_camera.dart';
import 'package:promet/providers/cameras_provider.dart';

TrafficCamera cam(String image, {String title = '', String desc = ''}) =>
    TrafficCamera(
      id: image,
      title: title,
      description: desc,
      region: '',
      imageUrl: image,
      position: const LatLng(46, 14.5),
    );

void main() {
  test('cameraShortLabel: last part of the description, else the title', () {
    expect(
      cameraShortLabel(
        cam('a', desc: 'R1-202, Rateče - Podkoren, pogled proti Planici'),
      ),
      'pogled proti Planici',
    );
    expect(cameraShortLabel(cam('a', title: 'Rateče')), 'Rateče');
    expect(cameraShortLabel(cam('a')), isNull);
    expect(cameraShortLabel(null), isNull);
  });

  test('cameraForImage matches the picture regardless of scheme', () {
    final list = [
      cam('http://kamere.dars.si/k/A_0001.jpg', title: 'A'),
      cam('https://kamere.dars.si/k/B_0001.jpg', title: 'B'),
    ];
    expect(
      cameraForImage(list, 'https://kamere.dars.si/k/A_0001.jpg')?.title,
      'A',
    );
    expect(cameraForImage(list, 'https://kamere.dars.si/k/C.jpg'), isNull);
  });
}
