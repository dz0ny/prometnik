import 'dart:async';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/traffic_camera.dart';
import 'sheet_snack.dart';
import 'app_sheet.dart';

/// Present a DARS camera in a modal bottom sheet (live image, auto-refresh,
/// tap for fullscreen). Shared by the map markers.
void showCameraSheet(BuildContext context, TrafficCamera camera) {
  showAppSheet<void>(context, builder: (_) => CameraSheet(camera: camera));
}

class CameraSheet extends StatefulWidget {
  final TrafficCamera camera;

  const CameraSheet({super.key, required this.camera});

  @override
  State<CameraSheet> createState() => _CameraSheetState();
}

class _CameraSheetState extends State<CameraSheet> {
  int _key = DateTime.now().millisecondsSinceEpoch;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        setState(() => _key = DateTime.now().millisecondsSinceEpoch);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _openFullscreen() {
    final url = widget.camera.imageUrlWithBuster(_key);
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => _FullscreenCamera(url: url),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  Future<void> _openBrowser() async {
    final uri = Uri.tryParse(widget.camera.imageUrl);
    if (uri == null || !uri.hasScheme) return;
    bool opened;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      opened = false;
    }
    if (!opened) {
      if (mounted) {
        showSheetSnack(
          context,
          message: 'Povezave ni mogoče odpreti',
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cam = widget.camera;

    return AppSheet(
      children: [
        GestureDetector(
          onTap: _openFullscreen,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: CachedNetworkImage(
                  imageUrl: cam.imageUrlWithBuster(_key),
                  cacheKey: cam.imageUrlWithBuster(_key),
                  useOldImageOnUrlChange: true,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
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
        const SizedBox(height: 12),
        Text(
          cam.title.isEmpty ? 'Kamera' : cam.title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        if (cam.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            cam.description,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
          ),
        ],
        if (cam.region.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cam.region,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        AdaptiveButton.child(
          onPressed: _openBrowser,
          style: AdaptiveButtonStyle.tinted,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_new, size: 18),
              SizedBox(width: 8),
              Text('Odpri v brskalniku'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Zoomable, dismissable fullscreen camera viewer.
class _FullscreenCamera extends StatelessWidget {
  final String url;

  const _FullscreenCamera({required this.url});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: SizedBox.expand(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    cacheKey: url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) =>
                        const CupertinoActivityIndicator(color: Colors.white),
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
              child: AdaptiveButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icons.close,
                style: AdaptiveButtonStyle.tinted,
                color: Colors.white24,
                iconColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
