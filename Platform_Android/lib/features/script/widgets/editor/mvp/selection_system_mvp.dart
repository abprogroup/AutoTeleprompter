import 'package:flutter/material.dart';

import '../markup_controller.dart';
import '../components/global_selection_overlay.dart';
import '../../../services/styling_service.dart';
import '../../../../../core/services/rich_clipboard.dart';

/// v4.1.1 MVP: Selection System
/// ─────────────────────────────────────────────────────────────────────────────
/// Isolated multi-block selection orchestration extracted from
/// script_editor_screen.dart.
///
/// Fixes Bug #4: Native toolbar (copy/paste/select all) disappears when
/// drag handles are invoked or after global select. Root cause: handle drag
/// collapses native selection → platform hides its toolbar. Fix: keep native
/// selection synced with overlay's externalSelection at all times.
///
/// Responsibilities:
///   - Select All across all editor blocks
///   - Clear / dismiss global selection
///   - Re-sync after style operations change text lengths
///   - Copy (clean, tag-stripped) to clipboard
///   - Cut (copy + delete selected text)
///   - Delete global selection
class SelectionSystemMvp {
  SelectionSystemMvp._();

  /// Select all text across all blocks.
  ///
  /// [controllers] — list of all block controllers.
  /// [overlayKey] — global key to the selection overlay widget.
  /// [setCommandExecuting] — callback to toggle _isCommandExecuting.
  /// [rebuild] — callback to trigger setState.
  static void selectAll({
    required List<MarkupController> controllers,
    required GlobalKey<GlobalSelectionOverlayState> overlayKey,
    required void Function(bool) setCommandExecuting,
    required VoidCallback rebuild,
  }) {
    setCommandExecuting(true);

    // Set full native selection on ALL blocks (not just the active one).
    // GhostSelectionControls hides the teardrop handles visually, but the
    // native selection must exist so the platform toolbar (copy/paste) appears.
    for (final c in controllers) {
      if (c.text.isNotEmpty) {
        c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      }
    }

    overlayKey.currentState?.selectAll();

    for (final c in controllers) {
      c.isGlobalSelected = true;
      c.externalSelection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }

    setCommandExecuting(false);
    rebuild();

    // Refresh after rebuild so TextFields repaint with new flags.
    for (final c in controllers) {
      c.refresh();
    }
  }

  /// Delete all text within the current selection (global or overlay).
  ///
  /// [controllers/focusNodes/blockKeys] — editor state lists.
  /// [saveHistory] — callback to commit an undo snapshot.
  static void deleteGlobalSelection({
    required List<MarkupController> controllers,
    required List<FocusNode> focusNodes,
    required List<GlobalKey> blockKeys,
    required GlobalKey<GlobalSelectionOverlayState> overlayKey,
    required void Function(bool) setCommandExecuting,
    required void Function(bool) setDirty,
    required void Function(String) saveHistory,
    required void Function(VoidCallback) setStateCallback,
  }) {
    setCommandExecuting(true);
    overlayKey.currentState?.clearSelection();

    for (final c in controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.text = '';
    }

    setStateCallback(() {
      while (controllers.length > 1) {
        controllers.last.dispose();
        focusNodes.last.dispose();
        blockKeys.removeLast();
        controllers.removeLast();
        focusNodes.removeLast();
      }
    });

    if (focusNodes.isNotEmpty) focusNodes.first.requestFocus();
    setCommandExecuting(false);
    setDirty(false);
    saveHistory('Delete Selection');
  }

  /// Clear/dismiss the global selection without deleting text.
  ///
  /// This is called when the user taps outside the selection or starts typing.
  /// Collapses native selections and external highlights in all blocks.
  ///
  /// [mounted] — whether the widget is still mounted (for post-frame callback).
  static void clearGlobalSelection({
    required List<MarkupController> controllers,
    required GlobalKey<GlobalSelectionOverlayState> overlayKey,
    required bool mounted,
    required VoidCallback rebuild,
  }) {
    overlayKey.currentState?.clearSelection();

    for (final c in controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      // Collapse native selection to prevent residual highlight in buildTextSpan.
      // For RTL text, use baseOffset (cursor stays at visual tap position).
      if (!c.selection.isCollapsed) {
        final collapseAt = c.selection.baseOffset.clamp(0, c.text.length);
        c.selection = TextSelection.collapsed(offset: collapseAt);
      }
    }

    rebuild();
    for (final c in controllers) {
      c.refresh();
    }

    // Safety net: re-clear after Flutter's TextField processes the tap gesture,
    // which can re-establish selection in RTL blocks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bool needsRefresh = false;
      for (final c in controllers) {
        if (c.externalSelection != null) {
          c.externalSelection = null;
          needsRefresh = true;
        }
        if (c.isGlobalSelected) {
          c.isGlobalSelected = false;
          needsRefresh = true;
        }
      }
      if (needsRefresh) {
        for (final c in controllers) {
          c.refresh();
        }
        rebuild();
      }
    });
  }

  /// Re-sync externalSelection after a global style operation changes text lengths.
  ///
  /// Must be called after any operation that modifies text while in global
  /// selection mode (e.g. applying bold to all blocks).
  static void resyncGlobalSelection({
    required List<MarkupController> controllers,
    required GlobalKey<GlobalSelectionOverlayState> overlayKey,
    required bool mounted,
    required VoidCallback rebuild,
  }) {
    for (final c in controllers) {
      c.isGlobalSelected = true;
      c.externalSelection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      // Keep native selection synced so platform toolbar stays available
      if (c.text.isNotEmpty) {
        c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      }
    }

    rebuild();
    for (final c in controllers) {
      c.refresh();
    }

    // Recalculate overlay handle positions after layout updates with new text.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) overlayKey.currentState?.selectAll();
    });
  }

  /// Copy selected text to clipboard (tag-stripped plain + HTML-formatted rich).
  ///
  /// Handles both global/overlay selection and single-block native selection.
  static void copyClean({
    required List<MarkupController> controllers,
    required GlobalKey<GlobalSelectionOverlayState> overlayKey,
    required bool isGlobalSelection,
    required MarkupController? activeController,
  }) {
    final hasOverlay = overlayKey.currentState?.hasSelection ?? false;
    if (isGlobalSelection || hasOverlay) {
      final plainBuf = StringBuffer();
      final htmlBuf = StringBuffer();
      for (int i = 0; i < controllers.length; i++) {
        final c = controllers[i];
        final sel = c.externalSelection;
        String slice;
        if (c.isGlobalSelected || sel == null || !sel.isValid) {
          slice = c.text;
        } else if (sel.isCollapsed) {
          continue;
        } else {
          slice = c.text.substring(sel.start, sel.end);
        }
        if (slice.isEmpty) continue;
        if (plainBuf.isNotEmpty) plainBuf.write('\n');
        plainBuf.write(StylingService.stripTags(slice));
        htmlBuf.write(StylingService.markupToHtml(slice));
      }
      if (plainBuf.isEmpty) return;
      RichClipboard.setHtml(plain: plainBuf.toString(), html: htmlBuf.toString());
      return;
    }

    final controller = activeController;
    if (controller == null) return;
    final slice = controller.selection.textInside(controller.text);
    if (slice.isEmpty) return;
    RichClipboard.setHtml(
      plain: StylingService.stripTags(slice),
      html: StylingService.markupToHtml(slice),
    );
  }

  /// Cut: copy to clipboard, then delete the selected text.
  static void cutClean({
    required List<MarkupController> controllers,
    required GlobalKey<GlobalSelectionOverlayState> overlayKey,
    required bool isGlobalSelection,
    required MarkupController? activeController,
    required void Function(bool) setCommandExecuting,
    required void Function() clearGlobalSelection,
    required void Function(String) saveHistory,
    required VoidCallback rebuild,
  }) {
    // Copy first
    copyClean(
      controllers: controllers,
      overlayKey: overlayKey,
      isGlobalSelection: isGlobalSelection,
      activeController: activeController,
    );

    final hasOverlay = overlayKey.currentState?.hasSelection ?? false;
    if (isGlobalSelection || hasOverlay) {
      setCommandExecuting(true);
      if (isGlobalSelection) {
        for (final c in controllers) { c.text = ''; }
      } else {
        for (final c in controllers) {
          final sel = c.externalSelection;
          if (sel == null || !sel.isValid || sel.isCollapsed) continue;
          final s = sel.start.clamp(0, c.text.length);
          final e = sel.end.clamp(0, c.text.length);
          c.text = c.text.substring(0, s) + c.text.substring(e);
        }
      }
      clearGlobalSelection();
      setCommandExecuting(false);
      saveHistory('Cut');
      rebuild();
    } else {
      final c = activeController;
      if (c == null) return;
      final sel = c.selection;
      if (!sel.isValid || sel.isCollapsed) return;
      c.value = TextEditingValue(
        text: c.text.substring(0, sel.start) + c.text.substring(sel.end),
        selection: TextSelection.collapsed(offset: sel.start),
      );
      saveHistory('Cut');
    }
  }
}
