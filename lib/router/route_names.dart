/// Route path constants for go_router navigation.
class AppRoutes {
  AppRoutes._();

  // Root routes
  static const about = '/about';
  static const onboarding = '/onboarding';

  // Tab routes (StatefulShellRoute branches)
  static const map = '/map';
  static const list = '/list';
  static const times = '/times';
  static const nearby = '/nearby';

  // Station detail (nested under the list branch)
  static String stationDetail(int id) => '/list/station/$id';
}
