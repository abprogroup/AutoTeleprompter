part of 'script_editor_screen.dart';

class _EditorModeReturnSnapshot {
  final double? scrollOffset;

  const _EditorModeReturnSnapshot({
    required this.scrollOffset,
  });
}

extension _ScriptEditorModeReturnParts on _ScriptEditorScreenState {
  _EditorModeReturnSnapshot _captureEditorModeReturnSnapshot() {
    return _EditorModeReturnSnapshot(
      scrollOffset: _editorScrollController.hasClients
          ? _editorScrollController.offset
          : null,
    );
  }

  void _restoreEditorModeReturnSnapshot(
    _EditorModeReturnSnapshot snapshot,
  ) {
    final token = ++_editorModeReturnRestoreToken;

    void restoreScroll() {
      if (token != _editorModeReturnRestoreToken) return;
      final offset = snapshot.scrollOffset;
      if (offset == null || !_editorScrollController.hasClients) return;
      final max = _editorScrollController.position.maxScrollExtent;
      _editorScrollController.jumpTo(offset.clamp(0.0, max).toDouble());
    }

    FocusScope.of(context).unfocus();
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
