import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/favorites_provider.dart';
import '../providers/weather_provider.dart';
import '../router/navigation_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/interactive_webcam.dart';
import '../widgets/weather_details.dart';

/// Full-screen view of a single station: large auto-refreshing webcam (tap for
/// fullscreen, long-press to refresh) and the complete weather reading.
class StationDetailScreen extends StatefulWidget {
  final int stationId;

  const StationDetailScreen({super.key, required this.stationId});

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  Future<void> _openCameraInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    bool opened;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      opened = false;
    }
    if (!opened) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'Povezave ni mogoče odpreti',
          type: AdaptiveSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WeatherProvider>(
      builder: (context, provider, _) {
        final station = provider.byId(widget.stationId);
        if (station == null && provider.isLoading) {
          // Deep link opened before the weather feed arrived.
          return const AdaptiveScaffold(
            appBar: AdaptiveAppBar(title: 'Postaja'),
            body: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        if (station == null) {
          return const AdaptiveScaffold(
            appBar: AdaptiveAppBar(title: 'Postaja'),
            body: Center(child: Text('Postaja ni na voljo.')),
          );
        }
        final cs = Theme.of(context).colorScheme;
        final favs = context.watch<FavoritesProvider>();
        final isFav = favs.isFavorite(station.stationId);
        final updated = station.weather?.timestamp;

        return AdaptiveScaffold(
          appBar: AdaptiveAppBar(
            title: station.name,
            actions: [
              AdaptiveAppBarAction(
                icon: isFav ? Icons.star : Icons.star_border,
                iosSymbol: isFav ? 'star.fill' : 'star',
                label: isFav
                    ? 'Odstrani iz priljubljenih'
                    : 'Dodaj med priljubljene',
                tintColor: isFav ? const Color(0xFFFFB74D) : null,
                onPressed: () => favs.toggle(station.stationId),
              ),
              AdaptiveAppBarAction(
                icon: Icons.map_outlined,
                iosSymbol: 'map',
                label: 'Pokaži na karti',
                onPressed: () {
                  context.read<NavigationNotifier>().showStationOnMap(
                    station.stationId,
                  );
                },
              ),
            ],
          ),
          // The SafeArea clears the status bar and, on iOS 26, the native
          // toolbar too (the scaffold adds the toolbar height to the top
          // padding), so no extra app-bar inset is added here.
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + AppTheme.bottomBarContentInset(context),
              ),
              children: [
                InteractiveWebcam(
                  station: station,
                  autoRefresh: const Duration(seconds: 60),
                  showHistory: true,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (updated != null) ...[
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Posodobljeno: ${WeatherFormat.timestamp(updated)}',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    AdaptiveButton.child(
                      onPressed: () => _openCameraInBrowser(station.cameraLink),
                      style: AdaptiveButtonStyle.plain,
                      size: AdaptiveButtonSize.small,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Text('Kamera', style: TextStyle(color: cs.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (station.weather == null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Ta postaja ima samo kamero in ne sporoča '
                            'vremenskih podatkov.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  WeatherDetailsView(weather: station.weather!),
              ],
            ),
          ),
        );
      },
    );
  }
}
