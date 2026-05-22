part of 'script_editor_screen.dart';

extension _ScriptEditorKeyboardNavigationParts on _ScriptEditorScreenState {
  bool _onGlobalArrowKey(KeyEvent event) {
    if (!mounted || _controllers.isEmpty) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_handleGlobalEditingShortcut(event)) return true;
    final hasEditorFocus = _focusNodes.any((n) => n.hasFocus);
    final hasAppSelectionForKeyboard =
        _isGlobalSelection || (_overlayKey.currentState?.hasSelection ?? false);
    if (!hasEditorFocus && !hasAppSelectionForKeyboard) return false;
    final key = event.logicalKey;
    final isArrowKey = _isArrowKey(key);
    final isHomeEndKey = _isHomeEndKey(key);
    if (!isArrowKey && !isHomeEndKey) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (hasEditorFocus && !hasAppSelectionForKeyboard) {
      final shouldRouteFocusedControlVertical =
          _isControlArrowModifierState(keyboard) &&
              (key == LogicalKeyboardKey.arrowUp ||
                  key == LogicalKeyboardKey.arrowDown);
      final shouldRouteFocusedHomeEnd =
          isHomeEndKey && !keyboard.isControlPressed && !keyboard.isMetaPressed;
      if (shouldRouteFocusedControlVertical || shouldRouteFocusedHomeEnd) {
        final modifier = shouldRouteFocusedHomeEnd ? 'home/end' : 'ctrl';
        _lastArrowDecision = 'focused $modifier ${key.keyLabel}: route';
        return _handleEditorArrowKey(
                _ScriptEditorScreenState._arrowKeyDummyNode, event) ==
            KeyEventResult.handled;
      }
      if (_handleNativeArrowTrapIfNeeded(event)) return true;
      // The focused block's FocusNode owns arrow tracing. Recording here too
      // creates duplicate trace files for the same physical keypress and makes
      // focus-transfer bugs look like double movement.
      return false;
    }
    if (keyboard.isShiftPressed) {
      return _extendAppSelectionForArrow(key, keyboard);
    }
    if (_clearAppSelectionForArrow(key)) return true;
    final hasModifier = _hasAnyArrowModifier(keyboard);
    final routeModifiedArrow = _shouldRouteModifiedArrow(key, keyboard);
    if (hasModifier && !routeModifiedArrow) return false;
    _lastArrowDecision = 'arrow ${key.keyLabel}: route';
    return _handleEditorArrowKey(
            _ScriptEditorScreenState._arrowKeyDummyNode, event) ==
        KeyEventResult.handled;
  }

  bool _clearStaleOverlaySelectionForShift(HardwareKeyboard keyboard) {
    if (!keyboard.isShiftPressed || _isGlobalSelection) return false;
    final overlay = _overlayKey.currentState;
    final session = overlay?.selectionSessionSnapshot;
    if (overlay == null || !(overlay.hasSelection)) return false;
    // Use the editor's synchronous focus authority, not FocusNode iteration.
    // FocusNode ownership can lag for one key repeat after app-owned
    // Ctrl/Shift selection crosses a block, which made the stale-overlay guard
    // clear a valid overlay and restart selection in the next block.
    final controller = _lastFocusedController;
    if (controller == null) {
      _shiftSelectionAnchor = null;
      _shiftSelectionFocus = null;
      overlay.clearSelection();
      for (final c in _controllers) {
        c.isGlobalSelected = false;
        c.externalSelection = null;
        c.refresh();
      }
      setState(() {
        _isGlobalSelection = false;
        _lastArrowDecision = 'shift stale overlay cleared: no focus';
      });
      return true;
    }
    final block = _controllers.indexOf(controller);
    if (block < 0) return false;
    final selection = controller.selection;
    if (!selection.isValid) {
      _shiftSelectionAnchor = null;
      _shiftSelectionFocus = null;
      overlay.clearSelection();
      for (final c in _controllers) {
        c.isGlobalSelected = false;
        c.externalSelection = null;
        c.refresh();
      }
      setState(() {
        _isGlobalSelection = false;
        _lastArrowDecision = 'shift stale overlay cleared: invalid selection';
      });
      return true;
    }
    final offset =
        selection.extentOffset.clamp(0, controller.text.length).toInt();
    final visibleOverlayRange = _hasVisibleAppSelectionRange();
    if (session != null &&
        visibleOverlayRange &&
        session.focus.block == block &&
        session.focus.offset == offset) {
      return false;
    }
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    overlay.clearSelection();
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.refresh();
    }
    setState(() {
      _isGlobalSelection = false;
      _lastArrowDecision = visibleOverlayRange
          ? 'shift stale overlay cleared focus ${session?.focus} != $block:$offset'
          : 'shift stale overlay cleared invisible at $block:$offset';
    });
    return true;
  }

  bool _hasVisibleAppSelectionRange() {
    if (_isGlobalSelection) return true;
    for (final c in _controllers) {
      if (c.isGlobalSelected) return true;
      final selection = c.externalSelection;
      if (selection != null && selection.isValid && !selection.isCollapsed) {
        return true;
      }
    }
    return false;
  }

  bool _shouldRouteModifiedArrow(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard,
  ) {
    if (_isPlainArrowModifierState(keyboard)) {
      return true;
    }
    if (keyboard.isMetaPressed) return false;
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  bool _hasAnyArrowModifier(HardwareKeyboard keyboard) =>
      keyboard.isControlPressed ||
      keyboard.isShiftPressed ||
      keyboard.isMetaPressed;

  bool _isPlainArrowModifierState(HardwareKeyboard keyboard) =>
      !_hasAnyArrowModifier(keyboard);

  bool _isAltOnlyArrowModifierState(HardwareKeyboard keyboard) =>
      keyboard.isAltPressed &&
      !keyboard.isControlPressed &&
      !keyboard.isShiftPressed &&
      !keyboard.isMetaPressed;

  bool _isControlArrowModifierState(
    HardwareKeyboard keyboard, {
    bool allowShift = true,
  }) {
    return keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        (allowShift || !keyboard.isShiftPressed);
  }

  bool _isHomeEndKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end;

  bool _isArrowKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight;

  bool _handleGlobalEditingShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final hasShortcutModifier =
        keyboard.isControlPressed || keyboard.isMetaPressed;
    if (!hasShortcutModifier || keyboard.isAltPressed) return false;
    final hasAppSelection =
        _isGlobalSelection || (_overlayKey.currentState?.hasSelection ?? false);
    if (!hasAppSelection) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyC) {
      _overlayKey.currentState?.endDragging();
      _onCopyClean();
      _lastArrowDecision = 'shortcut copy: app selection';
      return true;
    }
    if (key == LogicalKeyboardKey.keyX) {
      _overlayKey.currentState?.endDragging();
      _onCut();
      _lastArrowDecision = 'shortcut cut: app selection';
      return true;
    }
    if (key == LogicalKeyboardKey.keyV) {
      _overlayKey.currentState?.endDragging();
      unawaited(_onPaste());
      _lastArrowDecision = 'shortcut paste: app selection';
      return true;
    }
    return false;
  }

  bool _clearAppSelectionForArrow(LogicalKeyboardKey key) {
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (!_isGlobalSelection && !hasOverlay) return false;
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    final collapseToEnd = _collapseSelectionToEndForArrow(key);
    final target = _appSelectionEdge(collapseToEnd: collapseToEnd);
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      final selection = c.selection;
      if (selection.isValid && !selection.isCollapsed) {
        final offset = collapseToEnd
            ? selection.end.clamp(0, c.text.length).toInt()
            : selection.start.clamp(0, c.text.length).toInt();
        c.selection = TextSelection.collapsed(offset: offset);
      }
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.refresh();
    }
    setState(() {
      _isGlobalSelection = false;
      _lastArrowDecision = target == null
          ? 'clear selection ${key.keyLabel}: no target'
          : 'clear selection ${key.keyLabel}: ${target.block}:${target.offset}';
    });
    if (target != null) {
      _lastFocusedController = _controllers[target.block];
      _focusNodes[target.block].requestFocus();
      _controllers[target.block].selection = TextSelection.collapsed(
        offset: target.offset,
      );
      _scrollEditorBlockIntoView(target.block);
    }
    return true;
  }

  bool _collapseSelectionToEndForArrow(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.end) return true;
    if (key == LogicalKeyboardKey.home) return false;
    if (key == LogicalKeyboardKey.arrowDown) return true;
    if (key == LogicalKeyboardKey.arrowUp) return false;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return false;
    }

    final session = _overlayKey.currentState?.selectionSessionSnapshot;
    final focusBlock = session?.focus.block;
    final active = _activeController ?? _lastFocusedController;
    final activeIndex = active == null ? -1 : _controllers.indexOf(active);
    final blockIndex = focusBlock != null &&
            focusBlock >= 0 &&
            focusBlock < _controllers.length
        ? focusBlock
        : activeIndex;
    final isRtl = blockIndex >= 0 ? _editorBlockResolvedRtl(blockIndex) : false;
    if (key == LogicalKeyboardKey.arrowLeft) return isRtl;
    return !isRtl;
  }

  bool _handleNativeArrowTrapIfNeeded(KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return false;
    }
    if (!_isPlainArrowModifierState(HardwareKeyboard.instance)) return false;

    final controller = _lastFocusedController ?? _activeController;
    if (controller == null) return false;
    final blockIndex = _controllers.indexOf(controller);
    if (blockIndex < 0) return false;
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;

    _activeArrowEventSignature = _arrowEventSignature(event);
    final target = _leadingHiddenPrefixPlainHorizontalTarget(
      blockIndex: blockIndex,
      rawOffset: selection.baseOffset,
      key: key,
      isRtl: _editorBlockResolvedRtl(blockIndex),
    );
    if (target == null) return false;

    _recordNativeArrowTrace(
      event,
      mode: 'global hidden-prefix trap -> ${target.block}:${target.offset}',
    );
    if (target.block == blockIndex) {
      controller.selection = TextSelection.collapsed(offset: target.offset);
      _lastFocusedController = controller;
      _focusNodes[blockIndex].requestFocus();
    } else {
      _crossToBlock(target.block, atOffset: target.offset);
    }
    _suppressActiveArrowEventOnce();
    _lastArrowDecision =
        'hidden-prefix ${key.keyLabel}: ${target.block}:${target.offset}';
    return true;
  }

  void _suppressActiveArrowEventOnce() {
    final arrowSignature = _activeArrowEventSignature;
    if (arrowSignature == null) return;
    _suppressDuplicateArrowEventSignature = arrowSignature;
    Future<void>.delayed(Duration.zero, () {
      if (!mounted) return;
      if (_suppressDuplicateArrowEventSignature == arrowSignature) {
        _suppressDuplicateArrowEventSignature = null;
      }
    });
  }

  String _arrowEventSignature(KeyEvent event) {
    return '${event.runtimeType}:${event.logicalKey.keyId}:'
        '${event.timeStamp.inMicroseconds}';
  }

  KeyEventResult _handleEditorArrowKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (!_isArrowKey(key) && !_isHomeEndKey(key)) {
      return KeyEventResult.ignored;
    }
    final eventSignature = _arrowEventSignature(event);
    if (_suppressDuplicateArrowEventSignature == eventSignature) {
      _lastArrowDecision = 'duplicate suppressed ${key.keyLabel}';
      return KeyEventResult.handled;
    }
    _activeArrowEventSignature = eventSignature;

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
    if (_isHomeEndKey(key)) {
      return _handleHomeEndKey(
        key: key,
        controller: controller,
        blockIndex: idx,
      );
    }

    final isVerticalArrow = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    final isAltOnlyArrow = _isAltOnlyArrowModifierState(keyboard);
    final isPlainVerticalArrow =
        _isPlainArrowModifierState(keyboard) && isVerticalArrow;
    if (!isPlainVerticalArrow) {
      _verticalArrowPreferredX = null;
    }
    if (_isControlArrowModifierState(keyboard) && isVerticalArrow) {
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
      if (keyboard.isAltPressed && _isArrowKey(key)) {
        _extendAppSelectionForArrow(key, keyboard);
        return KeyEventResult.handled;
      }
    }

    if (isPlainVerticalArrow) {
      final safeOffset = controller.selection.extentOffset
          .clamp(0, controller.text.length)
          .toInt();
      final isRtl = _editorBlockResolvedRtl(idx);
      final layout = _getVerticalLayout(
        idx,
        selection: TextSelection.collapsed(
          offset: safeOffset,
          affinity: controller.selection.affinity,
        ),
      );
      final visibleText = StylingService.stripTags(controller.text);
      final currentBlockIsEmpty = visibleText.trim().isEmpty;
      final renderedX = _renderEditableCaretX(
            blockIndex: idx,
            offset: safeOffset,
          ) ??
          layout.currentX;
      final preferredX = currentBlockIsEmpty
          ? renderedX
          : _verticalArrowPreferredX ?? renderedX;
      _verticalArrowPreferredX = preferredX;
      final target = _plainShiftVerticalLineTarget(
        block: idx,
        offset: safeOffset,
        key: key,
        crossBlockOnly: !isRtl && !isAltOnlyArrow,
        preferredX: preferredX,
      );
      _recordVerticalArrowTrace(
        key: key,
        blockIndex: idx,
        rawOffset: safeOffset,
        isRtl: isRtl,
        layout: layout,
        preferredX: preferredX,
        target: target,
      );
      if (target == null) {
        if (isAltOnlyArrow) {
          _lastArrowDecision = 'alt-neutral ${key.keyLabel}: no visual target';
          return KeyEventResult.handled;
        }
        return isRtl ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      if (target.block == idx) {
        controller.selection = TextSelection.collapsed(
          offset: target.offset.clamp(0, controller.text.length).toInt(),
          affinity: key == LogicalKeyboardKey.arrowUp
              ? TextAffinity.upstream
              : TextAffinity.downstream,
        );
        _lastArrowDecision = 'visual ${key.keyLabel}: $idx:${target.offset}';
      } else {
        _crossToBlock(target.block, atOffset: target.offset);
        _lastArrowDecision =
            'visual ${key.keyLabel}: ${target.block}:${target.offset}';
      }
      return KeyEventResult.handled;
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

    // Left/Right are routed through the shared visual geometry helper. Keeping
    // raw/logical fallbacks here caused old RTL behavior to fight the rendered
    // caret positions.
    final isRtl = _editorBlockResolvedRtl(idx);
    final sel = controller.selection;
    final textLen = controller.text.length;

    return _handleHorizontalArrowKey(
          event: event,
          key: key,
          controller: controller,
          blockIndex: idx,
          isRtl: isRtl,
          selection: sel,
          textLength: textLen,
          manualInBlock: _isPlainArrowModifierState(keyboard),
        ) ??
        KeyEventResult.ignored;
  }
}
