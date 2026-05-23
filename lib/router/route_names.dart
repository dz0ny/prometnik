/// Route path constants for go_router navigation.
class AppRoutes {
  AppRoutes._();

  // Root routes
  static const about = '/about';

  // Tab routes (StatefulShellRoute branches)
  static const map = '/map';
  static const list = '/list';
  static const events = '/events';
  static const times = '/times';

  // Station detail (nested under the list branch)
  static String stationDetail(int id) => '/list/station/$id';
}
