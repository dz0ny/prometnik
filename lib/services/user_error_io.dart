import 'dart:io';

/// Network-level failures on platforms with dart:io (no route, DNS, TLS).
bool isNetworkError(Object e) =>
    e is SocketException || e is TlsException || e is HttpException;
