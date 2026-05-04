part of 'script_editor_screen.dart';

extension _ScriptEditorScreenKeyboardNavigationParts on _ScriptEditorScreenState {
  KeyEventResult _handleEditorArrowKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }

    // Global selection short-circuit: any arrow collapses + repositions cursor.
    if (_isGlobalSelection) {
      _clearGlobalSelection();
      if (_controllers.isEmpty) return KeyEventResult.handled;
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowLeft) {
        _crossToBlock(0, atOffset: 0);
      } else {
        final last = _controllers.length - 1;
        _crossToBlock(last, atOffset: _controllers[last].text.length);
      }
      return KeyEventResult.handled;
    }

    final controller = _lastFocusedController;
    if (controller == null) return KeyEventResult.ignored;
    final idx = _controllers.indexOf(controller);
    if (idx < 0) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      return _handleControlVerticalArrowKey(
        key: key,
        controller: controller,
        blockIndex: idx,
        extendSelection: keyboard.isShiftPressed,
      );
    }

    if (keyboard.isShiftPressed) {
      final shifted = _extendNativeShiftSelectionAcrossBlockIfNeeded(
        key: key,
        keyboard: keyboard,
        controller: controller,
        blockIndex: idx,
        selection: controller.selection,
      );
      if (shifted) return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp && idx > 0) {
      final layout = _getVerticalLayout(idx);
      if (layout.isAtTop) {
        _crossToBlock(idx - 1, x: layout.currentX, atEnd: true);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.arrowDown && idx < _controllers.length - 1) {
      final layout = _getVerticalLayout(idx);
      if (layout.isAtBottom) {
        _crossToBlock(idx + 1, x: layout.currentX, atEnd: false);
        return KeyEventResult.handled;
      }
    }

    // Left/Right: Hebrew RTL needs special handling because Flutter's default
    // arrow-left maps to "logical backward" (offset--), which in RTL displays
    // visually RIGHT — opposite of what users expect. For RTL we override and
    // drive the cursor manually so left=visually-left and right=visually-right.
    final isRtl = controller.text.isHebrew;
    final sel = controller.selection;
    final textLen = controller.text.length;

    final horizontal = _handleHorizontalArrowKey(
      key: key,
      controller: controller,
      blockIndex: idx,
      isRtl: isRtl,
      selection: sel,
      textLength: textLen,
      manualInBlock: !keyboard.isControlPressed &&
          !keyboard.isAltPressed &&
          !keyboard.isMetaPressed &&
          !keyboard.isShiftPressed,
    );
    if (horizontal != null) return horizontal;

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (isRtl) {
        if (!sel.isCollapsed) {
          // Selection collapse rule: pressing left in Hebrew lands the cursor
          // at the visually-leftmost end of the selection (the higher offset).
          controller.selection = TextSelection.collapsed(offset: sel.end);
          return KeyEventResult.handled;
        }
        if (sel.baseOffset >= textLen) {
          if (idx < _controllers.length - 1) {
            _crossToBlock(idx + 1, atOffset: 0);
            return KeyEventResult.handled;
          }
          // No next block — let Flutter's default run (it will also do nothing,
          // but returning `ignored` keeps behaviour consistent with the LTR side
          // and avoids blocking any future platform shortcut dispatch).
          return KeyEventResult.ignored;
        }
        controller.selection =
            TextSelection.collapsed(offset: sel.baseOffset + 1);
        return KeyEventResult.handled;
      }
      // LTR: let Flutter default move within the block; only intercept at
      // the leftmost boundary so a long-press chains across blocks.
      if (sel.isCollapsed && sel.baseOffset == 0 && idx > 0) {
        _crossToBlock(idx - 1, atOffset: _controllers[idx - 1].text.length);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (isRtl) {
        if (!sel.isCollapsed) {
          controller.selection = TextSelection.collapsed(offset: sel.start);
          return KeyEventResult.handled;
        }
        if (sel.baseOffset <= 0) {
          if (idx > 0) {
            _crossToBlock(idx - 1, atOffset: _controllers[idx - 1].text.length);
            return KeyEventResult.handled;
          }
          // No previous block — let Flutter's default run (symmetric with LTR).
          return KeyEventResult.ignored;
        }
        controller.selection =
            TextSelection.collapsed(offset: sel.baseOffset - 1);
        return KeyEventResult.handled;
      }
      // LTR: let Flutter default handle in-block; intercept at the right edge.
      if (sel.isCollapsed &&
          sel.baseOffset == textLen &&
          idx < _controllers.length - 1) {
        _crossToBlock(idx + 1, atOffset: 0);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

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
      text.replaceAll(_ScriptEditorScreenState._keyboardBookmarkSign, '');

  int _keyboardRawToNavigationOffset(String text, int rawOffset) {
    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    var navigationOffset = 0;
    for (var i = 0; i < safeRaw; i++) {
      if (text[i] == _ScriptEditorScreenState._keyboardBookmarkSign) continue;
      navigationOffset++;
    }
    return navigationOffset;
  }

  int _keyboardNavigationToRawOffset(String text, int navigationOffset) {
    if (navigationOffset <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == _ScriptEditorScreenState._keyboardBookmarkSign) continue;
      seen++;
      if (seen >= navigationOffset) return i + 1;
    }
    return text.length;
  }

  int _keyboardNavigationSafeEndOffset(String text) {
    final navigationText = _keyboardNavigationText(text);
    return MarkupController.safeEndOffset(navigationText);
  }

  String _keyboardVisibleNavigationText(String rawText) =>
      StylingService.stripTags(rawText)
          .replaceAll(_ScriptEditorScreenState._keyboardBookmarkSign, '');

  int _keyboardRawToVisibleNavigationOffset(String rawText, int rawOffset) {
    final visibleText = StylingService.stripTags(rawText);
    final safeRaw = rawOffset.clamp(0, rawText.length).toInt();
    final visibleOffset = MarkupController.rawToVisualOffset(
      rawText,
      safeRaw,
    ).clamp(0, visibleText.length).toInt();
    var navigationOffset = 0;
    for (var i = 0; i < visibleOffset; i++) {
      if (visibleText[i] == _ScriptEditorScreenState._keyboardBookmarkSign) {
        continue;
      }
      navigationOffset++;
    }
    return navigationOffset;
  }

  int _keyboardVisibleNavigationToRawOffset(
    String rawText,
    int navigationOffset,
  ) {
    final visibleText = StylingService.stripTags(rawText);
    if (navigationOffset <= 0) {
      return MarkupController.visualToRawOffset(rawText, 0);
    }
    var seen = 0;
    for (var i = 0; i < visibleText.length; i++) {
      if (visibleText[i] == _ScriptEditorScreenState._keyboardBookmarkSign) {
        continue;
      }
      seen++;
      if (seen >= navigationOffset) {
        return MarkupController.visualToRawOffset(rawText, i + 1);
      }
    }
    return MarkupController.visualToRawOffset(rawText, visibleText.length);
  }

  bool _isKeyboardNavigationWordChar(String value) {
    if (value.isEmpty ||
        value == _ScriptEditorScreenState._keyboardBookmarkSign) {
      return false;
    }
    final code = value.codeUnitAt(0);
    final isAsciiLetter =
        (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
    final isDigit = code >= 0x30 && code <= 0x39;
    final isHebrew = code >= 0x0590 && code <= 0x05FF;
    return isAsciiLetter || isDigit || isHebrew;
  }

  ({int block, int offset})? _controlVerticalTarget({
    required int blockIndex,
    required int focusOffset,
    required bool moveUp,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    final safeFocus = focusOffset.clamp(0, text.length).toInt();
    final navigationFocus = _keyboardRawToNavigationOffset(text, safeFocus);
    if (moveUp) {
      if (navigationFocus > 0) {
        return (
          block: blockIndex,
          offset: _keyboardNavigationToRawOffset(text, 0),
        );
      }
      if (blockIndex > 0) return (block: blockIndex - 1, offset: 0);
      return null;
    }

    final navigationEnd = _keyboardNavigationSafeEndOffset(text);
    if (navigationFocus < navigationEnd) {
      return (
        block: blockIndex,
        offset: _keyboardNavigationToRawOffset(text, navigationEnd),
      );
    }
    if (blockIndex < _controllers.length - 1) {
      final nextText = _controllers[blockIndex + 1].text;
      final nextNavigationEnd = _keyboardNavigationSafeEndOffset(nextText);
      return (
        block: blockIndex + 1,
        offset: _keyboardNavigationToRawOffset(nextText, nextNavigationEnd),
      );
    }
    return null;
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
    _controllers[targetBlock].selection =
        TextSelection.collapsed(offset: targetOffset);
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
    _controllers[target.block].selection =
        TextSelection.collapsed(offset: target.offset);
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

  ({int block, int offset})? _arrowTargetFromPosition({
    required LogicalKeyboardKey key,
    required int block,
    required int offset,
    required HardwareKeyboard keyboard,
    required bool allowInBlockHorizontalStep,
    required bool allowInBlockVerticalStep,
  }) {
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (keyboard.isControlPressed) {
        return _controlVerticalTarget(
          blockIndex: block,
          focusOffset: offset,
          moveUp: key == LogicalKeyboardKey.arrowUp,
        );
      }
      return _verticalBoundaryTarget(
        blockIndex: block,
        focusOffset: offset,
        moveUp: key == LogicalKeyboardKey.arrowUp,
        allowInBlockStep: allowInBlockVerticalStep,
      );
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (keyboard.isControlPressed &&
          keyboard.isShiftPressed &&
          !keyboard.isAltPressed &&
          !keyboard.isMetaPressed) {
        return _controlShiftHorizontalTarget(
          blockIndex: block,
          rawOffset: offset,
          key: key,
        );
      }
      if (keyboard.isAltPressed &&
          !keyboard.isControlPressed &&
          !keyboard.isMetaPressed) {
        return _altHorizontalTarget(
          blockIndex: block,
          rawOffset: offset,
          key: key,
        );
      }
      return _horizontalTargetFromPosition(
        blockIndex: block,
        rawOffset: offset,
        key: key,
        allowInBlockStep: allowInBlockHorizontalStep,
      );
    }
    return null;
  }

  ({int block, int offset})? _controlShiftHorizontalTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final moveLeft = key == LogicalKeyboardKey.arrowLeft;
    final text = _controllers[blockIndex].text;
    final navigationText = _keyboardVisibleNavigationText(text);
    final navigationOffset = _keyboardRawToVisibleNavigationOffset(
      text,
      rawOffset,
    ).clamp(0, navigationText.length).toInt();

    if (moveLeft) {
      if (navigationOffset <= 0) {
        if (blockIndex <= 0) return null;
        final previousText = _controllers[blockIndex - 1].text;
        return (
          block: blockIndex - 1,
          offset: _keyboardVisibleNavigationToRawOffset(
            previousText,
            _keyboardVisibleNavigationText(previousText).length,
          ),
        );
      }

      var target = navigationOffset - 1;
      while (target >= 0 &&
          !_isKeyboardNavigationWordChar(navigationText[target])) {
        target--;
      }
      if (target < 0) {
        return (
          block: blockIndex,
          offset: _keyboardVisibleNavigationToRawOffset(text, 0),
        );
      }
      while (target > 0 &&
          _isKeyboardNavigationWordChar(navigationText[target - 1])) {
        target--;
      }
      return (
        block: blockIndex,
        offset: _keyboardVisibleNavigationToRawOffset(text, target),
      );
    }

    if (navigationOffset >= navigationText.length) {
      if (blockIndex >= _controllers.length - 1) return null;
      return (block: blockIndex + 1, offset: 0);
    }

    var target = navigationOffset;
    if (_isKeyboardNavigationWordChar(navigationText[target])) {
      while (target < navigationText.length &&
          _isKeyboardNavigationWordChar(navigationText[target])) {
        target++;
      }
    } else {
      while (target < navigationText.length &&
          !_isKeyboardNavigationWordChar(navigationText[target])) {
        target++;
      }
      while (target < navigationText.length &&
          _isKeyboardNavigationWordChar(navigationText[target])) {
        target++;
      }
    }
    return (
      block: blockIndex,
      offset: _keyboardVisibleNavigationToRawOffset(text, target),
    );
  }

  ({int block, int offset})? _altHorizontalTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    final safeOffset = rawOffset.clamp(0, text.length).toInt();
    final endOffset = MarkupController.safeEndOffset(text);
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (safeOffset > 0) return (block: blockIndex, offset: 0);
      if (blockIndex > 0) return (block: blockIndex - 1, offset: 0);
      return null;
    }
    if (safeOffset < endOffset) return (block: blockIndex, offset: endOffset);
    if (blockIndex < _controllers.length - 1) {
      final nextText = _controllers[blockIndex + 1].text;
      return (
        block: blockIndex + 1,
        offset: MarkupController.safeEndOffset(nextText),
      );
    }
    return null;
  }

  ({int block, int offset})? _verticalBoundaryTarget({
    required int blockIndex,
    required int focusOffset,
    required bool moveUp,
    required bool allowInBlockStep,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    final safeFocus = focusOffset.clamp(0, text.length).toInt();
    final endOffset = MarkupController.safeEndOffset(text);
    if (moveUp) {
      if (safeFocus > 0 && allowInBlockStep) {
        return (block: blockIndex, offset: 0);
      }
      if (safeFocus <= 0 && blockIndex > 0) {
        return (
          block: blockIndex - 1,
          offset:
              MarkupController.safeEndOffset(_controllers[blockIndex - 1].text),
        );
      }
      return null;
    }
    if (safeFocus < endOffset && allowInBlockStep) {
      return (block: blockIndex, offset: endOffset);
    }
    if (safeFocus >= endOffset && blockIndex < _controllers.length - 1) {
      return (block: blockIndex + 1, offset: 0);
    }
    return null;
  }

  ({int block, int offset})? _horizontalTargetFromPosition({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
    required bool allowInBlockStep,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final controller = _controllers[blockIndex];
    final isRtl = controller.text.isHebrew;
    final visibleText = StylingService.stripTags(controller.text);
    final visibleLength = visibleText.length;
    final safeRaw = rawOffset.clamp(0, controller.text.length).toInt();
    final visibleOffset = MarkupController.rawToVisualOffset(
      controller.text,
      safeRaw,
    ).clamp(0, visibleLength).toInt();
    final atVisibleStart = visibleOffset <= 0;
    final atVisibleEnd = visibleOffset >= visibleLength;

    if (!isRtl) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (atVisibleStart) {
          if (blockIndex <= 0) return null;
          return (
            block: blockIndex - 1,
            offset: MarkupController.safeEndOffset(
                _controllers[blockIndex - 1].text),
          );
        }
        if (!allowInBlockStep) return null;
        return (
          block: blockIndex,
          offset: MarkupController.visualToRawOffset(
            controller.text,
            (visibleOffset - 1).clamp(0, visibleLength).toInt(),
          ),
        );
      }
      if (atVisibleEnd) {
        if (blockIndex >= _controllers.length - 1) return null;
        return (block: blockIndex + 1, offset: 0);
      }
      if (!allowInBlockStep) return null;
      return (
        block: blockIndex,
        offset: MarkupController.visualToRawOffset(
          controller.text,
          (visibleOffset + 1).clamp(0, visibleLength).toInt(),
        ),
      );
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (atVisibleEnd) {
        if (blockIndex >= _controllers.length - 1) return null;
        return (block: blockIndex + 1, offset: 0);
      }
      if (!allowInBlockStep) return null;
      return (
        block: blockIndex,
        offset: MarkupController.visualToRawOffset(
          controller.text,
          (visibleOffset + 1).clamp(0, visibleLength).toInt(),
        ),
      );
    }
    if (atVisibleStart) {
      if (blockIndex <= 0) return null;
      return (
        block: blockIndex - 1,
        offset:
            MarkupController.safeEndOffset(_controllers[blockIndex - 1].text),
      );
    }
    if (!allowInBlockStep) return null;
    return (
      block: blockIndex,
      offset: MarkupController.visualToRawOffset(
        controller.text,
        (visibleOffset - 1).clamp(0, visibleLength).toInt(),
      ),
    );
  }

  KeyEventResult? _handleHorizontalArrowKey({
    required LogicalKeyboardKey key,
    required MarkupController controller,
    required int blockIndex,
    required bool isRtl,
    required TextSelection selection,
    required int textLength,
    required bool manualInBlock,
  }) {
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return null;
    }

    if (!selection.isCollapsed) {
      if (!isRtl) return KeyEventResult.ignored;
      final offset = key == LogicalKeyboardKey.arrowLeft
          ? selection.end.clamp(0, textLength).toInt()
          : selection.start.clamp(0, textLength).toInt();
      controller.selection = TextSelection.collapsed(offset: offset);
      return KeyEventResult.handled;
    }

    final keyboard = HardwareKeyboard.instance;
    final target = keyboard.isAltPressed &&
            !keyboard.isControlPressed &&
            !keyboard.isMetaPressed
        ? _altHorizontalTarget(
            blockIndex: blockIndex,
            rawOffset: selection.baseOffset,
            key: key,
          )
        : _horizontalTargetFromPosition(
            blockIndex: blockIndex,
            rawOffset: selection.baseOffset,
            key: key,
            allowInBlockStep: manualInBlock,
          );
    if (target == null) return KeyEventResult.ignored;
    if (target.block != blockIndex) {
      _crossToBlock(target.block, atOffset: target.offset);
      return KeyEventResult.handled;
    }
    controller.selection = TextSelection.collapsed(offset: target.offset);
    return KeyEventResult.handled;
  }

  /// Moves focus and the caret to [targetIdx]. Updates `_lastFocusedController`
  /// SYNCHRONOUSLY before requesting focus, so the very next KeyRepeatEvent
  /// finds the correct controller — without that sync update, a long-press
  /// can stall at a paragraph boundary because the FocusNode listener that
  /// updates `_lastFocusedController` only fires on the next microtask.
  ///
  /// Provide either [atOffset] (exact char offset) or [x] (preserve x-position
  /// across vertical jumps) + [atEnd] (true = bottom line, false = top line).
  void _crossToBlock(int targetIdx, {int? atOffset, double? x, bool? atEnd}) {
    if (targetIdx < 0 || targetIdx >= _controllers.length) return;
    _lastFocusedController = _controllers[targetIdx];
    _focusNodes[targetIdx].requestFocus();
    final text = _controllers[targetIdx].text;
    int offset;
    if (atOffset != null) {
      final raw = atOffset.clamp(0, text.length);
      // When entering a block at the END (arrowLeft cross-block), walk backward
      // past any trailing invisible tags so the cursor isn't trapped just after a
      // tag's end where MarkupController would snap it back on every arrowLeft.
      offset = (atOffset >= text.length)
          ? MarkupController.safeEndOffset(text)
          : raw;
    } else if (x != null) {
      final layout = _getVerticalLayout(targetIdx);
      offset = layout.getPositionAtX(x, fromBottom: atEnd ?? false);
    } else {
      final raw = atEnd == true ? text.length : 0;
      offset = atEnd == true ? MarkupController.safeEndOffset(text) : raw;
    }
    _controllers[targetIdx].selection = TextSelection.collapsed(offset: offset);
    _lastArrowDecision = 'cross block $targetIdx:$offset';
    _scrollEditorBlockIntoView(targetIdx);
  }
}
