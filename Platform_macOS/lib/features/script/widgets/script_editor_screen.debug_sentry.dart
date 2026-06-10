part of 'script_editor_screen.dart';

extension _ScriptEditorDebugSentryParts on _ScriptEditorScreenState {
  Widget _buildDebugSentry() {
    if (_debugSentryCollapsed) {
      return Material(
        color: Colors.transparent,
        child: Tooltip(
          message: 'Show Editor Sentry',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _setEditorState(() => _debugSentryCollapsed = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bug_report_outlined,
                      color: Colors.amber, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'SENTRY',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final activeIdx = _focusNodes.indexWhere((n) => n.hasFocus);
    final sel = _activeController?.selection;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 1)
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 360),
        child: SingleChildScrollView(
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
              Text('Blocks: ${_controllers.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text('Active Block: ${activeIdx != -1 ? activeIdx : "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              if (sel != null)
                Text('Cursor: [${sel.baseOffset}, ${sel.extentOffset}]',
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text('Global Selection: $_isGlobalSelection',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Overlay: ${_overlayKey.currentState?.debugSelectionSummary ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text('Arrow: $_lastArrowDecision',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Arrow Trace PNG: ${_lastArrowTraceScreenshotPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text('Arrow Trace Log: ${_lastArrowTraceLogPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Highlight Trace PNG: ${_lastHighlightTraceScreenshotPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Highlight Trace Log: ${_lastHighlightTraceLogPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Selection Trace PNG: ${_lastSelectionTraceScreenshotPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Selection Trace Log: ${_lastSelectionTraceLogPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text('History States: ${_history.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _debugSentryButton(
                    icon: Icons.expand_more,
                    label: 'Minimize',
                    onPressed: () =>
                        _setEditorState(() => _debugSentryCollapsed = true),
                  ),
                  _debugSentryButton(
                    icon: Icons.copy,
                    label: 'Copy Trace',
                    onPressed: _copyLastArrowTrace,
                  ),
                  _debugSentryButton(
                    icon: Icons.folder_open,
                    label: 'Open Trace Folder',
                    onPressed: _openArrowTraceFolder,
                  ),
                  _debugSentryButton(
                    icon: Icons.highlight_alt,
                    label: 'Highlight Trace',
                    onPressed: _captureCurrentHighlightTrace,
                  ),
                  _debugSentryButton(
                    icon: Icons.copy_all,
                    label: 'Copy Highlight',
                    onPressed: _copyLastHighlightTrace,
                  ),
                  _debugSentryButton(
                    icon: Icons.folder_copy,
                    label: 'Open Selection',
                    onPressed: _openSelectionTraceFolder,
                  ),
                  _debugSentryButton(
                    icon: Icons.copy_all,
                    label: 'Copy Selection',
                    onPressed: _copyLastSelectionTrace,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _debugSentryTraceText(_lastSelectionTrace),
              const SizedBox(height: 6),
              _debugSentryTraceText(_lastHighlightTrace),
              const SizedBox(height: 6),
              _debugSentryTraceText(_lastArrowTrace),
            ],
          ),
        ),
      ),
    );
  }

  Widget _debugSentryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.amber,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _debugSentryTraceText(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 9,
        height: 1.25,
      ),
    );
  }
}
