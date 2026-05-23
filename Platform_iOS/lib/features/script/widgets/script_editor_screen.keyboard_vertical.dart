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

  int _effectiveVisibleCaretRawOffset(String rawText, int rawOffset) {
    final visible = EditorTextGeometryService.visibleText(rawText);
    if (visible.isEmpty) return 0;
    final safeRaw = rawOffset.clamp(0, rawText.length).toInt();
    final visibleOffset = MarkupController.rawToVisualOffset(rawText, safeRaw)
        .clamp(0, visible.length)
        .toInt();
    final raw = MarkupController.visualToRawOffset(rawText, visibleOffset);
    return raw.clamp(0, rawText.length).toInt();
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

  ({int block, int offset})? _ctrlShiftVerticalTarget({
    required SelectionEndpoint anchor,
    required SelectionEndpoint focus,
    required bool moveUp,
  }) {
    if (focus.block < 0 || focus.block >= _controllers.length) return null;
    final focusSide = _compareEndpoints(focus, anchor);
    final towardAnchor =
        (focusSide > 0 && moveUp) || (focusSide < 0 && !moveUp);

    if (_isEditorBlockVisiblyBlank(focus.block)) {
      return _ctrlShiftAdjacentNonBlankGroupTarget(
        fromBlock: focus.block,
        moveUp: moveUp,
        towardAnchor: towardAnchor,
      );
    }

    final group = _nonBlankParagraphGroupForBlock(focus.block);
    final startText = _controllers[group.start].text;
    final endText = _controllers[group.end].text;
    final groupStartOffset = _blockEntryStartRawOffset(startText);
    final groupEndOffset = MarkupController.safeEndOffset(endText);
    final focusText = _controllers[focus.block].text;
    final safeFocus = focus.offset.clamp(0, focusText.length).toInt();

    if (moveUp) {
      final atGroupEnd =
          focus.block == group.end && safeFocus >= groupEndOffset;
      if (towardAnchor && atGroupEnd) {
        return _ctrlShiftAdjacentNonBlankGroupTarget(
          fromBlock: group.start,
          moveUp: true,
          towardAnchor: true,
        );
      }
      if (focus.block != group.start || safeFocus > groupStartOffset) {
        return (block: group.start, offset: groupStartOffset);
      }
      return _ctrlShiftAdjacentNonBlankGroupTarget(
        fromBlock: group.start,
        moveUp: true,
        towardAnchor: towardAnchor,
      );
    }

    final atGroupStart =
        focus.block == group.start && safeFocus <= groupStartOffset;
    if (towardAnchor && atGroupStart) {
      return _ctrlShiftAdjacentNonBlankGroupTarget(
        fromBlock: group.end,
        moveUp: false,
        towardAnchor: true,
      );
    }
    if (focus.block != group.end || safeFocus < groupEndOffset) {
      return (block: group.end, offset: groupEndOffset);
    }
    return _ctrlShiftAdjacentNonBlankGroupTarget(
      fromBlock: group.end,
      moveUp: false,
      towardAnchor: towardAnchor,
    );
  }

  ({int block, int offset})? _ctrlShiftAdjacentNonBlankGroupTarget({
    required int fromBlock,
    required bool moveUp,
    required bool towardAnchor,
  }) {
    final group = _nearestNonBlankGroup(
      startBlock: fromBlock + (moveUp ? -1 : 1),
      moveUp: moveUp,
    );
    if (group == null) return null;
    final useStartEdge = moveUp ? !towardAnchor : towardAnchor;
    final targetBlock = useStartEdge ? group.start : group.end;
    final targetText = _controllers[targetBlock].text;
    return (
      block: targetBlock,
      offset: useStartEdge
          ? _blockEntryStartRawOffset(targetText)
          : MarkupController.safeEndOffset(targetText),
    );
  }

  ({int start, int end})? _nearestNonBlankGroup({
    required int startBlock,
    required bool moveUp,
  }) {
    var block = startBlock;
    while (block >= 0 && block < _controllers.length) {
      if (!_isEditorBlockVisiblyBlank(block)) {
        return _nonBlankParagraphGroupForBlock(block);
      }
      block += moveUp ? -1 : 1;
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
