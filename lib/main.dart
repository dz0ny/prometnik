import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'providers/alerts_controller.dart';
import 'providers/burja_provider.dart';
import 'providers/feed.dart';
import 'providers/drsi_provider.dart';
import 'providers/cameras_provider.dart';
import 'providers/events_provider.dart';
import 'providers/rest_areas_provider.dart';
import 'providers/travel_times_provider.dart';
import 'providers/weather_provider.dart';
import 'router/app_router.dart';
import 'screens/intro_wizard_screen.dart';
import 'services/map_tile_cache_service.dart';
import 'routing/route_check.dart';
import 'services/prefs.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  await MapTileCacheService.instance.initialize();
  unawaited(_scheduleRouteChecks());
  // The composition root: every provider lives in this one scope.
  runApp(const ProviderScope(child: PrometApp()));
}

/// Background check of saved routes before their departure (Android about
/// every 15 minutes; iOS when the system allows background refresh).
Future<void> _scheduleRouteChecks() async {
  if (kIsWeb ||
      !(defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return;
  }
  try {
    await Workmanager().initialize(routeCheckDispatcher);
    await Workmanager().registerPeriodicTask(
      routeCheckTask,
      routeCheckTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } on Exception catch (e) {
    debugPrint('route checks not scheduled: $e');
  }
  // And now, in case a departure is close.
  await runRouteCheck().catchError((Object e) {
    debugPrint('route check failed: $e');
  });
}

/// Entry point of the background task (its own isolate).
@pragma('vm:entry-point')
void routeCheckDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Prefs.init();
      await runRouteCheck();
    } on Object catch (e) {
      debugPrint('background route check failed: $e');
    }
    return true;
  });
}

class PrometApp extends StatefulWidget {
  const PrometApp({super.key});

  @override
  State<PrometApp> createState() => _PrometAppState();
}

class _PrometAppState extends State<PrometApp> {
  late final GoRouterHolder _routerHolder;

  @override
  void initState() {
    super.initState();
    _routerHolder = GoRouterHolder();
  }

  @override
  void dispose() {
    _routerHolder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AppServices(
      child: _PollingLifecycle(
        child: AdaptiveApp.router(
          title: 'Prometnik',
          themeMode: ThemeMode.system,
          materialLightTheme: AppTheme.lightTheme,
          materialDarkTheme: AppTheme.darkTheme,
          cupertinoLightTheme: AppTheme.cupertinoLight,
          cupertinoDarkTheme: AppTheme.cupertinoDark,
          // CupertinoApp (used on iOS) provides neither a Material [Theme] nor
          // [MaterialLocalizations]. Add the Material/Cupertino delegates and a
          // root Material + Theme so body widgets that still rely on Material
          // (RefreshIndicator, chips, modal sheets, Theme.of colours) keep
          // working and pick up our palette on every platform.
          localizationsDelegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultCupertinoLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          builder: (context, child) {
            final theme = AppTheme.materialFor(
              MediaQuery.platformBrightnessOf(context),
            );
            return Theme(
              data: theme,
              child: Material(
                type: MaterialType.transparency,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          routerConfig: _routerHolder.router,
        ),
      ),
    );
  }
}

/// Pauses data polling while the app is in the background (saves data and
/// battery). Events and travel times keep polling only when the user watches
/// something, so watched-road / route alerts can still fire.
class _PollingLifecycle extends ConsumerStatefulWidget {
  final Widget child;
  const _PollingLifecycle({required this.child});

  @override
  ConsumerState<_PollingLifecycle> createState() => _PollingLifecycleState();
}

class _PollingLifecycleState extends ConsumerState<_PollingLifecycle> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onPause: _pause, onResume: _resume);
  }

  /// Every polled feed, for pausing/resuming together.
  List<FeedNotifier<Object?>> get _feeds => [
    ref.read(weatherProvider.notifier),
    ref.read(camerasProvider.notifier),
    ref.read(restAreasProvider.notifier),
    ref.read(burjaProvider.notifier),
    ref.read(drsiProvider.notifier),
    ref.read(eventsProvider.notifier),
    ref.read(travelTimesProvider.notifier),
  ];

  void _pause() {
    final alerts = ref.read(alertsProvider);
    for (final feed in _feeds) {
      // Events and travel times keep polling while something is watched.
      if (feed is EventsFeed && alerts.hasWatched) continue;
      if (feed is TravelTimesFeed && alerts.watchedTravelTimes.isNotEmpty) {
        continue;
      }
      feed.stop();
    }
  }

  void _resume() {
    unawaited(
      runRouteCheck().catchError((Object e) {
        debugPrint('route check failed: $e');
      }),
    );
    // start() refreshes immediately and re-arms the timer (no-op if running).
    for (final feed in _feeds) {
      feed.start();
    }
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Starts the long-lived services eagerly (Riverpod providers are lazy): the
/// feeds begin polling and alerts begin listening at app start, not when a
/// screen first reads them.
class _AppServices extends ConsumerWidget {
  final Widget child;
  const _AppServices({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref
      ..watch(alertsProvider.select((_) => null))
      ..watch(weatherProvider.select((_) => null))
      ..watch(camerasProvider.select((_) => null))
      ..watch(restAreasProvider.select((_) => null))
      ..watch(burjaProvider.select((_) => null))
      ..watch(drsiProvider.select((_) => null));
    return child;
  }
}

/// Holds the GoRouter so it survives rebuilds and is disposed cleanly.
class GoRouterHolder {
  final router = createRouter(showOnboarding: IntroWizardScreen.shouldShow());
  void dispose() => router.dispose();
}
