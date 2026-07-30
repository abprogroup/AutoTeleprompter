part of 'script_editor_screen.dart';

class _EditorModeReturnSnapshot {
  final double? scrollOffset;

  const _EditorModeReturnSnapshot({
    required this.scrollOffset,
  });
}

/// Preserves editor scroll position and clears text-field focus when leaving
/// for Present mode, then restores that position on return. Ported from
/// Windows' `script_editor_screen.mode_return.dart` - Android's own
/// `_startPresenting()` didn't do either, so returning from a presentation
/// session could leave the scroll position wherever it happened to land and
/// a text field's keyboard/cursor active underneath the presenter overlay.
extension _ScriptEditorModeReturnParts on _ScriptEditorScreenState {
  _EditorModeReturnSnapshot _captureEditorModeReturnSnapshot() {
    return _EditorModeReturnSnapshot(
      scrollOffset: _editorScrollController.hasClients
          ? _editorScrollController.offset
          : null,
    );
  }

  void _suspendEditorFocusForReaderMode() {
    _keyboardFocusRepairToken++;
    FocusScope.of(context).unfocus();
    for (final focusNode in _focusNodes) {
      focusNode.unfocus();
    }
  }

  void _restoreEditorModeReturnSnapshot(
    _EditorModeReturnSnapshot snapshot,
  ) {
    final token = ++_editorModeReturnRestoreToken;
    _suspendEditorFocusForReaderMode();

    void restoreScroll() {
      if (token != _editorModeReturnRestoreToken) return;
      final offset = snapshot.scrollOffset;
      if (offset == null || !_editorScrollController.hasClients) return;
      final max = _editorScrollController.position.maxScrollExtent;
      _editorScrollController.jumpTo(offset.clamp(0.0, max).toDouble());
    }

    restoreScroll();

    void restoreAfterFrame(int remainingFrames) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _editorModeReturnRestoreToken) return;
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
