import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'live_webcam_image.dart';

/// Length of one webcam refresh step. Thumbnail URLs carry a cache-buster
/// rounded to this step, so map rebuilds within it reuse the cached frame.
const Duration webcamRefreshStep = Duration(minutes: 5);

/// The current cache-bust bucket: epoch milliseconds rounded down to
/// [webcamRefreshStep]. Pass it to `cameraUrlWithBuster`/`imageUrlWithBuster`.
int webcamCacheBucket([DateTime? now]) {
  final step = webcamRefreshStep.inMilliseconds;
  final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return ms ~/ step * step;
}

/// Size tiers for map webcam thumbnails; frames grow as the map zooms in.
enum ThumbnailSize {
  small(80, 50),
  medium(140, 88),
  large(200, 125);

  final double width;
  final double height;

  const ThumbnailSize(this.width, this.height);

  /// Extra marker height this tier needs above a pin (frame + gap).
  double get extent => height + WebcamThumbnail.gap;

  /// The tier for [zoom], or null below [minZoom] (no thumbnail).
  ///
  /// Tiers: small from 11, medium from 13, large from 14.5. A [minZoom]
  /// above 11 skips straight to the tier that applies at that zoom.
  static ThumbnailSize? forZoom(double zoom, {double minZoom = 11}) {
    if (zoom < minZoom || zoom < 11) return null;
    if (zoom >= 14.5) return large;
    if (zoom >= 13) return medium;
    return small;
  }
}

/// A small live webcam frame shown above a map pin when zoomed in.
class WebcamThumbnail extends StatelessWidget {
  /// Gap between the frame and the pin below it.
  static const double gap = 4;

  final String url;

  /// Frame size; defaults to the [ThumbnailSize.small] tier.
  final double width;
  final double height;

  const WebcamThumbnail(
    this.url, {
    super.key,
    this.width = 80,
    this.height = 50,
  });

  /// A frame sized to the [size] tier.
  WebcamThumbnail.sized(this.url, ThumbnailSize size, {super.key})
    : width = size.width,
      height = size.height;

  /// Corner radius of the frame (outer edge, rim included).
  static const double radius = 10;

  /// White rim, as on the map pins.
  static const double rim = 1.5;

  @override
  Widget build(BuildContext context) {
    // No solid fill or shadow behind the frame: while it loads (or fails) it
    // stays a faint outline instead of a black box burying nearby pins.
    // The white rim and rounded corners match the map pins below it.
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: rim,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - rim),
        child: LiveWebcamImage(
          url: url,
          // Decode at display size (3x for retina, capped), not the full frame.
          memCacheWidth: math.min((width * 3).round(), 600),
          fit: BoxFit.cover,
          placeholder: (_) =>
              ColoredBox(color: Colors.black.withValues(alpha: 0.12)),
          errorWidget: (_) => ColoredBox(
            color: const Color(0xFF3A4B5E).withValues(alpha: 0.55),
            child: const Center(
              child: Icon(Icons.videocam_off, size: 16, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
