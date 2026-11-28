import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'weather_details.dart' show WeatherFormat;
import 'sheet_snack.dart';
import 'live_webcam_image.dart';
import 'shimmer_box.dart';
import 'webcam_viewer.dart';
import '../services/webcam_store.dart';

/// A small dark translucent icon button drawn over the webcam image, with a
/// 44pt hit area around its 28pt visual.
class _OverlayIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A webcam frame that:
///  - tap → opens a zoomable fullscreen viewer,
///  - long-press → fetches a fresh frame (with haptic feedback),
///  - optionally auto-refreshes on an interval.
///
/// When [overlayName] is provided, the station name (and optional temperature
/// badge) are drawn over a bottom gradient scrim, making the frame a hero
/// image. Until the first frame arrives a shimmer skeleton is shown.
class InteractiveWebcam extends StatefulWidget {
  /// Camera name, used for the fullscreen viewer's title.
  final String title;

  /// The proxied, cache-busted frame URL for a buster; null = no camera.
  final String Function(int buster)? urlFor;

  /// Called with the time of each live frame shown (e.g. a header's
  /// "Slika ob" line).
  final ValueChanged<DateTime>? onLiveFrame;
  final double aspectRatio;
  final double borderRadius;
  final Duration? autoRefresh;
  final String? overlayName;
  final double? overlayTemp;

  /// How the frame fills the box; heroes crop with [BoxFit.cover].
  final BoxFit fit;

  /// Whether to show a visible refresh button next to the fullscreen one.
  final bool showRefreshButton;

  /// Show the "Zadnjih 24 ur" strip of hourly snapshots under the image.
  final bool showHistory;

  /// Called with the hour of the picked history snapshot, or null when the
  /// live frame is back, so the page can show the readings of that hour.
  final ValueChanged<DateTime?>? onSnapshotChanged;

  /// Shown between the image and the history strip (e.g. a camera picker).
  final Widget? belowImage;

  const InteractiveWebcam({
    super.key,
    required this.title,
    required this.urlFor,
    this.onLiveFrame,
    this.aspectRatio = 16 / 9,
    this.borderRadius = 20,
    this.autoRefresh,
    this.overlayName,
    this.overlayTemp,
    this.fit = BoxFit.contain,
    this.showRefreshButton = true,
    this.showHistory = false,
    this.onSnapshotChanged,
    this.belowImage,
  });

  @override
  State<InteractiveWebcam> createState() => _InteractiveWebcamState();
}

class _InteractiveWebcamState extends State<InteractiveWebcam> {
  int _key = DateTime.now().millisecondsSinceEpoch;
  Timer? _timer;

  /// Selected history snapshot (null = live) and the latest live frame time,
  /// which reloads the history strip when a new frame arrives.
  WebcamFrame? _snapshot;
  DateTime? _liveAt;

  @override
  void initState() {
    super.initState();
    final interval = widget.autoRefresh;
    // No point refreshing a station that has no camera.
    if (interval != null && widget.urlFor != null) {
      _timer = Timer.periodic(interval, (_) {
        if (mounted) {
          setState(() => _key = DateTime.now().millisecondsSinceEpoch);
        }
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
    showSheetSnack(
      context,
      message: 'Osvežujem sliko…',
      duration: const Duration(milliseconds: 900),
    );
  }

  void _openFullscreen() {
    showWebcamViewer(
      context,
      title: widget.title,
      urlFor: widget.urlFor!,
      initialKey: _key,
      initialSnapshot: _snapshot,
      showHistory: widget.showHistory,
    );
  }

  void _onFrame(WebcamFrame f) {
    widget.onLiveFrame?.call(f.at);
    if (_liveAt != f.at && mounted) {
      // Defer: onFrame can fire during the child's build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _liveAt = f.at);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _buildImage(context);
    final urlFor = widget.urlFor;
    final below = widget.belowImage;
    final history = widget.showHistory && urlFor != null;
    if (!history && below == null) return image;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        image,
        ?below,
        if (history)
          WebcamHistoryStrip(
            url: urlFor(_key),
            selected: _snapshot,
            refreshToken: _liveAt,
            onSelect: (f) {
              setState(() => _snapshot = f);
              widget.onSnapshotChanged?.call(f?.at);
            },
          ),
      ],
    );
  }

  Widget _buildImage(BuildContext context) {
    final hasOverlay = widget.overlayName != null;
    final urlFor = widget.urlFor;
    final hasCamera = urlFor != null;
    return GestureDetector(
      onTap: hasCamera ? _openFullscreen : null,
      onLongPress: hasCamera ? _refresh : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: hasCamera
                    ? LiveWebcamImage(
                        url: urlFor(_key),
                        fit: widget.fit,
                        width: double.infinity,
                        snapshot: _snapshot,
                        onFrame: _onFrame,
                        placeholder: (_) => const ShimmerBox(),
                        errorWidget: (_) => const _ImageUnavailable(),
                      )
                    : const Center(
                        child: Icon(
                          Icons.videocam_off,
                          color: Colors.white38,
                          size: 32,
                          semanticLabel: 'Ni kamere',
                        ),
                      ),
              ),
              if (_snapshot != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: WebcamSnapshotBadge(frame: _snapshot!),
                ),
              if (hasOverlay)
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.45, 0.75, 1.0],
                        colors: [
                          Colors.transparent,
                          Color(0x59000000),
                          Color(0xB3000000),
                        ],
                      ),
                    ),
                  ),
                ),
              // Refresh and fullscreen affordances (long-press still
              // refreshes, tap anywhere still opens fullscreen).
              if (hasCamera)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.showRefreshButton)
                        _OverlayIconButton(
                          icon: Icons.refresh,
                          tooltip: 'Osveži sliko',
                          onTap: _refresh,
                        ),
                      _OverlayIconButton(
                        icon: Icons.fullscreen,
                        tooltip: 'Celozaslonski prikaz',
                        onTap: _openFullscreen,
                      ),
                    ],
                  ),
                ),
              if (hasOverlay)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: _HeroCaption(
                    name: widget.overlayName!,
                    temp: widget.overlayTemp,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Place name and current temperature drawn over the bottom of a hero
/// webcam image.
class _HeroCaption extends StatelessWidget {
  final String name;
  final double? temp;

  const _HeroCaption({required this.name, this.temp});

  static const _shadow = [Shadow(blurRadius: 8, color: Colors.black87)];

  @override
  Widget build(BuildContext context) {
    final t = temp;
    final title = Text(
      name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 20,
        height: 1.15,
        shadows: _shadow,
      ),
    );
    if (t == null) return title;
    return LayoutBuilder(
      builder: (context, c) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // The name takes whatever the temperature leaves.
          Expanded(child: title),
          const SizedBox(width: 10),
          // At most ~55% of the width; scales down rather than overflowing
          // at large text sizes.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth * .55),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tinted dot: the temperature colour scale, on any image.
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.temperatureColor(t),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    WeatherFormat.temp(t),
                    maxLines: 1,
                    style: AppTheme.numberStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      shadows: _shadow,
                    ),
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

/// Shown in place of the image when no frame could be loaded.
class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              'Slika ni na voljo',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
