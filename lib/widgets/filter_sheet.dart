import 'package:flutter/material.dart';

/// A compact "Filtri" button with an active-count badge. Opens a filter sheet.
class FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const FilterButton({super.key, required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = activeCount > 0;
    final fg = active ? cs.onPrimary : cs.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? cs.primary : cs.outline.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(
              'Filtri',
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 6),
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.onPrimary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$activeCount',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Presents a filter sheet. [contentBuilder] receives a [StateSetter] so the
/// sheet's controls can update immediately while the sheet stays open.
Future<void> showFilterSheet({
  required BuildContext context,
  required String title,
  required Widget Function(StateSetter setSheetState) contentBuilder,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // Present above the shell so the sheet isn't covered by the bottom tab bar.
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) => _FilterSheetBody(
          title: title,
          child: contentBuilder(setSheetState),
        ),
      );
    },
  );
}

class _FilterSheetBody extends StatelessWidget {
  final String title;
  final Widget child;

  const _FilterSheetBody({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small uppercase section header for the filter sheet.
class FilterSectionLabel extends StatelessWidget {
  final String text;

  const FilterSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
