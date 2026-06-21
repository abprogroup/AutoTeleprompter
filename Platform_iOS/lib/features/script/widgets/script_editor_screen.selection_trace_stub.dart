part of 'script_editor_screen.dart';

extension _ScriptEditorSelectionTraceParts on _ScriptEditorScreenState {
  void _recordSelectionTrace(
    String reason, {
    LogicalKeyboardKey? key,
    SelectionEndpoint? anchor,
    SelectionEndpoint? focus,
    String? seedSource,
    String? targetMode,
    bool? anchorCrossing,
    bool? collapsedShiftSeed,
    bool? staleOverlayRejected,
  }) {}
}
