import 'dart:async';
import 'dart:typed_data';

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

  /// Draw the strip inside a tinted card (sheets); false over a dark
  /// fullscreen image.
  final bool framed;

  const WebcamHistoryStrip({
    super.key,
    required this.url,
    required this.selected,
    required this.onSelect,
    this.refreshToken,
    this.framed = true,
  });

  @override
  State<WebcamHistoryStrip> createState() => _WebcamHistoryStripState();
}

class _WebcamHistoryStripState extends State<WebcamHistoryStrip> {
  List<WebcamHistoryEntry> _history = const [];

  /// The worker snapshot being downloaded after a tap, if any.
  DateTime? _loadingAt;

  // Timelapse playback through the history, oldest to newest.
  bool _playing = false;
  int _playToken = 0;

  static const int _slots = 24;
  static const double _stripHeight = 46;
  static const double _liveWidth = 58;

  @override
  void dispose() {
    _playToken++;
    super.dispose();
  }

  void _stopPlay() {
    _playToken++;
    if (_playing) setState(() => _playing = false);
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      _stopPlay();
      return;
    }
    final token = ++_playToken;
    final frames = List.of(_history);
    setState(() {
      _playing = true;
      _loadingAt = null;
    });
    for (var i = 0; i < frames.length; i++) {
      final e = frames[i];
      final frame = e.frame ?? await WebcamStore.instance.snapshotFrame(e);
      if (!mounted || token != _playToken) return;
      if (frame == null) continue;
      widget.onSelect(frame);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted || token != _playToken) return;
    }
    setState(() => _playing = false);
    widget.onSelect(null);
  }

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
    _stopPlay();
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
    final liveSelected = widget.selected == null && _loadingAt == null;
    final liveBytes = WebcamStore.instance.latestSync(widget.url)?.bytes;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Zadnjih 24 ur',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: WebcamTimeLabel(snapshot: widget.selected),
              ),
            ),
            Tooltip(
              message: _playing ? 'Ustavi' : 'Predvajaj zadnjih 24 ur',
              child: Material(
                color: _playing
                    ? cs.primary
                    : cs.primary.withValues(alpha: .14),
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => unawaited(_togglePlay()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _playing ? Icons.stop : Icons.play_arrow,
                          size: 16,
                          color: _playing ? cs.onPrimary : cs.primary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _playing ? 'Ustavi' : 'Predvajaj',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _playing ? cs.onPrimary : cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _filmstrip(context, liveSelected, selectedAt, liveBytes),
      ],
    );

    if (!widget.framed) return content;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: content,
      ),
    );
  }

  /// Start of the hour shown in slot [i] (0 = 23 hours ago, 23 = this hour).
  DateTime _slotHour(int i, DateTime now) => DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
  ).subtract(Duration(hours: _slots - 1 - i));

  /// All 24 hours across one bar (oldest left), then a "V živo" cell. Tap or
  /// drag along it to scrub; hours without a frame are dimmed and skipped.
  Widget _filmstrip(
    BuildContext context,
    bool liveSelected,
    DateTime? selectedAt,
    Uint8List? liveBytes,
  ) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final bySlot = List<WebcamHistoryEntry?>.filled(_slots, null);
    for (final e in _history) {
      for (var i = 0; i < _slots; i++) {
        if (_slotHour(i, now).isAtSameMomentAs(e.at)) bySlot[i] = e;
      }
    }
    final activeAt = _loadingAt ?? selectedAt;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stripWidth = constraints.maxWidth - _liveWidth - 6;
        final cell = stripWidth / _slots;

        void scrubTo(double dx) {
          if (dx >= stripWidth) {
            if (!liveSelected) {
              _stopPlay();
              setState(() => _loadingAt = null);
              widget.onSelect(null);
            }
            return;
          }
          final at = (dx / cell).floor().clamp(0, _slots - 1);
          // Nearest hour that has a frame.
          WebcamHistoryEntry? pick;
          for (var d = 0; d < _slots && pick == null; d++) {
            if (at - d >= 0) pick = bySlot[at - d];
            if (pick == null && at + d < _slots) pick = bySlot[at + d];
          }
          if (pick == null) return;
          if (activeAt != null && activeAt.isAtSameMomentAs(pick.at)) return;
          unawaited(_pick(pick));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => scrubTo(d.localPosition.dx),
              onHorizontalDragStart: (d) => scrubTo(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => scrubTo(d.localPosition.dx),
              child: SizedBox(
                height: _stripHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: stripWidth,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ColoredBox(
                          color: cs.surfaceContainerHighest,
                          child: Row(
                            children: [
                              for (var i = 0; i < _slots; i++)
                                Expanded(
                                  child: _slotCell(
                                    cs,
                                    bySlot[i],
                                    selected:
                                        bySlot[i] != null &&
                                        activeAt != null &&
                                        activeAt.isAtSameMomentAs(
                                          bySlot[i]!.at,
                                        ),
                                    loading:
                                        bySlot[i] != null &&
                                        _loadingAt == bySlot[i]!.at,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _liveCell(cs, liveSelected, liveBytes),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Hour ticks every 6 hours under the strip.
            SizedBox(
              width: stripWidth,
              height: 14,
              child: Stack(
                children: [
                  for (final i in const [0, 6, 12, 18])
                    Positioned(
                      left: i * cell,
                      child: Text(
                        '${_slotHour(i, now).hour.toString().padLeft(2, '0')}h',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _slotCell(
    ColorScheme cs,
    WebcamHistoryEntry? e, {
    required bool selected,
    required bool loading,
  }) {
    if (e == null) {
      // No frame for this hour.
      return Center(
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: cs.onSurfaceVariant.withValues(alpha: .35),
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    final thumb = e.bytes != null
        ? Image.memory(
            e.bytes!,
            fit: BoxFit.cover,
            cacheWidth: 160,
            gaplessPlayback: true,
          )
        : CachedNetworkImage(
            imageUrl: e.url!,
            cacheManager: WebcamStore.instance.snapshotCache,
            fit: BoxFit.cover,
            memCacheWidth: 160,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, _) => const SizedBox.shrink(),
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          );
    return Semantics(
      button: true,
      selected: selected,
      label: 'Posnetek ob ${webcamHourLabel(e.at)}',
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          color: loading ? Colors.black38 : null,
          border: selected
              ? Border.all(color: cs.primary, width: 2.5)
              : Border(
                  right: BorderSide(
                    color: Colors.black.withValues(alpha: .35),
                    width: .5,
                  ),
                ),
        ),
        child: SizedBox.expand(child: thumb),
      ),
    );
  }

  Widget _liveCell(ColorScheme cs, bool selected, Uint8List? liveBytes) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Slika v živo',
      child: Container(
        width: _liveWidth,
        clipBehavior: Clip.antiAlias,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? cs.primary : Colors.white.withValues(alpha: .12),
            width: selected ? 2.5 : 1,
          ),
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (liveBytes != null)
              Image.memory(
                liveBytes,
                fit: BoxFit.cover,
                cacheWidth: 180,
                gaplessPlayback: true,
              ),
            const ColoredBox(color: Colors.black45),
            const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LiveDot(),
                  SizedBox(width: 4),
                  Text(
                    'Živo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "HH:00", prefixed with "vč." for hours from the previous day.
String webcamHourLabel(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final hh = '${at.hour.toString().padLeft(2, '0')}:00';
  final sameDay = at.year == n.year && at.month == n.month && at.day == n.day;
  return sameDay ? hh : 'vč. $hh';
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFFFF453A),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// What the image currently shows: a red "V živo" pill, or the snapshot's
/// hour and how long ago it was.
class WebcamTimeLabel extends StatelessWidget {
  final WebcamFrame? snapshot;
  const WebcamTimeLabel({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = snapshot;
    if (s == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LiveDot(),
          const SizedBox(width: 5),
          Text(
            'V živo',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    final hours = DateTime.now().difference(s.at).inHours;
    final ago = hours <= 0 ? 'pravkar' : 'pred $hours h';
    return Text(
      '${webcamHourLabel(s.at)} · $ago',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: cs.primary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            'Posnetek ${webcamHourLabel(frame.at)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
