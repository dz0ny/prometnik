import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/about_screen.dart';
import '../screens/list_tab.dart';
import '../screens/intro_wizard_screen.dart';
import '../screens/map_tab.dart';
import '../screens/nearby_tab.dart';
import '../screens/travel_times_tab.dart';
import '../screens/station_detail_screen.dart';
import '../widgets/main_scaffold.dart';
import 'route_names.dart';

/// Navigator keys for StatefulShellRoute branches.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorMapKey = GlobalKey<NavigatorState>(debugLabel: 'map');
final _shellNavigatorListKey = GlobalKey<NavigatorState>(debugLabel: 'list');
final _shellNavigatorTimesKey = GlobalKey<NavigatorState>(debugLabel: 'times');
final _shellNavigatorNearbyKey = GlobalKey<NavigatorState>(debugLabel: 'nearby');

/// Global key to access MapTabState for operations like focusing a station.
final mapTabKey = GlobalKey<MapTabState>();

/// Create the GoRouter configuration. When [showOnboarding] is true the app
/// starts on the intro wizard.
GoRouter createRouter({bool showOnboarding = false}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: showOnboarding ? AppRoutes.onboarding : AppRoutes.map,
    debugLogDiagnostics: false,
    routes: [
      // Onboarding wizard (full screen, outside shell)
      GoRoute(
        path: AppRoutes.onboarding,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const IntroWizardScreen(),
      ),

      // About screen (full screen, outside shell)
      GoRoute(
        path: AppRoutes.about,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AboutScreen(),
      ),

      // Main shell with tabs
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainScaffold(navigationShell: navigationShell);
        },
        branches: [
          // Map tab (index 0)
          StatefulShellBranch(
            navigatorKey: _shellNavigatorMapKey,
            routes: [
              GoRoute(
                path: AppRoutes.map,
                builder: (context, state) => MapTab(key: mapTabKey),
              ),
            ],
          ),

          // List tab (index 1)
          StatefulShellBranch(
            navigatorKey: _shellNavigatorListKey,
            routes: [
              GoRoute(
                path: AppRoutes.list,
                builder: (context, state) => const ListTab(),
                routes: [
                  GoRoute(
                    path: 'station/:id',
                    builder: (context, state) {
                      final id = int.parse(state.pathParameters['id']!);
                      return StationDetailScreen(stationId: id);
                    },
                  ),
                ],
              ),
            ],
          ),

          // Travel times tab
          StatefulShellBranch(
            navigatorKey: _shellNavigatorTimesKey,
            routes: [
              GoRoute(
                path: AppRoutes.times,
                builder: (context, state) => const TravelTimesTab(),
              ),
            ],
          ),

          // Nearby tab (index 4)
          StatefulShellBranch(
            navigatorKey: _shellNavigatorNearbyKey,
            routes: [
              GoRoute(
                path: AppRoutes.nearby,
                builder: (context, state) => const NearbyTab(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
