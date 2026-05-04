part of 'script_editor_screen.dart';

extension _ScriptEditorDebugBookmarkSearchParts on _ScriptEditorScreenState {
  Widget _buildDebugSentry() {
    final activeIdx = _focusNodes.indexWhere((n) => n.hasFocus);
    final sel = _activeController?.selection;
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'EDITOR SENTRY',
            style: TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          _debugLine('Blocks: ${_controllers.length}'),
          _debugLine('Active Block: ${activeIdx != -1 ? activeIdx : "None"}'),
          if (sel != null)
            _debugLine('Cursor: [${sel.baseOffset}, ${sel.extentOffset}]'),
          _debugLine('Global Selection: $_isGlobalSelection'),
          _debugLine(
            'Overlay: ${_overlayKey.currentState?.debugSelectionSummary ?? "None"}',
          ),
          _debugLine('Arrow: $_lastArrowDecision'),
          _debugLine('Clipboard: $_selectionClipboardDebug'),
          _debugLine('Command: $_selectionCommandDebug'),
          _debugLine('Range: $_recognizedBlockRangeDebug'),
          _debugLine('History States: ${_history.length}'),
        ],
      ),
    );
  }

  Widget _debugLine(String value) => Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      );

  /// Called on pointer-up to promote the final native selection into the
  /// overlay handles. Cross-block drags already own the overlay, so this only
  /// adopts one-block partial native ranges.
  void _promoteNativeSelectionToOverlay() {
    if (_isGlobalSelection || _isCommandExecuting) return;
    final overlay = _overlayKey.currentState;
    if (overlay == null ||
        overlay.hasSelection ||
        overlay.isHandleInteractionActive) {
      return;
    }
    for (var i = 0; i < _controllers.length; i++) {
      if (!_focusNodes[i].hasFocus) continue;
      final sel = _controllers[i].selection;
      if (!sel.isValid || sel.isCollapsed) continue;
      if (sel.start == 0 && sel.end == _controllers[i].text.length) continue;
      _extendNativeSelectionToOverlay(i);
      return;
    }
  }

  void _onCut() => _onCutClean();

  Future<void> _onPaste() async => _pasteFromGlobalClipboard();
}
