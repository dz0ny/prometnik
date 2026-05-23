/// Configuration for the Slovenian National Access Point (NAP) open-data API
/// (https://b2b.nap.si), which serves traffic events, roadworks, etc. as
/// GeoJSON behind HTTP Basic auth.
///
/// Credentials are supplied at build/run time via --dart-define so they are
/// never committed to source control:
///
///   flutter run \
///     --dart-define=NAP_USERNAME=your_user \
///     --dart-define=NAP_PASSWORD=your_pass
///
/// Optionally override the events endpoint:
///   --dart-define=NAP_EVENTS_URL=https://b2b.nap.si/data/b2b.dogodki.geojson.sl_SI
class NapConfig {
  NapConfig._();

  static const String username = String.fromEnvironment('NAP_USERNAME');
  static const String password = String.fromEnvironment('NAP_PASSWORD');

  /// Events ("dogodki") feed as GeoJSON. Override via --dart-define if needed.
  static const String eventsUrl = String.fromEnvironment(
    'NAP_EVENTS_URL',
    defaultValue: 'https://b2b.nap.si/data/b2b.dogodki.geojson.sl_SI',
  );

  /// Whether credentials were provided. When false, the traffic feature is
  /// hidden / shows a "not configured" state instead of failing.
  static bool get isConfigured => username.isNotEmpty && password.isNotEmpty;
}
