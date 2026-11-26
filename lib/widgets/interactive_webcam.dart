import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/weather_station.dart';
import '../theme/app_theme.dart';
import 'weather_details.dart' show WeatherFormat;
import 'webcam_image.dart';
import 'sheet_snack.dart';
import 'live_webcam_image.dart';
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
/// badge) are drawn over a bottom gradient scrim.
class InteractiveWebcam extends StatefulWidget {
  final WeatherStation station;
  final double aspectRatio;
  final double borderRadius;
  final Duration? autoRefresh;
  final String? overlayName;
  final double? overlayTemp;

  /// Whether to show a visible refresh button next to the fullscreen one.
  final bool showRefreshButton;

  /// Show the "Zadnjih 24 ur" strip of hourly snapshots under the image.
  final bool showHistory;

  const InteractiveWebcam({
    super.key,
    required this.station,
    this.aspectRatio = 16 / 9,
    this.borderRadius = 20,
    this.autoRefresh,
    this.overlayName,
    this.overlayTemp,
    this.showRefreshButton = true,
    this.showHistory = false,
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
    if (interval != null && widget.station.cameraLink.isNotEmpty) {
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
      title: widget.station.name,
      urlFor: widget.station.cameraUrlWithBuster,
      initialKey: _key,
      initialSnapshot: _snapshot,
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _buildImage(context);
    if (!widget.showHistory || widget.station.cameraLink.isEmpty) return image;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        image,
        WebcamHistoryStrip(
          url: widget.station.cameraUrlWithBuster(_key),
          selected: _snapshot,
          refreshToken: _liveAt,
          onSelect: (f) => setState(() => _snapshot = f),
        ),
      ],
    );
  }

  Widget _buildImage(BuildContext context) {
    final hasOverlay = widget.overlayName != null;
    final hasCamera = widget.station.cameraLink.isNotEmpty;
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
                child: WebcamImage(
                  station: widget.station,
                  refreshKey: _key,
                  fit: BoxFit.contain,
                  snapshot: _snapshot,
                  onFrame: (f) {
                    if (_liveAt != f.at && mounted) {
                      // Defer: onFrame can fire during the child's build.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _liveAt = f.at);
                      });
                    }
                  },
                ),
              ),
              if (_snapshot != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: WebcamSnapshotBadge(frame: _snapshot!),
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
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black87),
                            ],
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
                            color: AppTheme.temperatureColor(
                              widget.overlayTemp,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(blurRadius: 6, color: Colors.black54),
                            ],
                          ),
                          child: Text(
                            WeatherFormat.temp(widget.overlayTemp),
                            style: TextStyle(
                              // Cold colours are dark violet/blue: pick a
                              // readable foreground from the background.
                              color:
                                  AppTheme.temperatureColor(widget.overlayTemp)
                                          .computeLuminance() <
                                      0.45
                                  ? Colors.white
                                  : Colors.black,
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
