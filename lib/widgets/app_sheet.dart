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
    required this.children,
    this.initialSize = 0.62,
    this.minSize = 0.25,
    this.maxSize = 1.0,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
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

class _SheetHeader extends SliverPersistentHeaderDelegate {
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Color color;

  _SheetHeader({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.color,
  });

  double get _height {
    if (title == null) return 48;
    return subtitle == null ? 64 : 80;
  }

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

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
              padding: const EdgeInsets.fromLTRB(16, 2, 8, 6),
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
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
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
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const _CloseButton(),
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
      old.color != color;
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Zapri',
      child: Material(
        color: cs.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).maybePop(),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
