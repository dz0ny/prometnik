import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:promet/models/traffic_camera.dart';
import 'package:promet/services/drsi_service.dart';
import 'package:promet/services/webcam_proxy.dart';

void main() {
  group('proxiedWebcamUrl', () {
    test('empty stays empty', () {
      expect(proxiedWebcamUrl(''), '');
      expect(proxiedWebcamUrl('', buster: 5), '');
    });

    test('allowed https host goes through the proxy', () {
      final url = proxiedWebcamUrl(
        'https://kamere.dars.si/kamere/a b/x.jpg',
        buster: 42,
      );
      final uri = Uri.parse(url);
      expect(uri.scheme, 'https');
      expect(uri.host, webcamProxyHost);
      expect(uri.path, '/cam');
      expect(
        uri.queryParameters['u'],
        'https://kamere.dars.si/kamere/a%20b/x.jpg',
      );
      expect(uri.queryParameters['t'], '42');
    });

    test('allowed http host is proxied over https', () {
      final url = proxiedWebcamUrl(
        'http://www.drsc.si/kamere/Miklavz/Mik1_0001.jpg',
        buster: 7,
      );
      expect(url, startsWith('https://$webcamProxyHost/cam?'));
      expect(
        Uri.parse(url).queryParameters['u'],
        'http://www.drsc.si/kamere/Miklavz/Mik1_0001.jpg',
      );
    });

    test('no buster means no t on the proxy URL', () {
      final uri = Uri.parse(
        proxiedWebcamUrl('https://meteo.arso.gov.si/cam.jpg'),
      );
      expect(uri.queryParameters.keys, ['u']);
    });

    test('other hosts pass through with the buster appended', () {
      expect(
        proxiedWebcamUrl('https://example.com/cam.jpg', buster: 1),
        'https://example.com/cam.jpg?t=1',
      );
      expect(
        proxiedWebcamUrl('https://example.com/cam.jpg?a=1', buster: 1),
        'https://example.com/cam.jpg?a=1&t=1',
      );
      expect(
        proxiedWebcamUrl('https://example.com/cam.jpg'),
        'https://example.com/cam.jpg',
      );
    });

    test('existing t param is stripped from the camera URL', () {
      final uri = Uri.parse(
        proxiedWebcamUrl(
          'https://kamere.dars.si/x.jpg?t=old&size=big&t=older#frag',
          buster: 9,
        ),
      );
      expect(uri.queryParameters['u'], 'https://kamere.dars.si/x.jpg?size=big');
      expect(uri.queryParameters['t'], '9');

      final only = Uri.parse(
        proxiedWebcamUrl('https://drsc.si/x.jpg?t=old', buster: 9),
      );
      expect(only.queryParameters['u'], 'https://drsc.si/x.jpg');
    });
  });

  test('TrafficCamera and DrsiStation use the proxy', () {
    const cam = TrafficCamera(
      id: '1',
      title: 'T',
      description: '',
      region: '',
      imageUrl: 'https://kamere.dars.si/kamere/x.jpg',
      position: LatLng(46, 14),
    );
    expect(cam.imageUrlWithBuster(3), startsWith('https://$webcamProxyHost/'));
    expect(
      const TrafficCamera(
        id: '1',
        title: 'T',
        description: '',
        region: '',
        imageUrl: '',
        position: LatLng(46, 14),
      ).imageUrlWithBuster(3),
      '',
    );
  });

  test('DrsiStation camera URL uses the proxy', () {
    final stations = parseDrsiTable(
      File('test/fixtures/drsi_current.json').readAsStringSync(),
    );
    final kranj = stations.firstWhere((s) => s.id == '1');
    final uri = Uri.parse(kranj.cameraUrlWithBuster(5));
    expect(uri.host, webcamProxyHost);
    expect(uri.queryParameters['u'], kranj.webcamUrl);
    expect(uri.queryParameters['t'], '5');
  });
}
