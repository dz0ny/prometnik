import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/update_provider.dart';

/// Floating card at the bottom of the screen while an app update is
/// available, downloading or failed (Android APK builds only).
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateProvider);
    if (s.status == UpdateStatus.idle || s.status == UpdateStatus.checking) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(updateProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final error = s.status == UpdateStatus.error;
    final busy =
        s.status == UpdateStatus.downloading ||
        s.status == UpdateStatus.installing;
    final bg = error ? cs.errorContainer : cs.primaryContainer;
    final fg = error ? cs.onErrorContainer : cs.onPrimaryContainer;
    final (String title, String? detail) = switch (s.status) {
      UpdateStatus.available => (
        'Na voljo je nova različica',
        s.release == null ? null : 'Prometnik ${s.release!.version}',
      ),
      UpdateStatus.downloading => (
        'Prenašam posodobitev …',
        '${(s.progress * 100).round()} %',
      ),
      UpdateStatus.installing => ('Nameščam posodobitev …', null),
      _ => ('Posodobitev ni uspela', s.error),
    };

    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        top: false,
        child: Material(
          elevation: 6,
          color: bg,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                if (busy)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      value: s.progress > 0 && s.progress < 1
                          ? s.progress
                          : null,
                      strokeWidth: 2.5,
                      color: fg,
                    ),
                  )
                else
                  Icon(
                    error ? Icons.error_outline : Icons.system_update,
                    color: fg,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg.withValues(alpha: .8),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!busy)
                  TextButton(
                    onPressed: error ? notifier.check : notifier.install,
                    style: TextButton.styleFrom(
                      backgroundColor: fg,
                      foregroundColor: bg,
                    ),
                    child: Text(error ? 'Ponovi' : 'Posodobi'),
                  ),
                if (!busy)
                  IconButton(
                    tooltip: 'Pozneje',
                    icon: Icon(Icons.close, color: fg, size: 20),
                    onPressed: notifier.dismiss,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
