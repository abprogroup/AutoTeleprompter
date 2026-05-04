import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// v3.9.5.68: Ghost Selection Controls
/// Hides native selection handles/toolbars while preserving logical selection.
///
/// The script editor uses an app-owned Cut/Copy/Paste/Select All toolbar. On
/// Android, long-press/drag can still ask the deprecated selection-controls
/// toolbar path to build before `contextMenuBuilder` removes the adaptive menu,
/// so both paths must return empty widgets.
class GhostSelectionControls extends MaterialTextSelectionControls {
  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    return const SizedBox.shrink();
  }

  @Deprecated(
    'Use `contextMenuBuilder` instead. '
    'This feature was deprecated after v3.3.0-0.5.pre.',
  )
  @override
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset selectionMidpoint,
    List<TextSelectionPoint> endpoints,
    TextSelectionDelegate delegate,
    ValueListenable<ClipboardStatus>? clipboardStatus,
    Offset? lastSecondaryTapDownPosition,
  ) {
    ContextMenuController.removeAny();
    return const SizedBox.shrink();
  }
}
