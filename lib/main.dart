import 'dart:async';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/alerts_controller.dart';
import 'providers/burja_provider.dart';
import 'providers/drsi_provider.dart';
import 'providers/cameras_provider.dart';
import 'providers/events_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/rest_areas_provider.dart';
import 'providers/travel_times_provider.dart';
import 'providers/weather_provider.dart';
import 'router/app_router.dart';
import 'router/navigation_notifier.dart';
import 'screens/intro_wizard_screen.dart';
import 'services/map_tile_cache_service.dart';
import 'services/prefs.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  await MapTileCacheService.instance.initialize();
  runApp(const PrometApp());
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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WeatherProvider()..start()),
        ChangeNotifierProvider(create: (_) => EventsProvider()..start()),
        ChangeNotifierProvider(create: (_) => CamerasProvider()..start()),
        ChangeNotifierProvider(create: (_) => RestAreasProvider()..start()),
        ChangeNotifierProvider(create: (_) => BurjaProvider()..start()),
        ChangeNotifierProvider(create: (_) => DrsiProvider()..start()),
        ChangeNotifierProvider(create: (_) => TravelTimesProvider()..start()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()..load()),
        ChangeNotifierProvider(create: (_) => NavigationNotifier()),
        // Location/watched-road alerts; listens to the data providers
        // directly so polls finishing in the background still alert.
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) {
            final alerts = AlertsController()
              ..attach(
                ctx.read<EventsProvider>(),
                ctx.read<TravelTimesProvider>(),
              );
            unawaited(
              alerts.bootstrap().catchError((Object e, StackTrace s) {
                debugPrint('alerts bootstrap failed: $e\n$s');
              }),
            );
            return alerts;
          },
        ),
      ],
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
class _PollingLifecycle extends StatefulWidget {
  final Widget child;
  const _PollingLifecycle({required this.child});

  @override
  State<_PollingLifecycle> createState() => _PollingLifecycleState();
}

class _PollingLifecycleState extends State<_PollingLifecycle> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onPause: _pause, onResume: _resume);
  }

  void _pause() {
    context.read<WeatherProvider>().stop();
    context.read<CamerasProvider>().stop();
    context.read<RestAreasProvider>().stop();
    context.read<BurjaProvider>().stop();
    context.read<DrsiProvider>().stop();
    final alerts = context.read<AlertsController>();
    if (!alerts.hasWatched) context.read<EventsProvider>().stop();
    if (alerts.watchedTravelTimes.isEmpty) {
      context.read<TravelTimesProvider>().stop();
    }
  }

  void _resume() {
    // start() refreshes immediately and re-arms the timer (no-op if running).
    context.read<WeatherProvider>().start();
    context.read<CamerasProvider>().start();
    context.read<RestAreasProvider>().start();
    context.read<BurjaProvider>().start();
    context.read<DrsiProvider>().start();
    context.read<EventsProvider>().start();
    context.read<TravelTimesProvider>().start();
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Holds the GoRouter so it survives rebuilds and is disposed cleanly.
class GoRouterHolder {
  final router = createRouter(showOnboarding: IntroWizardScreen.shouldShow());
  void dispose() => router.dispose();
}
