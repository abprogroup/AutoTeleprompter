part of 'script_editor_screen.dart';

extension _ScriptEditorKeyboardFocusParts on _ScriptEditorScreenState {
  void _crossToBlock(int targetIdx, {int? atOffset, double? x, bool? atEnd}) {
    if (targetIdx < 0 || targetIdx >= _controllers.length) return;
    _suppressActiveArrowEventOnce();
    _lastFocusedController = _controllers[targetIdx];
    _focusNodes[targetIdx].requestFocus();
    final text = _controllers[targetIdx].text;
    int offset;
    if (atOffset != null) {
      final raw = atOffset.clamp(0, text.length).toInt();
      // When entering a block at the END (arrowLeft cross-block), walk backward
      // past any trailing invisible tags so the cursor isn't trapped just after a
      // tag's end where MarkupController would snap it back on every arrowLeft.
      offset = raw <= 0
          ? _blockEntryStartRawOffset(text)
          : (atOffset >= text.length)
              ? MarkupController.safeEndOffset(text)
              : raw;
    } else if (x != null) {
      final layout = _getVerticalLayout(targetIdx);
      offset = layout.getPositionAtX(
        x,
        fromBottom: atEnd ?? false,
        rawText: text,
      );
    } else {
      final raw = atEnd == true ? text.length : 0;
      offset = atEnd == true ? MarkupController.safeEndOffset(text) : raw;
    }
    _controllers[targetIdx].selection = TextSelection.collapsed(offset: offset);
    _lastArrowDecision = 'cross block $targetIdx:$offset';
    _scrollEditorBlockIntoView(targetIdx);
    _scheduleKeyboardFocusRepair(targetIdx, offset);
  }

  void _scheduleKeyboardFocusRepair(int targetIdx, int offset) {
    final token = ++_keyboardFocusRepairToken;

    void repair() {
      if (!mounted || token != _keyboardFocusRepairToken) return;
      if (targetIdx < 0 || targetIdx >= _controllers.length) return;
      final controller = _controllers[targetIdx];
      final safeOffset = offset.clamp(0, controller.text.length).toInt();
      _lastFocusedController = controller;
      if (controller.selection.baseOffset != safeOffset ||
          controller.selection.extentOffset != safeOffset) {
        controller.selection = TextSelection.collapsed(offset: safeOffset);
      }
      if (!_focusNodes[targetIdx].hasFocus) {
        _focusNodes[targetIdx].requestFocus();
      }
    }

    Future<void>.delayed(Duration.zero, repair);
    WidgetsBinding.instance.addPostFrameCallback((_) => repair());
  }
}

class _RenderCaretCandidate {
  final int raw;
  final double x;
  final double y;

  const _RenderCaretCandidate({
    required this.raw,
    required this.x,
    required this.y,
  });
}
