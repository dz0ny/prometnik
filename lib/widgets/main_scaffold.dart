import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/burja_provider.dart';
import '../providers/cameras_provider.dart';
import '../providers/events_provider.dart';
import '../providers/rest_areas_provider.dart';
import '../providers/travel_times_provider.dart';
import '../providers/weather_provider.dart';
import '../router/app_router.dart';
import '../router/navigation_notifier.dart';
import '../screens/about_screen.dart';

/// Main scaffold with bottom navigation for the app shell.
class MainScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _tabTapCount = 0;
  NavigationNotifier? _navNotifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = context.read<NavigationNotifier>();
    if (!identical(_navNotifier, notifier)) {
      _navNotifier?.removeListener(_handlePendingNavigation);
      _navNotifier = notifier;
      _navNotifier?.addListener(_handlePendingNavigation);
    }
  }

  @override
  void dispose() {
    _navNotifier?.removeListener(_handlePendingNavigation);
    super.dispose();
  }

  void _handlePendingNavigation() {
    final navNotifier = context.read<NavigationNotifier>();
    final stationId = navNotifier.pendingStationOnMap;
    if (stationId != null) {
      widget.navigationShell.goBranch(0); // Switch to map tab
      WidgetsBinding.instance.addPostFrameCallback((_) {
        mapTabKey.currentState?.focusStation(stationId);
        navNotifier.clearPendingStation();
      });
    }
    final location = navNotifier.pendingLocationOnMap;
    if (location != null) {
      widget.navigationShell.goBranch(0); // Switch to map tab
      WidgetsBinding.instance.addPostFrameCallback((_) {
        mapTabKey.currentState?.focusLocation(location);
        navNotifier.clearPendingLocation();
      });
    }
  }

  void _handleTabTap(int index) {
    // 5 consecutive taps on the active tab opens the about screen.
    if (index == widget.navigationShell.currentIndex) {
      _tabTapCount++;
      if (_tabTapCount >= 5) {
        _tabTapCount = 0;
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const AboutScreen()),
        );
      }
    } else {
      _tabTapCount = 0;
    }

    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );

    // Pick up fresh data when switching tabs if it's stale.
    context.read<WeatherProvider>().refreshIfStale();
    context.read<EventsProvider>().refreshIfStale();
    context.read<CamerasProvider>().refreshIfStale();
    context.read<RestAreasProvider>().refreshIfStale();
    context.read<BurjaProvider>().refreshIfStale();
    context.read<TravelTimesProvider>().refreshIfStale();
  }

  /// Builds a destination using native SF Symbols on iOS and Material icons on
  /// Android. [icon]/[selectedIcon] are SF Symbol names; the Material icons are
  /// the platform fallback.
  AdaptiveNavigationDestination _dest({
    required String label,
    required String iosSymbol,
    required String iosSelectedSymbol,
    required IconData icon,
    required IconData selectedIcon,
  }) {
    final isIOS = PlatformInfo.isIOS;
    return AdaptiveNavigationDestination(
      icon: isIOS ? iosSymbol : icon,
      selectedIcon: isIOS ? iosSelectedSymbol : selectedIcon,
      label: label,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<NavigationNotifier>();
    final index = widget.navigationShell.currentIndex;
    final cs = Theme.of(context).colorScheme;

    return AdaptiveScaffold(
      // Keep the iOS 26 native tab bar at full size (don't shrink on scroll).
      minimizeBehavior: TabBarMinimizeBehavior.never,
      body: widget.navigationShell,
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: index,
        onTap: _handleTabTap,
        selectedItemColor: PlatformInfo.isIOS ? cs.primary : null,
        unselectedItemColor: PlatformInfo.isIOS ? cs.onSurfaceVariant : null,
        items: [
          _dest(
            label: 'Karta',
            iosSymbol: 'map',
            iosSelectedSymbol: 'map.fill',
            icon: Icons.map_outlined,
            selectedIcon: Icons.map,
          ),
          _dest(
            label: 'Kamere',
            iosSymbol: 'video',
            iosSelectedSymbol: 'video.fill',
            icon: Icons.videocam_outlined,
            selectedIcon: Icons.videocam,
          ),
          _dest(
            label: 'Časi',
            iosSymbol: 'clock',
            iosSelectedSymbol: 'clock.fill',
            icon: Icons.timer_outlined,
            selectedIcon: Icons.timer,
          ),
          _dest(
            label: 'Bližina',
            iosSymbol: 'location',
            iosSelectedSymbol: 'location.fill',
            icon: Icons.near_me_outlined,
            selectedIcon: Icons.near_me,
          ),
        ],
      ),
    );
  }
}
