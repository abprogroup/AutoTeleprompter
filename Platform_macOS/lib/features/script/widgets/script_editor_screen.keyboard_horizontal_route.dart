part of 'script_editor_screen.dart';

extension _ScriptEditorKeyboardHorizontalRoute on _ScriptEditorScreenState {
  KeyEventResult? _handleHorizontalArrowKey({
    required KeyEvent event,
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

    final keyboard = HardwareKeyboard.instance;
    if (!selection.isCollapsed) {
      if (_isControlArrowModifierState(keyboard, allowShift: false)) {
        final collapseToEnd = isRtl == (key == LogicalKeyboardKey.arrowLeft);
        final edge = collapseToEnd ? selection.end : selection.start;
        final offset = edge.clamp(0, textLength).toInt();
        _recordNativeArrowTrace(event,
            mode: 'ctrlOnlyNativeCollapse -> $offset');
        controller.selection = TextSelection.collapsed(offset: offset);
        _shiftSelectionAnchor = null;
        _shiftSelectionFocus = null;
        _lastFocusedController = controller;
        _focusNodes[blockIndex].requestFocus();
        return KeyEventResult.handled;
      }
      if (!isRtl) {
        if (keyboard.isAltPressed &&
            !keyboard.isShiftPressed &&
            !keyboard.isMetaPressed) {
          final offset = key == LogicalKeyboardKey.arrowLeft
              ? selection.start.clamp(0, textLength).toInt()
              : selection.end.clamp(0, textLength).toInt();
          _recordNativeArrowTrace(
            event,
            mode: 'focus LTR alt normalized selection collapse -> $offset',
          );
          controller.selection = TextSelection.collapsed(offset: offset);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      final offset = key == LogicalKeyboardKey.arrowLeft
          ? selection.end.clamp(0, textLength).toInt()
          : selection.start.clamp(0, textLength).toInt();
      controller.selection = TextSelection.collapsed(offset: offset);
      return KeyEventResult.handled;
    }

    final plainArrow = _isPlainArrowModifierState(keyboard);
    if (plainArrow) {
      final hiddenPrefixTarget = _leadingHiddenPrefixPlainHorizontalTarget(
        blockIndex: blockIndex,
        rawOffset: selection.baseOffset,
        key: key,
        isRtl: isRtl,
      );
      if (hiddenPrefixTarget != null) {
        _recordNativeArrowTrace(
          event,
          mode:
              'focus hidden-prefix trap -> ${hiddenPrefixTarget.block}:${hiddenPrefixTarget.offset}',
        );
        if (hiddenPrefixTarget.block == blockIndex) {
          controller.selection = TextSelection.collapsed(
            offset: hiddenPrefixTarget.offset,
          );
          _suppressActiveArrowEventOnce();
        } else {
          _crossToBlock(
            hiddenPrefixTarget.block,
            atOffset: hiddenPrefixTarget.offset,
          );
        }
        return KeyEventResult.handled;
      }

      final bookmarkTarget = _leadingBookmarkPlainHorizontalTarget(
        blockIndex: blockIndex,
        rawOffset: selection.baseOffset,
        key: key,
        isRtl: isRtl,
      );
      if (bookmarkTarget != null) {
        _recordNativeArrowTrace(
          event,
          mode:
              'focus leading-bookmark trap -> ${bookmarkTarget.block}:${bookmarkTarget.offset}',
        );
        if (bookmarkTarget.block == blockIndex) {
          controller.selection = TextSelection.collapsed(
            offset: bookmarkTarget.offset,
          );
          _suppressActiveArrowEventOnce();
        } else {
          _crossToBlock(bookmarkTarget.block, atOffset: bookmarkTarget.offset);
        }
        return KeyEventResult.handled;
      }
    }

    if (!isRtl) {
      if (keyboard.isAltPressed &&
          !keyboard.isShiftPressed &&
          !keyboard.isMetaPressed) {
        final target = _isControlArrowModifierState(
          keyboard,
          allowShift: false,
        )
            ? _controlHorizontalWordTarget(
                blockIndex: blockIndex,
                rawOffset: selection.baseOffset,
                key: key,
              )
            : _horizontalTargetFromPosition(
                blockIndex: blockIndex,
                rawOffset: selection.baseOffset,
                key: key,
                allowInBlockStep: true,
              );
        if (target == null) {
          _recordNativeArrowTrace(
            event,
            mode: 'focus LTR alt normalized no-op',
          );
          return KeyEventResult.handled;
        }
        _recordNativeArrowTrace(
          event,
          mode: 'focus LTR alt normalized -> ${target.block}:${target.offset}',
        );
        if (target.block != blockIndex) {
          _crossToBlock(target.block, atOffset: target.offset);
          return KeyEventResult.handled;
        }
        controller.selection = TextSelection.collapsed(offset: target.offset);
        _lastFocusedController = controller;
        _focusNodes[blockIndex].requestFocus();
        return KeyEventResult.handled;
      }
      if (!plainArrow) {
        if (_isControlArrowModifierState(keyboard, allowShift: false)) {
          final target = _controlHorizontalWordTarget(
            blockIndex: blockIndex,
            rawOffset: selection.baseOffset,
            key: key,
          );
          _recordNativeArrowTrace(
            event,
            mode: target == null
                ? 'ctrlWordMove no-op'
                : 'ctrlWordMove -> ${target.block}:${target.offset}',
          );
          if (target == null) return KeyEventResult.handled;
          if (target.block != blockIndex) {
            _crossToBlock(target.block, atOffset: target.offset);
          } else {
            controller.selection = TextSelection.collapsed(
              offset: target.offset,
            );
            _lastFocusedController = controller;
            _focusNodes[blockIndex].requestFocus();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      final hiddenPrefixStep = _ltrHiddenPrefixVisibleStep(
        text: controller.text,
        rawOffset: selection.baseOffset,
        key: key,
      );
      if (hiddenPrefixStep != null) {
        _recordNativeArrowTrace(
          event,
          mode: 'focus LTR hidden-prefix visible step -> $hiddenPrefixStep',
        );
        controller.selection = TextSelection.collapsed(
          offset: hiddenPrefixStep,
        );
        _lastFocusedController = controller;
        _focusNodes[blockIndex].requestFocus();
        _suppressActiveArrowEventOnce();
        return KeyEventResult.handled;
      }
      final boundaryTarget = _horizontalBoundaryTargetFromPosition(
        blockIndex: blockIndex,
        rawOffset: selection.baseOffset,
        key: key,
      );
      if (boundaryTarget == null) return KeyEventResult.ignored;
      _crossToBlock(boundaryTarget.block, atOffset: boundaryTarget.offset);
      return KeyEventResult.handled;
    }

    final isControlWordMove = _isControlArrowModifierState(keyboard);
    final target = isControlWordMove
        ? _controlHorizontalWordTarget(
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
    if (target == null) {
      if (isControlWordMove) {
        _recordNativeArrowTrace(event, mode: 'ctrlWordMove no-op');
      }
      return isRtl ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (isControlWordMove) {
      _recordNativeArrowTrace(
        event,
        mode: 'ctrlWordMove -> ${target.block}:${target.offset}',
      );
    }
    if (target.block != blockIndex) {
      _crossToBlock(target.block, atOffset: target.offset);
      return KeyEventResult.handled;
    }
    controller.selection = TextSelection.collapsed(offset: target.offset);
    return KeyEventResult.handled;
  }
}
