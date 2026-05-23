import 'dart:async';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/weather_station.dart';
import '../theme/app_theme.dart';
import 'webcam_image.dart';

/// A webcam frame that:
///  - tap → opens a zoomable fullscreen viewer,
///  - long-press → fetches a fresh frame (with haptic feedback),
///  - optionally auto-refreshes on an interval.
///
/// When [overlayName] is provided, the station name (and optional temperature
/// badge) are drawn over a bottom gradient scrim.
class InteractiveWebcam extends StatefulWidget {
  final WeatherStation station;
  final double aspectRatio;
  final double borderRadius;
  final Duration? autoRefresh;
  final String? overlayName;
  final double? overlayTemp;

  const InteractiveWebcam({
    super.key,
    required this.station,
    this.aspectRatio = 16 / 9,
    this.borderRadius = 20,
    this.autoRefresh,
    this.overlayName,
    this.overlayTemp,
  });

  @override
  State<InteractiveWebcam> createState() => _InteractiveWebcamState();
}

class _InteractiveWebcamState extends State<InteractiveWebcam> {
  int _key = DateTime.now().millisecondsSinceEpoch;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final interval = widget.autoRefresh;
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) {
        if (mounted) setState(() => _key = DateTime.now().millisecondsSinceEpoch);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    HapticFeedback.mediumImpact();
    setState(() => _key = DateTime.now().millisecondsSinceEpoch);
    AdaptiveSnackBar.show(
      context,
      message: 'Osvežujem sliko…',
      duration: const Duration(milliseconds: 900),
    );
  }

  void _openFullscreen() {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) =>
            _FullscreenWebcam(station: widget.station, initialKey: _key),
        // Fade the lightbox in/out — a smooth, platform-neutral modal feel.
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasOverlay = widget.overlayName != null;
    return GestureDetector(
      onTap: _openFullscreen,
      onLongPress: _refresh,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: WebcamImage(
                  station: widget.station,
                  refreshKey: _key,
                  fit: BoxFit.contain,
                ),
              ),
              if (hasOverlay)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.55, 1.0],
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                ),
              // Fullscreen affordance.
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.fullscreen, size: 18, color: Colors.white),
                ),
              ),
              if (hasOverlay)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          widget.overlayName!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                          ),
                        ),
                      ),
                      if (widget.overlayTemp != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.temperatureColor(widget.overlayTemp),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(blurRadius: 6, color: Colors.black54),
                            ],
                          ),
                          child: Text(
                            '${widget.overlayTemp!.toStringAsFixed(1)} °C',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zoomable, dismissable fullscreen webcam viewer. Tap to close, long-press to
/// refresh.
class _FullscreenWebcam extends StatefulWidget {
  final WeatherStation station;
  final int initialKey;

  const _FullscreenWebcam({required this.station, required this.initialKey});

  @override
  State<_FullscreenWebcam> createState() => _FullscreenWebcamState();
}

class _FullscreenWebcamState extends State<_FullscreenWebcam> {
  late int _key = widget.initialKey;

  void _refresh() {
    HapticFeedback.mediumImpact();
    setState(() => _key = DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.station.cameraUrlWithBuster(_key);
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            onLongPress: _refresh,
            child: SizedBox.expand(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    cacheKey: url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => Center(
                      child: PlatformInfo.isIOS
                          ? const CupertinoActivityIndicator(
                              color: Colors.white,
                            )
                          : const CircularProgressIndicator(),
                    ),
                    errorWidget: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AdaptiveButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icons.close,
                    style: AdaptiveButtonStyle.tinted,
                    color: Colors.white24,
                    iconColor: Colors.white,
                  ),
                  AdaptiveButton.icon(
                    onPressed: _refresh,
                    icon: Icons.refresh,
                    style: AdaptiveButtonStyle.tinted,
                    color: Colors.white24,
                    iconColor: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
