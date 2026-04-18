import 'package:flutter/material.dart';

/// v3.9.5.68: Ghost Selection Controls
/// Hides the native OS 'bubble' handles while preserving the logical selection and context menu.
class GhostSelectionControls extends MaterialTextSelectionControls {
  @override
  Widget buildHandle(BuildContext context, TextSelectionHandleType type, double textLineHeight, [VoidCallback? onTap, double? startGlyphHeight, double? endGlyphHeight]) {
    // Return an empty box to hide the native handle
    return const SizedBox.shrink();
  }
}
