part of 'script_editor_screen.dart';

extension _ScriptEditorToolbarSelectionGuardParts on _ScriptEditorScreenState {
  void _beginEditorToolbarSelectionGuard() {
    _editorToolbarFocusGuardTimer?.cancel();
    _editorToolbarFocusGuard = true;
    _preserveActiveSelectionForToolbarInteraction();
    _editorToolbarFocusGuardTimer = Timer(
      const Duration(milliseconds: 700),
      _endEditorToolbarSelectionGuard,
    );
  }

  void _endEditorToolbarSelectionGuard() {
    _editorToolbarFocusGuardTimer?.cancel();
    _editorToolbarFocusGuardTimer = null;
    _editorToolbarFocusGuard = false;
  }

  void _preserveActiveSelectionForToolbarInteraction() {
    if (_isGlobalSelection ||
        (_overlayKey.currentState?.hasSelection ?? false)) {
      return;
    }
    final controller = _activeController;
    if (controller == null) return;
    final nativeSelection = controller.selection;
    final preservedSelection = identical(controller, _lastFocusedController)
        ? _preservedSelection
        : null;
    final selection = nativeSelection.isValid && !nativeSelection.isCollapsed
        ? nativeSelection
        : preservedSelection;
    if (selection == null) return;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = selection.start.clamp(0, controller.text.length).toInt();
    final end = selection.end.clamp(start, controller.text.length).toInt();
    if (end <= start) return;
    final preserved = TextSelection(baseOffset: start, extentOffset: end);
    _preservedSelection = preserved;
    _lastFocusedController = controller;
    final blockIndex = _controllers.indexOf(controller);
    if (blockIndex >= 0) {
      _overlayKey.currentState?.extendNativeBlockSelection(
        blockIndex,
        preserved,
        allowFullBlock: true,
      );
    } else {
      controller.externalSelection = preserved;
      controller.externalVisibleSelection = null;
      controller.refresh();
    }
  }
}
