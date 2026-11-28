import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/traffic_camera.dart';
import 'sheet_snack.dart';
import 'app_sheet.dart';
import 'interactive_webcam.dart';
import 'weather_details.dart' show WeatherFormat;

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

/// The same layout as the station sheet: the live frame as a full-width hero
/// with the name over it and refresh / fullscreen buttons, the frame time in
/// the slim header, then where the camera is and what it looks at.
class _CameraSheetState extends State<CameraSheet> {
  /// When the frame on screen was taken (from the edge proxy).
  DateTime? _frameAt;

  void _onLiveFrame(DateTime at) {
    if (at == _frameAt) return;
    // May arrive while the image builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && at != _frameAt) setState(() => _frameAt = at);
    });
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
    if (!opened && mounted) {
      showSheetSnack(
        context,
        message: 'Povezave ni mogoče odpreti',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cam = widget.camera;
    final name = cam.title.isEmpty ? 'Kamera' : cam.title;
    final at = _frameAt;

    return AppSheet(
      // The hero carries the name; the header keeps the frame time.
      subtitle: at == null ? null : 'Slika ob ${WeatherFormat.timestamp(at)}',
      children: [
        InteractiveWebcam(
          title: name,
          urlFor: cam.imageUrlWithBuster,
          onLiveFrame: _onLiveFrame,
          autoRefresh: const Duration(seconds: 60),
          fit: BoxFit.cover,
          borderRadius: 24,
          overlayName: name,
        ),
        const SizedBox(height: 12),
        _CameraInfoCard(camera: cam),
        const SizedBox(height: 16),
        // Flutter, not the native iOS 26 button: a native view inside the
        // scrolling sheet clipped the header on devices.
        SheetLinkButton(
          onPressed: () => unawaited(_openBrowser()),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_new, size: 18),
              SizedBox(width: 8),
              Text('Odpri sliko v brskalniku'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where the camera is: road and view direction, region and source.
class _CameraInfoCard extends StatelessWidget {
  final TrafficCamera camera;
  const _CameraInfoCard({required this.camera});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (camera.description.isNotEmpty)
            _InfoRow(icon: Icons.route, text: camera.description, strong: true),
          if (camera.region.isNotEmpty)
            _InfoRow(icon: Icons.place_outlined, text: camera.region),
          const _InfoRow(
            icon: Icons.videocam_outlined,
            text: 'Kamera DARS · slika se osveži vsako minuto',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool strong;
  const _InfoRow({required this.icon, required this.text, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: strong ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: strong ? cs.onSurface : cs.onSurfaceVariant,
                fontSize: strong ? 15 : 13.5,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Zoomable, dismissable fullscreen camera viewer.
