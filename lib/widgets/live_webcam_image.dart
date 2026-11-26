import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
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
/// Hours come from this device (captured whenever the app loads the camera)
/// and from the edge worker, which snapshots every camera once an hour. A
/// worker snapshot is downloaded when picked; if the worker can't be
/// reached, only the device's hours are shown.
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
  List<WebcamHistoryEntry> _history = const [];

  /// The worker snapshot being downloaded after a tap, if any.
  DateTime? _loadingAt;

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
      if (cameraKey(old.url) != cameraKey(widget.url)) {
        _history = const [];
        _loadingAt = null;
      }
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final store = WebcamStore.instance;
    final key = cameraKey(widget.url);
    bool current() => mounted && cameraKey(widget.url) == key;
    // Device hours first (fast), then merged with the worker's list, so a
    // slow or unreachable worker never holds the strip back.
    final merged = store.mergedHistory(widget.url);
    final local = await store.history(widget.url);
    if (current() && _history.isEmpty) {
      setState(
        () =>
            _history = mergeWebcamHistory(local, const [], now: DateTime.now()),
      );
    }
    final all = await merged;
    if (current()) setState(() => _history = all);
  }

  Future<void> _pick(WebcamHistoryEntry e) async {
    final local = e.frame;
    if (local != null) {
      setState(() => _loadingAt = null);
      widget.onSelect(local);
      return;
    }
    setState(() => _loadingAt = e.at);
    final frame = await WebcamStore.instance.snapshotFrame(e);
    // Ignore a download the user moved on from (another tile, V živo).
    if (!mounted || _loadingAt != e.at) return;
    setState(() => _loadingAt = null);
    if (frame != null) widget.onSelect(frame);
  }

  @override
  Widget build(BuildContext context) {
    if (_history.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final entries = _history.reversed.toList(); // newest first
    final selectedAt = widget.selected?.at;
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
              itemCount: entries.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _tile(
                    context,
                    selected: widget.selected == null && _loadingAt == null,
                    label: 'V živo',
                    onTap: () {
                      setState(() => _loadingAt = null);
                      widget.onSelect(null);
                    },
                    child: Icon(Icons.videocam, color: cs.primary, size: 22),
                  );
                }
                final e = entries[i - 1];
                final loading = _loadingAt == e.at;
                final thumb = e.bytes != null
                    ? Image.memory(
                        e.bytes!,
                        fit: BoxFit.cover,
                        cacheWidth: 192,
                        gaplessPlayback: true,
                      )
                    : CachedNetworkImage(
                        imageUrl: e.url!,
                        cacheManager: WebcamStore.instance.snapshotCache,
                        fit: BoxFit.cover,
                        memCacheWidth: 192,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (_, _) => const SizedBox.shrink(),
                        errorWidget: (_, _, _) => Icon(
                          Icons.image_not_supported_outlined,
                          color: cs.onSurfaceVariant,
                          size: 18,
                        ),
                      );
                return _tile(
                  context,
                  selected:
                      loading ||
                      (_loadingAt == null &&
                          selectedAt != null &&
                          selectedAt.isAtSameMomentAs(e.at)),
                  label: '${e.at.hour.toString().padLeft(2, '0')}:00',
                  onTap: () => unawaited(_pick(e)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      thumb,
                      if (loading)
                        const ColoredBox(
                          color: Colors.black38,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
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
