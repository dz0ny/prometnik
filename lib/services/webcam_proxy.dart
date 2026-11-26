/// Routes webcam images through the Prometnik Cloudflare edge cache.
///
/// The worker (see worker/src/index.js) keeps each camera frame for about a
/// minute per Cloudflare location, serves plain-http cameras over https and
/// sends open CORS headers, so the web build can show them too.
library;

/// Edge cache endpoint: `GET /cam?u=<camera URL>[&t=<buster>]`.
const String webcamProxyHost = 'prometnik-cams.dz0ny.workers.dev';
const String webcamProxyPath = '/cam';

/// Camera hosts the worker accepts; anything else gets a 400 there.
///
/// Keep in sync with `ALLOWED_HOSTS` in worker/src/index.js.
const Set<String> webcamProxyHosts = {
  'kamere.dars.si',
  'www.drsc.si',
  'drsc.si',
  'meteo.arso.gov.si',
};

/// The URL to load the webcam image [original] from.
///
/// Known camera hosts go through the edge cache, with any `t` query param
/// removed from the camera URL and [buster] passed as the proxy's own `t`.
/// Other hosts load directly, with `t=[buster]` appended. Empty stays empty.
String proxiedWebcamUrl(String original, {int? buster}) {
  if (original.isEmpty) return original;
  final uri = Uri.tryParse(original);
  final proxied =
      uri != null &&
      (uri.isScheme('https') || uri.isScheme('http')) &&
      webcamProxyHosts.contains(uri.host.toLowerCase());
  if (!proxied) {
    if (buster == null) return original;
    final sep = original.contains('?') ? '&' : '?';
    return '$original${sep}t=$buster';
  }
  return Uri.https(webcamProxyHost, webcamProxyPath, {
    'u': _withoutBuster(uri),
    if (buster != null) 't': '$buster',
  }).toString();
}

/// [uri] without its `t` query params and fragment, other params kept as-is.
String _withoutBuster(Uri uri) {
  final kept = uri.query
      .split('&')
      .where((p) => p.isNotEmpty && _paramName(p) != 't')
      .join('&');
  final base = uri.removeFragment().replace(query: '').toString();
  final path = base.endsWith('?') ? base.substring(0, base.length - 1) : base;
  return kept.isEmpty ? path : '$path?$kept';
}

String _paramName(String pair) {
  final name = pair.split('=').first;
  try {
    return Uri.decodeQueryComponent(name);
  } on FormatException {
    return name;
  }
}
