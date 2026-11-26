import 'dart:async';

import 'package:flutter/material.dart';

import '../services/webcam_store.dart';

/// A webcam image that paints the last known frame **instantly** (memory,
/// then disk) and swaps in the fresh frame when it arrives — no spinner on
/// repeat views. Each download is also kept by [WebcamStore] as the camera's
/// hourly snapshot for the 24-hour history.
///
/// [url] is the proxied, cache-busted URL from the models' `*WithBuster`
/// methods; a new buster triggers a refresh while the old frame stays up.
class LiveWebcamImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Decode width in physical pixels (like `CachedNetworkImage.memCacheWidth`).
  final int? memCacheWidth;

  /// Shown only when no frame is known yet.
  final WidgetBuilder? placeholder;

  /// Shown only when no frame is known and the download failed.
  final WidgetBuilder? errorWidget;

  /// When set (e.g. a history snapshot is selected), shown instead of the
  /// live frame; the live frame keeps refreshing underneath.
  final WebcamFrame? snapshot;

  /// Called with each frame shown (stored or fresh).
  final ValueChanged<WebcamFrame>? onFrame;

  const LiveWebcamImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.placeholder,
    this.errorWidget,
    this.snapshot,
    this.onFrame,
  });

  @override
  State<LiveWebcamImage> createState() => _LiveWebcamImageState();
}

class _LiveWebcamImageState extends State<LiveWebcamImage> {
  /// Skip re-downloading a camera another widget fetched this recently.
  static const Duration _freshFor = Duration(seconds: 30);

  final WebcamStore _store = WebcamStore.instance;
  WebcamFrame? _frame;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _frame = _store.latestSync(widget.url);
    if (_frame == null) unawaited(_loadStored());
    _refresh();
  }

  @override
  void didUpdateWidget(LiveWebcamImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      final known = _store.latestSync(widget.url);
      if (known != null && !identical(known, _frame)) _show(known);
      _refresh();
    }
  }

  Future<void> _loadStored() async {
    final stored = await _store.latest(widget.url);
    // A fresh frame may have landed first; don't replace it with an older one.
    if (stored != null && mounted && _frame == null) {
      setState(() => _show(stored));
    }
  }

  void _refresh() {
    if (widget.url.isEmpty) return;
    if (_frame != null && _store.isFresh(widget.url, _freshFor)) return;
    final url = widget.url;
    unawaited(
      _store.fetch(url).then((fresh) {
        if (!mounted || url != widget.url) return;
        setState(() {
          if (fresh != null) {
            _show(fresh);
            _failed = false;
          } else {
            _failed = _frame == null;
          }
        });
      }),
    );
  }

  void _show(WebcamFrame frame) {
    _frame = frame;
    widget.onFrame?.call(frame);
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.snapshot ?? _frame;
    if (frame == null) {
      final builder = _failed ? widget.errorWidget : widget.placeholder;
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: builder?.call(context) ?? const SizedBox.shrink(),
      );
    }
    return Image.memory(
      frame.bytes,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      cacheWidth: widget.memCacheWidth,
      // Keep the previous frame on screen while the next one decodes.
      gaplessPlayback: true,
      errorBuilder: (context, _, _) =>
          widget.errorWidget?.call(context) ?? const SizedBox.shrink(),
    );
  }
}

/// Horizontal strip of the camera's hourly snapshots (last 24 hours) with a
/// "V živo" chip first. Picking an hour calls [onSelect] with that frame;
/// "V živo" calls it with null. Hidden until at least one snapshot exists.
///
/// Snapshots are captured on this device whenever the app loads the camera,
/// so the strip only has hours in which the camera was viewed.
class WebcamHistoryStrip extends StatefulWidget {
  /// Any URL of the camera (proxied/busted is fine).
  final String url;
  final WebcamFrame? selected;
  final ValueChanged<WebcamFrame?> onSelect;

  /// Changes when a new live frame arrives, so the strip reloads.
  final Object? refreshToken;

  const WebcamHistoryStrip({
    super.key,
    required this.url,
    required this.selected,
    required this.onSelect,
    this.refreshToken,
  });

  @override
  State<WebcamHistoryStrip> createState() => _WebcamHistoryStripState();
}

class _WebcamHistoryStripState extends State<WebcamHistoryStrip> {
  List<WebcamFrame> _history = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(WebcamHistoryStrip old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken ||
        cameraKey(old.url) != cameraKey(widget.url)) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final h = await WebcamStore.instance.history(widget.url);
    if (mounted) setState(() => _history = h);
  }

  @override
  Widget build(BuildContext context) {
    if (_history.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final frames = _history.reversed.toList(); // newest first
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zadnjih 24 ur',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: frames.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _tile(
                    context,
                    selected: widget.selected == null,
                    label: 'V živo',
                    onTap: () => widget.onSelect(null),
                    child: Icon(Icons.videocam, color: cs.primary, size: 22),
                  );
                }
                final f = frames[i - 1];
                return _tile(
                  context,
                  selected: identical(widget.selected, f),
                  label: '${f.at.hour.toString().padLeft(2, '0')}:00',
                  onTap: () => widget.onSelect(f),
                  child: Image.memory(
                    f.bytes,
                    fit: BoxFit.cover,
                    cacheWidth: 192,
                    gaplessPlayback: true,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required bool selected,
    required String label,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label == 'V živo' ? 'Slika v živo' : 'Posnetek ob $label',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Container(
                width: 72,
                height: 44,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? cs.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Center(child: child),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small badge drawn over a webcam image while a history snapshot is shown.
class WebcamSnapshotBadge extends StatelessWidget {
  final WebcamFrame frame;
  const WebcamSnapshotBadge({super.key, required this.frame});

  @override
  Widget build(BuildContext context) {
    final h = frame.at.hour.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Posnetek ob $h:00',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
