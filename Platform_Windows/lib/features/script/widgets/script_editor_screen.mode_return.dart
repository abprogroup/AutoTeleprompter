part of 'script_editor_screen.dart';

class _EditorModeReturnSnapshot {
  final double? scrollOffset;
  final int? activeBlock;
  final TextSelection? selection;
  final bool hadFocus;

  const _EditorModeReturnSnapshot({
    required this.scrollOffset,
    required this.activeBlock,
    required this.selection,
    required this.hadFocus,
  });
}

extension _ScriptEditorModeReturnParts on _ScriptEditorScreenState {
  _EditorModeReturnSnapshot _captureEditorModeReturnSnapshot() {
    final focusedBlock = _focusNodes.indexWhere((node) => node.hasFocus);
    final activeBlock = focusedBlock;
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
      hadFocus: focusedBlock >= 0,
    );
  }

  void _restoreEditorModeReturnSnapshot(
    _EditorModeReturnSnapshot snapshot,
  ) {
    final token = ++_editorModeReturnRestoreToken;

    void restoreSelection() {
      if (token != _editorModeReturnRestoreToken) return;
      if (!snapshot.hadFocus) return;
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
      _focusNodes[block].requestFocus();
    }

    void restoreScroll() {
      if (token != _editorModeReturnRestoreToken) return;
      final offset = snapshot.scrollOffset;
      if (offset == null || !_editorScrollController.hasClients) return;
      final max = _editorScrollController.position.maxScrollExtent;
      _editorScrollController.jumpTo(offset.clamp(0.0, max).toDouble());
    }

    if (!snapshot.hadFocus) {
      FocusScope.of(context).unfocus();
    }
    restoreSelection();
    restoreScroll();

    void restoreAfterFrame(int remainingFrames) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _editorModeReturnRestoreToken) return;
        restoreSelection();
        restoreScroll();
        if (remainingFrames > 1) {
          restoreAfterFrame(remainingFrames - 1);
        } else {
          Future<void>.delayed(const Duration(milliseconds: 80), () {
            if (!mounted || token != _editorModeReturnRestoreToken) return;
            restoreScroll();
            _onSelectionChanged();
          });
        }
      });
    }

    restoreAfterFrame(3);
  }
}
