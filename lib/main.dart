import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/events_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/travel_times_provider.dart';
import 'providers/weather_provider.dart';
import 'router/app_router.dart';
import 'router/navigation_notifier.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        ChangeNotifierProvider(create: (_) => TravelTimesProvider()..start()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()..load()),
        ChangeNotifierProvider(create: (_) => NavigationNotifier()),
      ],
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
    );
  }
}

/// Holds the GoRouter so it survives rebuilds and is disposed cleanly.
class GoRouterHolder {
  final router = createRouter();
  void dispose() => router.dispose();
}
