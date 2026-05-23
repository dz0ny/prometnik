import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Color schemes ──────────────────────────────────────────────────────
  // Cool "night sky / road" palette for Promet (dark) and a light variant
  // that keeps the same sky-blue accent for use under the system theme.

  static const ColorScheme darkScheme = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: Color(0xFF5DA9E9), // Sky blue
    onPrimary: Color(0xFF06121F),
    primaryContainer: Color(0xFF1B3A5B), // Deep blue
    onPrimaryContainer: Color(0xFFD3E6F7),
    secondary: Color(0xFF7FD1AE), // Mint
    onSecondary: Color(0xFF062014),
    secondaryContainer: Color(0xFF234A3C),
    onSecondaryContainer: Color(0xFFCDEFE0),
    tertiary: Color(0xFFFFB74D), // Amber (warmth / sun)
    onTertiary: Color(0xFF1F1300),
    error: Color(0xFFCF6679),
    onError: Color(0xFF000000),
    errorContainer: Color(0xFF5B1B23),
    onErrorContainer: Color(0xFFF7D6DC),
    surface: Color(0xFF0D1B2A), // Deep navy
    onSurface: Color(0xFFE6EAF0),
    surfaceContainerHighest: Color(0xFF1B263B),
    onSurfaceVariant: Color(0xFFB6C2D2),
    outline: Color(0xFF415A77),
  );

  // iOS keeps a true-dark (near-black) surface like the native system dark
  // mode instead of the navy night-sky used on Android, while sharing the same
  // sky-blue accent.
  static const ColorScheme darkSchemeIOS = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: Color(0xFF5DA9E9), // Sky blue
    onPrimary: Color(0xFF06121F),
    primaryContainer: Color(0xFF1B3A5B),
    onPrimaryContainer: Color(0xFFD3E6F7),
    secondary: Color(0xFF7FD1AE),
    onSecondary: Color(0xFF062014),
    secondaryContainer: Color(0xFF234A3C),
    onSecondaryContainer: Color(0xFFCDEFE0),
    tertiary: Color(0xFFFFB74D),
    onTertiary: Color(0xFF1F1300),
    error: Color(0xFFFF453A),
    onError: Color(0xFF000000),
    errorContainer: Color(0xFF3A1316),
    onErrorContainer: Color(0xFFFFD7D5),
    surface: Color(0xFF000000), // True black
    onSurface: Color(0xFFEDEDED),
    surfaceContainerHighest: Color(0xFF1C1C1E), // iOS elevated surface
    onSurfaceVariant: Color(0xFFAEAEB2),
    outline: Color(0xFF3A3A3C),
  );

  static const ColorScheme lightScheme = ColorScheme.light(
    brightness: Brightness.light,
    primary: Color(0xFF1B6FB3), // Deeper sky blue for contrast on white
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFCFE5F7),
    onPrimaryContainer: Color(0xFF06243B),
    secondary: Color(0xFF2E9E78), // Mint, darkened
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFBFEBD9),
    onSecondaryContainer: Color(0xFF06281C),
    tertiary: Color(0xFFC97A00), // Amber, darkened
    onTertiary: Color(0xFFFFFFFF),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF7FAFD), // Near-white with a cool tint
    onSurface: Color(0xFF111A24),
    surfaceContainerHighest: Color(0xFFE3EBF3),
    onSurfaceVariant: Color(0xFF42525F),
    outline: Color(0xFF93A4B5),
  );

  // ── Material themes ────────────────────────────────────────────────────

  static ThemeData get darkTheme => _material(darkScheme);
  static ThemeData get darkThemeIOS => _material(darkSchemeIOS);
  static ThemeData get lightTheme => _material(lightScheme);

  /// The Material theme matching a given platform [brightness]. Used to inject
  /// our palette on iOS, where [AdaptiveApp] renders a CupertinoApp and would
  /// otherwise leave body widgets without our [ColorScheme]. iOS dark mode uses
  /// the near-black [darkSchemeIOS] rather than Android's navy night-sky.
  static ThemeData materialFor(Brightness brightness) {
    if (brightness != Brightness.dark) return lightTheme;
    return PlatformInfo.isIOS ? darkThemeIOS : darkTheme;
  }

  static ThemeData _material(ColorScheme cs) {
    return ThemeData(
      useMaterial3: true,
      brightness: cs.brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        toolbarHeight: 48,
        backgroundColor: cs.surfaceContainerHighest,
        foregroundColor: cs.onSurface,
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outline, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outline),
        ),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 58,
        backgroundColor: cs.surfaceContainerHighest,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: cs.primary.withValues(alpha: 0.3),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: cs.primary);
          }
          return IconThemeData(color: cs.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(color: cs.primary, fontSize: 12);
          }
          return TextStyle(color: cs.onSurfaceVariant, fontSize: 12);
        }),
      ),
    );
  }

  // ── Cupertino themes ───────────────────────────────────────────────────

  static const CupertinoThemeData cupertinoLight = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: Color(0xFF1B6FB3),
    scaffoldBackgroundColor: Color(0xFFF7FAFD),
    barBackgroundColor: Color(0xFFE3EBF3),
  );

  static const CupertinoThemeData cupertinoDark = CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: Color(0xFF5DA9E9),
    scaffoldBackgroundColor: Color(0xFF000000),
    barBackgroundColor: Color(0xFF1C1C1E),
  );

  /// Extra top inset for scrollable content beneath an [AdaptiveAppBar]. On
  /// iOS 26 the native Liquid-Glass toolbar (~44pt) overlays full-screen content
  /// and is not reflected in [MediaQuery] padding, so content must be pushed
  /// down by that height (on top of the status-bar inset a [SafeArea] adds).
  /// Other platforms inset the body below the bar already, so this is 0.
  static double appBarContentInset() =>
      PlatformInfo.isIOS26OrHigher() ? 44.0 : 0.0;

  /// Extra bottom inset for scrollable content sitting under the shell's tab
  /// bar. On iOS the tab bar floats over the body (it's not an inset like
  /// Android's Material NavigationBar), so list content must reserve room for
  /// it — the bar (~50pt) plus the home-indicator safe area — or the last rows
  /// hide behind it. Android's Scaffold already insets the body, so this is 0.
  static double bottomBarContentInset(BuildContext context) {
    if (!PlatformInfo.isIOS) return 0;
    return 56 + MediaQuery.viewPaddingOf(context).bottom;
  }

  /// Map a temperature (°C) to a colour for markers and chips.
  static Color temperatureColor(double? c) {
    if (c == null) return const Color(0xFF6B7B8C);
    if (c <= -10) return const Color(0xFF4A148C); // deep violet
    if (c <= 0) return const Color(0xFF1E88E5); // blue (freezing)
    if (c <= 5) return const Color(0xFF26C6DA); // cyan
    if (c <= 12) return const Color(0xFF66BB6A); // green
    if (c <= 20) return const Color(0xFFD4E157); // lime
    if (c <= 27) return const Color(0xFFFFB300); // amber
    if (c <= 33) return const Color(0xFFFB8C00); // orange
    return const Color(0xFFE53935); // hot red
  }
}
