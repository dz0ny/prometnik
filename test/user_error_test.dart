import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:promet/services/burja_service.dart';
import 'package:promet/services/drsi_service.dart';
import 'package:promet/services/events_service.dart';
import 'package:promet/services/location_service.dart';
import 'package:promet/services/user_error.dart';

void main() {
  group('userErrorMessage', () {
    test('connection failures', () {
      for (final e in <Object>[
        const SocketException('Failed host lookup: www.promet.si'),
        http.ClientException('Connection closed before full header'),
        TimeoutException('Future not completed', const Duration(seconds: 20)),
        const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
      ]) {
        expect(userErrorMessage(e), kErrorNoConnection, reason: '$e');
      }
      expect(kErrorNoConnection, 'Ni povezave z internetom. Poskusi znova.');
    });

    test('server status errors', () {
      expect(
        userErrorMessage(
          const EventsServiceException('Strežnik je vrnil napako 503.'),
        ),
        kErrorServer,
      );
      expect(
        userErrorMessage(
          const DrsiServiceException('Strežnik DRSI je vrnil napako 500.'),
        ),
        kErrorServer,
      );
      expect(
        kErrorServer,
        'Strežnik trenutno ne odgovarja. Poskusi znova kasneje.',
      );
    });

    test('parse / format errors', () {
      expect(
        userErrorMessage(const FormatException('Unexpected character')),
        kErrorParse,
      );
      expect(
        userErrorMessage(
          const BurjaServiceException('Nepričakovana oblika podatkov.'),
        ),
        kErrorParse,
      );
      expect(
        userErrorMessage(
          const BurjaServiceException(
            'Podatkov ni bilo mogoče prebrati: FormatException: x',
          ),
        ),
        kErrorParse,
      );
      expect(kErrorParse, 'Podatkov ni bilo mogoče prebrati.');
    });

    test('anything else is generic and never leaks the raw text', () {
      final msg = userErrorMessage(StateError('Bad state: secret detail'));
      expect(msg, kErrorGeneric);
      expect(msg, isNot(contains('secret')));
      expect(kErrorGeneric, 'Nekaj je šlo narobe. Poskusi znova.');
    });
  });

  test('LocationStatus messages', () {
    expect(LocationStatus.granted.message, isNull);
    expect(
      LocationStatus.deniedForever.message,
      'Dostop do lokacije je zavrnjen. Omogoči ga v nastavitvah.',
    );
    expect(LocationStatus.denied.message, LocationStatus.deniedForever.message);
    expect(
      LocationStatus.serviceDisabled.message,
      'Lokacijske storitve so izklopljene.',
    );
  });
}
