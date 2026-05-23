import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/weather_station.dart';

/// Displays a station's webcam frame. A [refreshKey] (e.g. a millisecond
/// timestamp) is appended to the URL to bust the cache and pull a fresh frame.
class WebcamImage extends StatelessWidget {
  final WeatherStation station;
  final int refreshKey;
  final BoxFit fit;
  final double? height;

  const WebcamImage({
    super.key,
    required this.station,
    required this.refreshKey,
    this.fit = BoxFit.cover,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (station.cameraLink.isEmpty) {
      return _placeholder(context, Icons.videocam_off, 'Ni kamere');
    }
    final url = station.cameraUrlWithBuster(refreshKey);
    return CachedNetworkImage(
      imageUrl: url,
      // Bypass the disk cache between refreshes; the buster makes keys unique.
      cacheKey: url,
      fit: fit,
      height: height,
      width: double.infinity,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, _) => _placeholder(context, null, null),
      errorWidget: (context, _, _) =>
          _placeholder(context, Icons.broken_image_outlined, 'Slika ni na voljo'),
    );
  }

  Widget _placeholder(BuildContext context, IconData? icon, String? label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: icon == null
          ? const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: cs.onSurfaceVariant, size: 32),
                if (label != null) ...[
                  const SizedBox(height: 8),
                  Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ],
            ),
    );
  }
}
