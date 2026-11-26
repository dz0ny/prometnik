import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

/// Shows a short message that is visible above modal bottom sheets.
///
/// On Android [AdaptiveSnackBar] posts to the root [ScaffoldMessenger], whose
/// Scaffold is painted *under* a modal sheet route, so the message is hidden.
/// iOS already uses an overlay, so it is left to [AdaptiveSnackBar].
void showSheetSnack(
  BuildContext context, {
  required String message,
  bool error = false,
  Duration duration = const Duration(seconds: 3),
}) {
  if (PlatformInfo.isIOS) {
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: error ? AdaptiveSnackBarType.error : AdaptiveSnackBarType.info,
      duration: duration,
    );
    return;
  }

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final cs = Theme.of(context).colorScheme;
  final bottom = MediaQuery.viewPaddingOf(context).bottom + 24;

  late final OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: IgnorePointer(
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          color: error ? cs.errorContainer : cs.inverseSurface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Text(
              message,
              style: TextStyle(
                color: error ? cs.onErrorContainer : cs.onInverseSurface,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(duration, remove);
}
