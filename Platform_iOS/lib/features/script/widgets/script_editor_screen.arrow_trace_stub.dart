part of 'script_editor_screen.dart';

extension _ScriptEditorArrowTraceParts on _ScriptEditorScreenState {
  bool get _shouldCaptureArrowTrace => false;

  void _recordVerticalArrowTrace({
    required LogicalKeyboardKey key,
    required int blockIndex,
    required int rawOffset,
    required bool isRtl,
    required _VerticalLayoutInfo layout,
    required double preferredX,
    required ({int block, int offset})? target,
  }) {}

  void _recordNativeArrowTrace(
    KeyEvent event, {
    String mode = 'native TextField pass-through',
  }) {}

  void _resetArrowTraceSession(String reason) {}

  RenderEditable? _findRenderEditable(RenderObject? root) {
    if (root == null) return null;
    if (root is RenderEditable) return root;
    RenderEditable? result;
    root.visitChildren((child) {
      result ??= _findRenderEditable(child);
    });
    return result;
  }
}
