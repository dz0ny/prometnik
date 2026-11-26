import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/traffic_camera.dart';
import 'sheet_snack.dart';
import 'app_sheet.dart';
import 'live_webcam_image.dart';
import 'webcam_viewer.dart';
import '../services/webcam_store.dart';

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

  /// Selected history snapshot (null = live) and the latest live frame time.
  WebcamFrame? _snapshot;
  DateTime? _liveAt;

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
    showWebcamViewer(
      context,
      title: widget.camera.title.isEmpty ? 'Kamera' : widget.camera.title,
      urlFor: widget.camera.imageUrlWithBuster,
      initialKey: _key,
      initialSnapshot: _snapshot,
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
      title: cam.title.isEmpty ? 'Kamera' : cam.title,
      titleMaxLines: 2,
      subtitle: cam.region.isEmpty ? null : cam.region,
      leading: Icon(Icons.videocam, color: cs.primary),
      children: [
        Semantics(
          button: true,
          label: 'Celozaslonski prikaz',
          child: GestureDetector(
            onTap: _openFullscreen,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      LiveWebcamImage(
                        url: cam.imageUrlWithBuster(_key),
                        fit: BoxFit.contain,
                        snapshot: _snapshot,
                        onFrame: (f) {
                          if (_liveAt != f.at) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _liveAt = f.at);
                            });
                          }
                        },
                        placeholder: (_) => const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                      if (_snapshot != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: WebcamSnapshotBadge(frame: _snapshot!),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        WebcamHistoryStrip(
          url: cam.imageUrlWithBuster(_key),
          selected: _snapshot,
          refreshToken: _liveAt,
          onSelect: (f) => setState(() => _snapshot = f),
        ),
        if (cam.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            cam.description,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
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
