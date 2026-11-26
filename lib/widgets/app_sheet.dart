import 'package:flutter/material.dart';

/// Opens a modal bottom sheet whose content is an [AppSheet].
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // The sheet draws its own handle in the pinned header.
    showDragHandle: false,
    builder: builder,
  );
}

/// The app's detail sheet: opens part-way so the map stays visible, drags up
/// to full height, and closes by dragging down, tapping the dimmed map or the
/// always-visible close button in its pinned header.
///
/// The body scrolls under the header; dragging down at the top of the body
/// shrinks the sheet (and dismisses it past [minSize]) instead of getting
/// stuck scrolling, which is what made the old sheets impossible to close.
class AppSheet extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? leading;

  /// Extra header buttons shown before the close button (e.g. navigation).
  final List<Widget> actions;

  /// How many lines the header title may wrap to before it is ellipsized.
  final int titleMaxLines;
  final List<Widget> children;
  final double initialSize;
  final double minSize;
  final double maxSize;
  final EdgeInsetsGeometry padding;

  const AppSheet({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.titleMaxLines = 1,
    required this.children,
    this.initialSize = 0.62,
    this.minSize = 0.25,
    this.maxSize = 1.0,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
  });

  /// Header height that fits the handle, the (scaled) title and subtitle and
  /// the 44pt close button. Never smaller than the original fixed heights.
  double _headerHeight(BuildContext context) {
    // Handle (8 + 5) plus the row's vertical padding (2 + 6).
    const chrome = 21.0;
    // Room for the 44pt close button even without a title.
    if (title == null) return chrome + _closeHitSize;
    final scaler = MediaQuery.textScalerOf(context);
    // Generous line-height factor: plain TextStyles use the font's own
    // metrics, which differ per platform font.
    const lineHeight = 1.35;
    var text = scaler.scale(_titleFontSize) * lineHeight * titleMaxLines;
    if (subtitle != null) text += scaler.scale(_subtitleFontSize) * lineHeight;
    // Material IconButtons in [actions] are 48pt tall.
    final buttons = actions.isEmpty ? _closeHitSize : 48.0;
    final content = text > buttons ? text : buttons;
    final floor = subtitle == null ? 64.0 : 80.0;
    final h = (chrome + content).ceilToDouble();
    return h > floor ? h : floor;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final headerHeight = _headerHeight(context);
    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      expand: false,
      snap: true,
      snapSizes: [initialSize],
      shouldCloseOnMinExtent: true,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16)],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SheetHeader(
                    title: title,
                    subtitle: subtitle,
                    leading: leading,
                    actions: actions,
                    titleMaxLines: titleMaxLines,
                    height: headerHeight,
                    color: cs.surface,
                  ),
                ),
                SliverPadding(
                  padding: padding,
                  sliver: SliverList.list(children: children),
                ),
                SliverToBoxAdapter(child: SizedBox(height: bottomInset + 8)),
              ],
            ),
          ),
        );
      },
    );
  }
}

const _titleFontSize = 20.0;
const _subtitleFontSize = 13.0;
const _closeHitSize = 44.0;

class _SheetHeader extends SliverPersistentHeaderDelegate {
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final int titleMaxLines;
  final double height;
  final Color color;

  _SheetHeader({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.actions,
    required this.titleMaxLines,
    required this.height,
    required this.color,
  });

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: color,
      // Hairline once content scrolls underneath the pinned header.
      shape: overlapsContent || shrinkOffset > 0
          ? Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: .5),
              ),
            )
          : null,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: cs.outline.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 4, 6),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  Expanded(
                    child: title == null
                        ? const SizedBox.shrink()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title!,
                                maxLines: titleMaxLines,
                                softWrap: titleMaxLines > 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: _titleFontSize,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle!,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: _subtitleFontSize,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  ...actions,
                  const AppSheetCloseButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_SheetHeader old) =>
      old.title != title ||
      old.subtitle != subtitle ||
      old.leading != leading ||
      old.actions != actions ||
      old.titleMaxLines != titleMaxLines ||
      old.height != height ||
      old.color != color;
}

/// The sheets' round close button: a 32pt circle with a 44pt hit area.
/// Pops the current route unless [onPressed] is given.
class AppSheetCloseButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const AppSheetCloseButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Zapri',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: 'Zapri',
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: onPressed ?? () => Navigator.of(context).maybePop(),
            radius: _closeHitSize / 2,
            child: SizedBox(
              width: _closeHitSize,
              height: _closeHitSize,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
