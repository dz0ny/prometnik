import 'package:flutter/material.dart';

import '../services/webcam_proxy.dart';
import 'live_webcam_image.dart';
import 'webcam_thumbnail.dart' show webcamCacheBucket;

/// A row of live thumbnails for a station with several cameras; tapping one
/// shows it large. The thumbnails share the frames of the large image (one
/// image source per camera), so they stay current.
class CameraPicker extends StatelessWidget {
  final List<String> urls;
  final int selected;
  final ValueChanged<int> onSelect;

  const CameraPicker({
    super.key,
    required this.urls,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final bucket = webcamCacheBucket();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          for (var i = 0; i < urls.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _Thumb(
                url: proxiedWebcamUrl(urls[i], buster: bucket),
                label: 'Kamera ${i + 1}',
                selected: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Thumb({
    required this.url,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            clipBehavior: Clip.antiAlias,
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? cs.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                LiveWebcamImage(
                  url: url,
                  memCacheWidth: 360,
                  fit: BoxFit.cover,
                  placeholder: (_) => const ColoredBox(color: Colors.black),
                  errorWidget: (_) => const Icon(
                    Icons.videocam_off,
                    color: Colors.white38,
                    size: 20,
                  ),
                ),
                Positioned(
                  left: 6,
                  bottom: 4,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
