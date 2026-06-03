part of 'script_editor_screen.dart';

class _EditorModeReturnSnapshot {
  final double? scrollOffset;
  final int? activeBlock;
  final TextSelection? selection;

  const _EditorModeReturnSnapshot({
    required this.scrollOffset,
    required this.activeBlock,
    required this.selection,
  });
}

extension _ScriptEditorModeReturnParts on _ScriptEditorScreenState {
  _EditorModeReturnSnapshot _captureEditorModeReturnSnapshot() {
    var activeBlock = _lastFocusedController == null
        ? -1
        : _controllers.indexOf(_lastFocusedController!);
    if (activeBlock < 0) {
      activeBlock = _focusNodes.indexWhere((node) => node.hasFocus);
    }
    final controller = activeBlock >= 0 && activeBlock < _controllers.length
        ? _controllers[activeBlock]
        : null;
    final selection = controller != null && controller.selection.isValid
        ? controller.selection
        : null;
    return _EditorModeReturnSnapshot(
      scrollOffset: _editorScrollController.hasClients
          ? _editorScrollController.offset
          : null,
      activeBlock: activeBlock >= 0 ? activeBlock : null,
      selection: selection,
    );
  }

  void _restoreEditorModeReturnSnapshot(
    _EditorModeReturnSnapshot snapshot,
  ) {
    void restoreSelection() {
      final block = snapshot.activeBlock;
      final selection = snapshot.selection;
      if (block == null ||
          selection == null ||
          block < 0 ||
          block >= _controllers.length) {
        return;
      }
      final controller = _controllers[block];
      final textLength = controller.text.length;
      if (selection.start > textLength || selection.end > textLength) return;
      controller.selection = selection;
      _lastFocusedController = controller;
    }

    void restoreScroll() {
      final offset = snapshot.scrollOffset;
      if (offset == null || !_editorScrollController.hasClients) return;
      final max = _editorScrollController.position.maxScrollExtent;
      _editorScrollController.jumpTo(offset.clamp(0.0, max).toDouble());
    }

    restoreSelection();
    restoreScroll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      restoreSelection();
      restoreScroll();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        restoreScroll();
        _onSelectionChanged();
      });
    });
  }
}
