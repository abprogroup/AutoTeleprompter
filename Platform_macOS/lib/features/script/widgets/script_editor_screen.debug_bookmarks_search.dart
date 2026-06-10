part of 'script_editor_screen.dart';

extension _ScriptEditorDebugBookmarkSearchParts on _ScriptEditorScreenState {
  /// Called on pointer-up to promote the final native selection (after any
  /// drag gesture) into the overlay handles. Only fires if:
  ///  - no global selection is active
  ///  - overlay has no existing selection (cross-block drag already set it)
  ///  - a focused block has a non-collapsed, partial (not full-block) selection
  void _promoteNativeSelectionToOverlay({
    String gestureKind = 'nativeDrag',
  }) {
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
      if (gestureKind == 'tripleClickBlock') {
        _extendNativeSelectionToOverlay(i, gestureKind: gestureKind);
        _recordSelectionTrace(
          'native selection promoted',
          gestureKind: gestureKind,
          nativeSelection: sel.isValid ? sel : null,
        );
        return;
      }
      if (!sel.isValid || sel.isCollapsed) continue;
      if (sel.start == 0 && sel.end == _controllers[i].text.length) continue;
      _extendNativeSelectionToOverlay(i, gestureKind: gestureKind);
      _recordSelectionTrace(
        'native selection promoted',
        anchor: null,
        focus: null,
        gestureKind: gestureKind,
        nativeSelection: sel,
      );
      return;
    }
  }

  /// Promotes a native single-block partial selection into the app overlay so
  /// that handles appear after double-click or drag-to-select inside one block.
  void _extendNativeSelectionToOverlay(
    int blockIndex, {
    String gestureKind = 'nativeDrag',
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return;
    if (_isGlobalSelection || _isCommandExecuting) return;
    final overlay = _overlayKey.currentState;
    if (overlay == null ||
        overlay.hasSelection ||
        overlay.isHandleInteractionActive) {
      return;
    }
    final controller = _controllers[blockIndex];
    final selection = controller.selection;
    if (gestureKind == 'tripleClickBlock') {
      final end = controller.text.length;
      _shiftSelectionAnchor = SelectionEndpoint(block: blockIndex, offset: 0);
      _shiftSelectionFocus = SelectionEndpoint(block: blockIndex, offset: end);
      _lastFocusedController = controller;
      overlay.setKeyboardSelection(
        anchorBlock: blockIndex,
        anchorOffset: 0,
        focusBlock: blockIndex,
        focusOffset: end,
      );
      return;
    }
    if (!selection.isValid || selection.isCollapsed) return;
    final start = selection.start.clamp(0, controller.text.length).toInt();
    final end = selection.end.clamp(0, controller.text.length).toInt();
    if (start == end) return;
    if (start == 0 &&
        end == controller.text.length &&
        gestureKind != 'doubleClickWord') {
      return;
    }
    final promotedSelection = gestureKind == 'doubleClickWord'
        ? _doubleClickWordSelection(controller.text, selection)
        : TextSelection(baseOffset: start, extentOffset: end);
    _lastFocusedController = controller;
    _shiftSelectionAnchor = SelectionEndpoint(
      block: blockIndex,
      offset: promotedSelection.baseOffset,
    );
    _shiftSelectionFocus = SelectionEndpoint(
      block: blockIndex,
      offset: promotedSelection.extentOffset,
    );
    overlay.extendNativeBlockSelection(
      blockIndex,
      promotedSelection,
      allowFullBlock: gestureKind == 'doubleClickWord',
    );
  }

  void _registerEditorPrimaryClick(PointerDownEvent event) {
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    const maxClickGap = Duration(milliseconds: 500);
    const maxClickDistance = 8.0;
    final lastTime = _lastEditorPrimaryClickTime;
    final lastPosition = _lastEditorPrimaryClickPosition;
    final repeated = lastTime != null &&
        lastPosition != null &&
        event.timeStamp - lastTime <= maxClickGap &&
        (event.position - lastPosition).distance <= maxClickDistance;
    _editorPrimaryClickCount = repeated ? _editorPrimaryClickCount + 1 : 1;
    if (_editorPrimaryClickCount > 3) _editorPrimaryClickCount = 1;
    _lastEditorPrimaryClickTime = event.timeStamp;
    _lastEditorPrimaryClickPosition = event.position;
    _pendingNativeSelectionGestureKind = switch (_editorPrimaryClickCount) {
      2 => 'doubleClickWord',
      3 => 'tripleClickBlock',
      _ => 'nativeDrag',
    };
  }

  bool _hasAppSelectionForPointerReplacement() {
    if (_isGlobalSelection ||
        (_overlayKey.currentState?.hasSelection ?? false)) {
      return true;
    }
    for (final controller in _controllers) {
      final external = controller.externalSelection;
      final native = controller.selection;
      if (controller.isGlobalSelected) return true;
      if (external != null && external.isValid && !external.isCollapsed) {
        return true;
      }
      if (native.isValid && !native.isCollapsed) return true;
    }
    return false;
  }

  void _clearAppSelectionForPointerReplacement({
    String reason = 'replaceAppSelection',
  }) {
    _overlayKey.currentState?.clearSelection();
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    for (final controller in _controllers) {
      controller.isGlobalSelected = false;
      controller.externalSelection = null;
      controller.externalVisibleSelection = null;
      final native = controller.selection;
      if (native.isValid && !native.isCollapsed) {
        final collapseAt = native.extentOffset.clamp(0, controller.text.length);
        controller.selection = TextSelection.collapsed(offset: collapseAt);
      }
      controller.refresh();
    }
    if (!mounted) return;
    _setEditorState(() {
      _isGlobalSelection = false;
    });
    _recordSelectionTrace(reason);
  }

  TextSelection _doubleClickWordSelection(
    String rawText,
    TextSelection nativeSelection,
  ) {
    final start = nativeSelection.start.clamp(0, rawText.length).toInt();
    final end = nativeSelection.end.clamp(0, rawText.length).toInt();
    if (start == end) return nativeSelection;
    final visible = EditorTextGeometryService.visibleText(rawText);
    if (visible.isEmpty) {
      return TextSelection(baseOffset: start, extentOffset: end);
    }
    final visibleStart = MarkupController.rawToVisualOffset(rawText, start)
        .clamp(
          0,
          visible.length,
        )
        .toInt();
    final visibleEnd = MarkupController.rawToVisualOffset(rawText, end)
        .clamp(
          0,
          visible.length,
        )
        .toInt();
    final probe = _doubleClickWordProbe(
      visible,
      visibleStart,
      visibleEnd,
    );
    if (probe == null) {
      return TextSelection(baseOffset: start, extentOffset: end);
    }
    var wordStart = probe;
    var wordEnd = probe + 1;
    while (wordStart > 0 && _isEditorWordChar(visible[wordStart - 1])) {
      wordStart--;
    }
    while (wordEnd < visible.length && _isEditorWordChar(visible[wordEnd])) {
      wordEnd++;
    }
    final rawStart = MarkupController.visualToRawOffset(rawText, wordStart)
        .clamp(0, rawText.length)
        .toInt();
    final rawEnd = MarkupController.visualToRawOffset(rawText, wordEnd)
        .clamp(0, rawText.length)
        .toInt();
    if (rawStart >= rawEnd) {
      return TextSelection(baseOffset: start, extentOffset: end);
    }
    return TextSelection(baseOffset: rawStart, extentOffset: rawEnd);
  }

  int? _doubleClickWordProbe(String visible, int start, int end) {
    if (start < visible.length && _isEditorWordChar(visible[start])) {
      return start;
    }
    if (start > 0 && _isEditorWordChar(visible[start - 1])) {
      return start - 1;
    }
    final safeEnd = end.clamp(start, visible.length).toInt();
    for (var i = start; i < safeEnd; i++) {
      if (_isEditorWordChar(visible[i])) return i;
    }
    return null;
  }

  bool _isEditorWordChar(String char) {
    if (char.trim().isEmpty || char.isEmpty) return false;
    final code = char.runes.first;
    if (code >= 0x30 && code <= 0x39) return true;
    if (code >= 0x41 && code <= 0x5A) return true;
    if (code >= 0x61 && code <= 0x7A) return true;
    if (code == 0x5F) return true;
    if (code >= 0x0590 && code <= 0x05FF) return true;
    if (code >= 0x0600 && code <= 0x06FF) return true;
    return false;
  }
}
