import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/webcam_store.dart';
import 'live_webcam_image.dart';

/// Opens the fullscreen webcam viewer.
void showWebcamViewer(
  BuildContext context, {
  required String title,
  required String Function(int buster) urlFor,
  required int initialKey,
  WebcamFrame? initialSnapshot,
  bool showHistory = true,
}) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => WebcamViewer(
        title: title,
        urlFor: urlFor,
        initialKey: initialKey,
        initialSnapshot: initialSnapshot,
        showHistory: showHistory,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Fullscreen webcam viewer: pinch or double-tap to zoom, drag to pan, with
/// the 24-hour history along the bottom. A single tap hides/shows the
/// controls; the close button (or the system back gesture) dismisses it.
class WebcamViewer extends StatefulWidget {
  final String title;
  final String Function(int buster) urlFor;
  final int initialKey;
  final WebcamFrame? initialSnapshot;

  /// The 24-hour strip (weather-station cameras only).
  final bool showHistory;

  const WebcamViewer({
    super.key,
    required this.title,
    required this.urlFor,
    required this.initialKey,
    this.initialSnapshot,
    this.showHistory = true,
  });

  @override
  State<WebcamViewer> createState() => _WebcamViewerState();
}

class _WebcamViewerState extends State<WebcamViewer>
    with SingleTickerProviderStateMixin {
  static const double _maxScale = 6;
  static const double _doubleTapScale = 2.5;

  late int _key = widget.initialKey;
  late WebcamFrame? _snapshot = widget.initialSnapshot;
  DateTime? _liveAt;
  bool _chrome = true;

  final _transform = TransformationController();
  late final AnimationController _zoomAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Animation<Matrix4>? _zoomTween;
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _zoomAnim.addListener(() {
      final tween = _zoomTween;
      if (tween != null) _transform.value = tween.value;
    });
  }

  @override
  void dispose() {
    _zoomAnim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _refresh() {
    HapticFeedback.mediumImpact();
    setState(() {
      _snapshot = null;
      _key = DateTime.now().millisecondsSinceEpoch;
    });
  }

  /// Double-tap: zoom in around the tapped point, or back out to fit.
  void _toggleZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.05;
    final Matrix4 target;
    if (zoomed) {
      target = Matrix4.identity();
    } else {
      final p = _doubleTapAt;
      target = Matrix4.identity()
        ..translateByDouble(
          -p.dx * (_doubleTapScale - 1),
          -p.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    }
    _zoomTween = Matrix4Tween(
      begin: _transform.value,
      end: target,
    ).animate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic));
    _zoomAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.urlFor(_key);
    final snapshot = _snapshot;
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _chrome = !_chrome),
              onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
              onDoubleTap: _toggleZoom,
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: _maxScale,
                child: SizedBox.expand(
                  child: LiveWebcamImage(
                    url: url,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    snapshot: snapshot,
                    onFrame: (f) {
                      if (_liveAt != f.at) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _liveAt = f.at);
                        });
                      }
                    },
                    placeholder: (_) => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    errorWidget: (_) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Top bar.
            _Chrome(
              visible: _chrome,
              alignment: Alignment.topCenter,
              gradientBegin: Alignment.topCenter,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Zapri',
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            WebcamTimeLabel(snapshot: snapshot),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Osveži sliko',
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: _refresh,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 24-hour history.
            if (widget.showHistory)
              _Chrome(
                visible: _chrome,
                alignment: Alignment.bottomCenter,
                gradientBegin: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
                    child: WebcamHistoryStrip(
                      url: url,
                      selected: snapshot,
                      refreshToken: _liveAt,
                      framed: false,
                      onSelect: (f) => setState(() => _snapshot = f),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A fading bar over the image with a scrim behind it.
class _Chrome extends StatelessWidget {
  final bool visible;
  final Alignment alignment;
  final Alignment gradientBegin;
  final Widget child;

  const _Chrome({
    required this.visible,
    required this.alignment,
    required this.gradientBegin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: gradientBegin,
                end: Alignment.center,
                colors: const [Colors.black87, Colors.transparent],
              ),
            ),
            child: SizedBox(width: double.infinity, child: child),
          ),
        ),
      ),
    );
  }
}
