import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/burja_provider.dart';
import '../providers/cameras_provider.dart';
import '../providers/events_provider.dart';
import '../providers/feed.dart';
import '../providers/rest_areas_provider.dart';
import '../providers/travel_times_provider.dart';
import '../providers/update_provider.dart';
import '../providers/weather_provider.dart';
import '../router/app_router.dart';
import '../router/navigation_notifier.dart';
import '../screens/about_screen.dart';
import 'update_banner.dart';

/// Main scaffold with bottom navigation for the app shell.
class MainScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _tabTapCount = 0;
  DateTime? _lastTabTap;

  @override
  void initState() {
    super.initState();
    // Android APK builds look for a newer GitHub release once per start.
    if (selfUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(updateProvider.notifier).check();
      });
    }
  }

  /// Cross-tab "show on map" requests: switch to the map tab, then focus.
  void _handleMapRequest(MapRequest? request) {
    if (request == null) return;
    widget.navigationShell.goBranch(0); // Switch to map tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final map = mapTabKey.currentState;
      switch (request) {
        case ShowStationOnMap(:final stationId):
          map?.focusStation(stationId);
        case ShowLocationOnMap(:final location):
          map?.focusLocation(location);
      }
      ref.read(mapRequestProvider.notifier).clear();
    });
  }

  void _handleTabTap(int index) {
    // Easter egg: 5 quick taps on the active tab open the about screen (it is
    // also listed in the map's filter sheet as "O aplikaciji").
    final now = DateTime.now();
    final quick =
        _lastTabTap != null &&
        now.difference(_lastTabTap!) < const Duration(seconds: 2);
    _lastTabTap = now;
    if (index == widget.navigationShell.currentIndex) {
      _tabTapCount = quick ? _tabTapCount + 1 : 1;
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
    for (final feed in <FeedNotifier<Object?>>[
      ref.read(weatherProvider.notifier),
      ref.read(eventsProvider.notifier),
      ref.read(camerasProvider.notifier),
      ref.read(restAreasProvider.notifier),
      ref.read(burjaProvider.notifier),
      ref.read(travelTimesProvider.notifier),
    ]) {
      unawaited(feed.refreshIfStale());
    }
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
    ref.listen(mapRequestProvider, (_, next) => _handleMapRequest(next));
    final index = widget.navigationShell.currentIndex;
    final cs = Theme.of(context).colorScheme;

    return AdaptiveScaffold(
      // Keep the iOS 26 native tab bar at full size (don't shrink on scroll).
      minimizeBehavior: TabBarMinimizeBehavior.never,
      body: selfUpdates
          ? Stack(
              // Scaffold gives the body loose constraints, and a loose Stack
              // takes the size of its non-positioned children: the banner's
              // SizedBox.shrink() when there is no update, which collapsed
              // the whole body to 0×0 (blank tabs on Android).
              fit: StackFit.expand,
              children: [
                Positioned.fill(child: widget.navigationShell),
                const UpdateBanner(),
              ],
            )
          : widget.navigationShell,
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
