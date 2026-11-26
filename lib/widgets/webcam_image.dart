import 'package:flutter/material.dart';

import '../models/weather_station.dart';
import 'live_webcam_image.dart';
import '../services/webcam_store.dart';

/// Displays a station's webcam frame. A [refreshKey] (e.g. a millisecond
/// timestamp) is appended to the URL to bust the cache and pull a fresh frame.
class WebcamImage extends StatelessWidget {
  final WeatherStation station;
  final int refreshKey;
  final BoxFit fit;
  final double? height;

  /// History snapshot to show instead of the live frame (see
  /// [WebcamHistoryStrip]).
  final WebcamFrame? snapshot;
  final ValueChanged<WebcamFrame>? onFrame;

  const WebcamImage({
    super.key,
    required this.station,
    required this.refreshKey,
    this.fit = BoxFit.cover,
    this.height,
    this.snapshot,
    this.onFrame,
  });

  @override
  Widget build(BuildContext context) {
    if (station.cameraLink.isEmpty) {
      return _placeholder(context, Icons.videocam_off, 'Ni kamere');
    }
    final url = station.cameraUrlWithBuster(refreshKey);
    return LiveWebcamImage(
      url: url,
      snapshot: snapshot,
      onFrame: onFrame,
      // Bypass the disk cache between refreshes; the buster makes keys unique.
      // Keep showing the previous frame until the refreshed one decodes.
      fit: fit,
      height: height,
      width: double.infinity,
      placeholder: (context) => _placeholder(context, null, null),
      errorWidget: (context) => _placeholder(
        context,
        Icons.broken_image_outlined,
        'Slika ni na voljo',
      ),
    );
  }

  Widget _placeholder(BuildContext context, IconData? icon, String? label) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Small thumbnails (e.g. 64×48 list rows) only fit an icon.
        final w = constraints.maxWidth;
        final h = height ?? constraints.maxHeight;
        final compact = w < _compactWidth || h < _compactHeight;
        final Widget child;
        if (icon == null) {
          final s = compact ? 16.0 : 28.0;
          child = SizedBox(
            width: s,
            height: s,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        } else if (compact || label == null) {
          child = Icon(
            icon,
            color: cs.onSurfaceVariant,
            size: compact ? 20 : 32,
            semanticLabel: label,
          );
        } else {
          child = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: cs.onSurfaceVariant, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          );
        }
        return Container(
          height: height,
          width: double.infinity,
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: child,
        );
      },
    );
  }

  static const _compactWidth = 140.0;
  static const _compactHeight = 100.0;
}
