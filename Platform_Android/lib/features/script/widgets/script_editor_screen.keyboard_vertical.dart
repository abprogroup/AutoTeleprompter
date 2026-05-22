part of 'script_editor_screen.dart';

extension _ScriptEditorKeyboardVerticalParts on _ScriptEditorScreenState {
  KeyEventResult _handleControlVerticalArrowKey({
    required LogicalKeyboardKey key,
    required MarkupController controller,
    required int blockIndex,
    required bool extendSelection,
  }) {
    final selection = controller.selection.isValid
        ? controller.selection
        : const TextSelection.collapsed(offset: 0);
    final focusOffset =
        selection.extentOffset.clamp(0, controller.text.length).toInt();
    final target = _controlVerticalTarget(
      blockIndex: blockIndex,
      focusOffset: focusOffset,
      moveUp: key == LogicalKeyboardKey.arrowUp,
    );
    if (target == null) {
      _lastArrowDecision =
          'ctrl ${key.keyLabel}: boundary $blockIndex:$focusOffset';
      return KeyEventResult.ignored;
    }

    if (_shouldCaptureArrowTrace) {
      final layout = _getVerticalLayout(
        blockIndex,
        selection: TextSelection.collapsed(
          offset: focusOffset,
          affinity: selection.affinity,
        ),
      );
      final preferredX = _renderEditableCaretX(
            blockIndex: blockIndex,
            offset: focusOffset,
          ) ??
          layout.currentX;
      _recordVerticalArrowTrace(
        key: key,
        blockIndex: blockIndex,
        rawOffset: focusOffset,
        isRtl: _editorBlockResolvedRtl(blockIndex),
        layout: layout,
        preferredX: preferredX,
        target: target,
      );
    }

    if (extendSelection) {
      final anchorOffset =
          selection.baseOffset.clamp(0, controller.text.length).toInt();
      _extendControlVerticalSelection(
        anchorBlock: blockIndex,
        anchorOffset: anchorOffset,
        targetBlock: target.block,
        targetOffset: target.offset,
      );
    } else {
      _crossToBlock(target.block, atOffset: target.offset);
    }
    _lastArrowDecision =
        'ctrl ${key.keyLabel}: ${target.block}:${target.offset}';
    return KeyEventResult.handled;
  }

  String _keyboardNavigationText(String text) =>
      text.replaceAll(_keyboardBookmarkSign, '');

  int _keyboardRawToNavigationOffset(String text, int rawOffset) {
    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    var navigationOffset = 0;
    for (var i = 0; i < safeRaw; i++) {
      if (text[i] == _keyboardBookmarkSign) continue;
      navigationOffset++;
    }
    return navigationOffset;
  }

  int _keyboardNavigationToRawOffset(String text, int navigationOffset) {
    if (navigationOffset <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == _keyboardBookmarkSign) continue;
      seen++;
      if (seen >= navigationOffset) return i + 1;
    }
    return text.length;
  }

  int _keyboardNavigationSafeEndOffset(String text) {
    final navigationText = _keyboardNavigationText(text);
    return MarkupController.safeEndOffset(navigationText);
  }

  ({int block, int offset})? _controlVerticalTarget({
    required int blockIndex,
    required int focusOffset,
    required bool moveUp,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    if (_editorBlockResolvedRtl(blockIndex)) {
      final rtlTarget = _controlVerticalRtlParagraphTarget(
        blockIndex: blockIndex,
        focusOffset: focusOffset,
        moveUp: moveUp,
      );
      if (rtlTarget != null) return rtlTarget;
    }
    final text = _controllers[blockIndex].text;
    final safeFocus = focusOffset.clamp(0, text.length).toInt();
    final blockStart = _blockEntryStartRawOffset(text);
    final blockEnd = MarkupController.safeEndOffset(text);
    if (moveUp) {
      if (safeFocus > blockStart) {
        return (block: blockIndex, offset: blockStart);
      }
      if (blockIndex > 0) {
        final previousText = _controllers[blockIndex - 1].text;
        return (
          block: blockIndex - 1,
          offset: _blockEntryStartRawOffset(previousText),
        );
      }
      return null;
    }

    if (safeFocus < blockEnd) {
      return (block: blockIndex, offset: blockEnd);
    }
    if (blockIndex < _controllers.length - 1) {
      final nextText = _controllers[blockIndex + 1].text;
      return (
        block: blockIndex + 1,
        offset: MarkupController.safeEndOffset(nextText),
      );
    }
    return null;
  }

  ({int block, int offset})? _controlVerticalRtlParagraphTarget({
    required int blockIndex,
    required int focusOffset,
    required bool moveUp,
  }) {
    if (_isEditorBlockVisiblyBlank(blockIndex)) {
      final adjacent = moveUp ? blockIndex - 1 : blockIndex + 1;
      if (adjacent < 0 || adjacent >= _controllers.length) return null;
      return _rtlControlVerticalTargetForAdjacentBlock(
        adjacent,
        moveUp: moveUp,
      );
    }

    final group = _nonBlankParagraphGroupForBlock(blockIndex);
    final currentText = _controllers[blockIndex].text;
    final safeFocus = focusOffset.clamp(0, currentText.length).toInt();

    if (moveUp) {
      final startText = _controllers[group.start].text;
      final groupStartOffset = _blockEntryStartRawOffset(startText);
      if (blockIndex != group.start || safeFocus > groupStartOffset) {
        return (block: group.start, offset: groupStartOffset);
      }
      final previous = group.start - 1;
      if (previous < 0) return null;
      return _rtlControlVerticalTargetForAdjacentBlock(
        previous,
        moveUp: true,
      );
    }

    final endText = _controllers[group.end].text;
    final groupEndOffset = MarkupController.safeEndOffset(endText);
    if (blockIndex != group.end || safeFocus < groupEndOffset) {
      return (block: group.end, offset: groupEndOffset);
    }
    final next = group.end + 1;
    if (next >= _controllers.length) return null;
    return _rtlControlVerticalTargetForAdjacentBlock(
      next,
      moveUp: false,
    );
  }

  ({int block, int offset}) _rtlControlVerticalTargetForAdjacentBlock(
    int blockIndex, {
    required bool moveUp,
  }) {
    if (_isEditorBlockVisiblyBlank(blockIndex)) {
      return (block: blockIndex, offset: 0);
    }
    final group = _nonBlankParagraphGroupForBlock(blockIndex);
    final targetBlock = moveUp ? group.start : group.end;
    final targetText = _controllers[targetBlock].text;
    return (
      block: targetBlock,
      offset: moveUp
          ? _blockEntryStartRawOffset(targetText)
          : MarkupController.safeEndOffset(targetText),
    );
  }

  bool _isEditorBlockVisiblyBlank(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return true;
    return EditorTextGeometryService.visibleText(
      _controllers[blockIndex].text,
    ).trim().isEmpty;
  }

  ({int start, int end}) _nonBlankParagraphGroupForBlock(int blockIndex) {
    var start = blockIndex.clamp(0, _controllers.length - 1).toInt();
    var end = start;
    while (start > 0 && !_isEditorBlockVisiblyBlank(start - 1)) {
      start--;
    }
    while (
        end + 1 < _controllers.length && !_isEditorBlockVisiblyBlank(end + 1)) {
      end++;
    }
    return (start: start, end: end);
  }

  void _extendControlVerticalSelection({
    required int anchorBlock,
    required int anchorOffset,
    required int targetBlock,
    required int targetOffset,
  }) {
    if (anchorBlock == targetBlock) {
      final controller = _controllers[anchorBlock];
      controller.selection = TextSelection(
        baseOffset: anchorOffset.clamp(0, controller.text.length).toInt(),
        extentOffset: targetOffset.clamp(0, controller.text.length).toInt(),
      );
      _lastFocusedController = controller;
      _focusNodes[anchorBlock].requestFocus();
      _scrollEditorBlockIntoView(anchorBlock);
      return;
    }

    _lastFocusedController = _controllers[targetBlock];
    _focusNodes[targetBlock].requestFocus();
    _controllers[targetBlock].selection = TextSelection.collapsed(
      offset: targetOffset,
    );
    _overlayKey.currentState?.setKeyboardSelection(
      anchorBlock: anchorBlock,
      anchorOffset: anchorOffset,
      focusBlock: targetBlock,
      focusOffset: targetOffset,
    );
    _scrollEditorBlockIntoView(targetBlock);
  }

  bool _extendNativeShiftSelectionAcrossBlockIfNeeded({
    required LogicalKeyboardKey key,
    required HardwareKeyboard keyboard,
    required MarkupController controller,
    required int blockIndex,
    required TextSelection selection,
  }) {
    if (!selection.isValid) return false;
    final focusOffset =
        selection.extentOffset.clamp(0, controller.text.length).toInt();
    final target = _isPlainShiftVerticalArrow(key, keyboard)
        ? _plainShiftVerticalLineTarget(
            block: blockIndex,
            offset: focusOffset,
            key: key,
            crossBlockOnly: true,
          )
        : _arrowTargetFromPosition(
            key: key,
            block: blockIndex,
            offset: focusOffset,
            keyboard: keyboard,
            allowInBlockHorizontalStep: false,
            allowInBlockVerticalStep: false,
          );
    final anchorOffset =
        selection.baseOffset.clamp(0, controller.text.length).toInt();
    if (target == null) return false;
    if (target.block == blockIndex) {
      if (target.offset == focusOffset) return false;
      controller.selection = TextSelection(
        baseOffset: anchorOffset,
        extentOffset: target.offset.clamp(0, controller.text.length).toInt(),
      );
      _lastFocusedController = controller;
      _focusNodes[blockIndex].requestFocus();
      _scrollEditorBlockIntoView(blockIndex);
      _lastArrowDecision =
          'shift same ${key.keyLabel}: $blockIndex:$anchorOffset-$blockIndex:${target.offset}';
      return true;
    }
    _lastFocusedController = _controllers[target.block];
    _focusNodes[target.block].requestFocus();
    _controllers[target.block].selection = TextSelection.collapsed(
      offset: target.offset,
    );
    _overlayKey.currentState?.setKeyboardSelection(
      anchorBlock: blockIndex,
      anchorOffset: anchorOffset,
      focusBlock: target.block,
      focusOffset: target.offset,
    );
    _scrollEditorBlockIntoView(target.block);
    _lastArrowDecision =
        'shift cross ${key.keyLabel}: $blockIndex:$anchorOffset-${target.block}:${target.offset}';
    return true;
  }

  KeyEventResult _handleHomeEndKey({
    required LogicalKeyboardKey key,
    required MarkupController controller,
    required int blockIndex,
  }) {
    final keyboard = HardwareKeyboard.instance;
    if (!_isHomeEndKey(key) ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final selection = controller.selection.isValid
        ? controller.selection
        : const TextSelection.collapsed(offset: 0);
    final focusOffset =
        selection.extentOffset.clamp(0, controller.text.length).toInt();
    final target = _homeEndTarget(
      blockIndex: blockIndex,
      rawOffset: focusOffset,
      key: key,
    );
    if (target == null) {
      _lastArrowDecision = '${key.keyLabel}: boundary';
      return KeyEventResult.handled;
    }

    final targetOffset = target.offset.clamp(0, controller.text.length).toInt();
    if (keyboard.isShiftPressed) {
      final anchorOffset =
          selection.baseOffset.clamp(0, controller.text.length).toInt();
      controller.selection = TextSelection(
        baseOffset: anchorOffset,
        extentOffset: targetOffset,
      );
    } else {
      controller.selection = TextSelection.collapsed(offset: targetOffset);
      _shiftSelectionAnchor = null;
      _shiftSelectionFocus = null;
    }
    _lastFocusedController = controller;
    _focusNodes[blockIndex].requestFocus();
    _lastArrowDecision = '${key.keyLabel}: $blockIndex:$targetOffset';
    return KeyEventResult.handled;
  }

  ({int block, int offset})? _homeEndTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final isRtl = _editorBlockResolvedRtl(blockIndex);
    final visualRight = key == LogicalKeyboardKey.home ? isRtl : !isRtl;
    if (_isEditorBlockVisiblyBlank(blockIndex)) {
      return (block: blockIndex, offset: 0);
    }
    final target = _lineEdgeTargetInBlock(
      blockIndex: blockIndex,
      rawOffset: rawOffset,
      visualRight: visualRight,
    );
    if (target != null) return target;

    final text = _controllers[blockIndex].text;
    final fallbackOffset = key == LogicalKeyboardKey.home
        ? (isRtl ? MarkupController.safeEndOffset(text) : 0)
        : (isRtl ? 0 : MarkupController.safeEndOffset(text));
    return (block: blockIndex, offset: fallbackOffset);
  }
}
