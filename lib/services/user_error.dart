import 'dart:async';

import 'package:http/http.dart' as http;

import 'user_error_io_stub.dart'
    if (dart.library.io) 'user_error_io.dart'
    as platform;

/// Marker for the exceptions thrown by the data services (`*ServiceException`).
/// Their [message] is Slovenian but technical (status codes, parser details),
/// so it is logged, not shown.
abstract interface class AppServiceException implements Exception {
  String get message;
}

const String kErrorNoConnection = 'Ni povezave z internetom. Poskusi znova.';
const String kErrorServer =
    'Strežnik trenutno ne odgovarja. Poskusi znova kasneje.';
const String kErrorParse = 'Podatkov ni bilo mogoče prebrati.';
const String kErrorGeneric = 'Nekaj je šlo narobe. Poskusi znova.';

final RegExp _statusCode = RegExp(r'napako \d{3}');

/// Maps any error from a data fetch to a short Slovenian message for the UI.
/// Log the raw error separately (debugPrint); never show `e.toString()`.
String userErrorMessage(Object e) {
  if (e is TimeoutException ||
      e is http.ClientException ||
      platform.isNetworkError(e)) {
    return kErrorNoConnection;
  }
  if (e is FormatException || e is TypeError) return kErrorParse;
  if (e is AppServiceException) {
    final m = e.message;
    if (_statusCode.hasMatch(m)) return kErrorServer;
    if (m.contains('ni bilo mogoče prebrati') ||
        m.contains('Nepričakovana oblika')) {
      return kErrorParse;
    }
    // e.g. "DRSI ni vrnil seje." — the server misbehaved.
    return kErrorServer;
  }
  return kErrorGeneric;
}
