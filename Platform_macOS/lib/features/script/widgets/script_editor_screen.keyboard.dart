part of 'script_editor_screen.dart';

extension _ScriptEditorScreenKeyboardParts on _ScriptEditorScreenState {
  bool _onGlobalArrowKey(KeyEvent event) {
    if (!mounted || _controllers.isEmpty) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_handleGlobalEditingShortcut(event)) return true;
    final hasEditorFocus = _focusNodes.any((n) => n.hasFocus);
    final hasAppSelectionForKeyboard =
        _isGlobalSelection || (_overlayKey.currentState?.hasSelection ?? false);
    if (!hasEditorFocus && !hasAppSelectionForKeyboard) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) {
      return _extendAppSelectionForArrow(key, keyboard);
    }
    if (_clearAppSelectionForArrow(key)) return true;
    final hasModifier = keyboard.isControlPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
    final routeModifiedArrow = _shouldRouteModifiedArrow(key, keyboard);
    if (hasModifier && !routeModifiedArrow) return false;
    _lastArrowDecision = 'arrow ${key.keyLabel}: route';
    return _handleEditorArrowKey(
          _ScriptEditorScreenState._arrowKeyDummyNode,
          event,
        ) ==
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
    if (!keyboard.isControlPressed &&
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      return true;
    }
    if (keyboard.isMetaPressed) return false;
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

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
    final collapseToEnd = key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown;
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
      _controllers[target.block].selection =
          TextSelection.collapsed(offset: target.offset);
      _scrollEditorBlockIntoView(target.block);
    }
    return true;
  }

  ({int block, int offset})? _appSelectionEdge({
    required bool collapseToEnd,
  }) {
    ({int block, int offset})? first;
    ({int block, int offset})? last;
    for (var i = 0; i < _controllers.length; i++) {
      final c = _controllers[i];
      final sel = c.externalSelection;
      final fullBlock = c.isGlobalSelected;
      final hasRange =
          fullBlock || (sel != null && sel.isValid && !sel.isCollapsed);
      if (!hasRange) continue;
      final start = fullBlock ? 0 : sel!.start.clamp(0, c.text.length).toInt();
      final end =
          fullBlock ? c.text.length : sel!.end.clamp(0, c.text.length).toInt();
      final low = start < end ? start : end;
      final high = start > end ? start : end;
      first ??= (block: i, offset: low);
      last = (block: i, offset: high);
    }
    if (first == null || last == null) {
      final active = _activeController;
      if (active == null) return null;
      final idx = _controllers.indexOf(active);
      if (idx < 0) return null;
      final sel = active.selection;
      final offset = collapseToEnd
          ? sel.end.clamp(0, active.text.length).toInt()
          : sel.start.clamp(0, active.text.length).toInt();
      return (block: idx, offset: offset);
    }
    return collapseToEnd ? last : first;
  }

  bool _extendAppSelectionForArrow(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard,
  ) {
    final seed = _shiftSelectionSeed(keyboard);
    if (seed == null) {
      _lastArrowDecision = 'shift ${key.keyLabel}: no focused caret';
      return true;
    }
    final anchor = seed.anchor;
    final focus = seed.focus;
    final target = _shiftArrowTarget(
      key: key,
      keyboard: keyboard,
      focus: focus,
    );
    if (target == null) {
      _lastArrowDecision =
          'shift ${key.keyLabel}: boundary ${focus.block}:${focus.offset}';
      return true;
    }
    if (target.block == focus.block && target.offset == focus.offset) {
      _lastArrowDecision =
          'shift ${key.keyLabel}: unchanged ${focus.block}:${focus.offset}';
      return true;
    }
    final adjusted = _clampKeyboardTargetAtAnchor(
      anchor: anchor,
      focus: focus,
      target: SelectionEndpoint(block: target.block, offset: target.offset),
    );
    if (_sameEndpoint(anchor, adjusted)) {
      _collapseAppSelectionTo(anchor,
          reason: 'extend-collapse ${key.keyLabel}');
      return true;
    }
    _setAppSelectionFromAnchorToFocus(anchor, adjusted);
    _lastArrowDecision =
        'extend ${key.keyLabel}: ${anchor.block}:${anchor.offset}-${adjusted.block}:${adjusted.offset}';
    return true;
  }

  ({SelectionEndpoint anchor, SelectionEndpoint focus})? _shiftSelectionSeed(
    HardwareKeyboard keyboard,
  ) {
    final visibleOverlayRange = _hasVisibleAppSelectionRange();
    final session = _overlayKey.currentState?.selectionSessionSnapshot;
    if (visibleOverlayRange && session != null) {
      _shiftSelectionAnchor = session.anchor;
      _shiftSelectionFocus = session.focus;
      return (anchor: session.anchor, focus: session.focus);
    }
    final rememberedAnchor = _shiftSelectionAnchor;
    final rememberedFocus = _shiftSelectionFocus;
    if (visibleOverlayRange &&
        rememberedAnchor != null &&
        rememberedFocus != null) {
      return (anchor: rememberedAnchor, focus: rememberedFocus);
    }
    _clearStaleOverlaySelectionForShift(keyboard);
    final controller = _lastFocusedController ?? _activeController;
    if (controller == null) return null;
    final block = _controllers.indexOf(controller);
    if (block < 0) return null;
    final selection = controller.selection.isValid
        ? controller.selection
        : const TextSelection.collapsed(offset: 0);
    final realAnchor = SelectionEndpoint(
      block: block,
      offset: selection.baseOffset.clamp(0, controller.text.length).toInt(),
    );
    final realFocus = SelectionEndpoint(
      block: block,
      offset: selection.extentOffset.clamp(0, controller.text.length).toInt(),
    );
    final currentVisibleOverlayRange = _hasVisibleAppSelectionRange();
    if (session != null &&
        currentVisibleOverlayRange &&
        _sameEndpoint(session.focus, realFocus)) {
      return (anchor: session.anchor, focus: session.focus);
    }
    if (currentVisibleOverlayRange || _isGlobalSelection) {
      _overlayKey.currentState?.clearSelection();
      for (final c in _controllers) {
        c.isGlobalSelected = false;
        c.externalSelection = null;
        c.refresh();
      }
      _isGlobalSelection = false;
    }
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    return (anchor: realAnchor, focus: realFocus);
  }

  ({int block, int offset})? _shiftArrowTarget({
    required LogicalKeyboardKey key,
    required HardwareKeyboard keyboard,
    required SelectionEndpoint focus,
  }) {
    if (_isPlainShiftVerticalArrow(key, keyboard)) {
      return _plainShiftVerticalLineTarget(
        block: focus.block,
        offset: focus.offset,
        key: key,
      );
    }
    return _arrowTargetFromPosition(
      key: key,
      block: focus.block,
      offset: focus.offset,
      keyboard: keyboard,
      allowInBlockHorizontalStep:
          !keyboard.isControlPressed && !keyboard.isAltPressed,
      allowInBlockVerticalStep: true,
    );
  }

  bool _isPlainShiftVerticalArrow(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard,
  ) {
    return keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown);
  }

  ({int block, int offset})? _plainShiftVerticalLineTarget({
    required int block,
    required int offset,
    required LogicalKeyboardKey key,
    bool crossBlockOnly = false,
  }) {
    if (block < 0 || block >= _controllers.length) return null;
    final moveUp = key == LogicalKeyboardKey.arrowUp;
    final controller = _controllers[block];
    final safeOffset = offset.clamp(0, controller.text.length).toInt();
    final layout = _getVerticalLayout(
      block,
      selection: TextSelection.collapsed(offset: safeOffset),
    );
    final preferredX = layout.currentX;
    if (controller.text.isEmpty) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: moveUp,
        preferredX: preferredX,
      );
    }

    final plainText = layout.painter.text?.toPlainText() ?? '';
    if (plainText.isEmpty) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: moveUp,
        preferredX: preferredX,
      );
    }

    final painterOffset = safeOffset.clamp(0, plainText.length).toInt();
    final line = layout.painter.getLineBoundary(
      TextPosition(offset: painterOffset),
    );
    if (moveUp && line.start <= 0) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: true,
        preferredX: preferredX,
      );
    }
    if (!moveUp && line.end >= plainText.length) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: false,
        preferredX: preferredX,
      );
    }
    if (crossBlockOnly) return null;

    final targetOffset = layout
        .getPositionOnAdjacentLineAtX(preferredX, moveUp: moveUp)
        ?.clamp(0, controller.text.length)
        .toInt();
    if (targetOffset == null) return null;
    if (targetOffset == safeOffset) return null;
    return (block: block, offset: targetOffset);
  }

  ({int block, int offset})? _plainShiftVerticalCrossBlockTarget({
    required int fromBlock,
    required bool moveUp,
    required double preferredX,
  }) {
    final targetBlock = moveUp ? fromBlock - 1 : fromBlock + 1;
    if (targetBlock < 0 || targetBlock >= _controllers.length) return null;
    final targetController = _controllers[targetBlock];
    if (targetController.text.isEmpty) {
      return (block: targetBlock, offset: 0);
    }
    final fallbackOffset =
        moveUp ? MarkupController.safeEndOffset(targetController.text) : 0;
    final layout = _getVerticalLayout(
      targetBlock,
      selection: TextSelection.collapsed(offset: fallbackOffset),
    );
    final offset = layout
        .getPositionAtX(preferredX, fromBottom: moveUp)
        .clamp(0, targetController.text.length)
        .toInt();
    return (block: targetBlock, offset: offset);
  }

  bool _sameEndpoint(SelectionEndpoint a, SelectionEndpoint b) =>
      a.block == b.block && a.offset == b.offset;

  int _compareEndpoints(SelectionEndpoint a, SelectionEndpoint b) {
    if (a.block != b.block) return a.block.compareTo(b.block);
    return a.offset.compareTo(b.offset);
  }

  SelectionEndpoint _clampKeyboardTargetAtAnchor({
    required SelectionEndpoint anchor,
    required SelectionEndpoint focus,
    required SelectionEndpoint target,
  }) {
    final focusSide = _compareEndpoints(focus, anchor);
    final targetSide = _compareEndpoints(target, anchor);
    if (focusSide == 0 || targetSide == 0) return target;
    if ((focusSide < 0 && targetSide > 0) ||
        (focusSide > 0 && targetSide < 0)) {
      return anchor;
    }
    return target;
  }

  void _setAppSelectionFromAnchorToFocus(
    SelectionEndpoint anchor,
    SelectionEndpoint focus,
  ) {
    _shiftSelectionAnchor = anchor;
    _shiftSelectionFocus = focus;
    _lastFocusedController = _controllers[focus.block];
    _focusNodes[focus.block].requestFocus();
    _controllers[focus.block].selection =
        TextSelection.collapsed(offset: focus.offset);
    _overlayKey.currentState?.setKeyboardSelection(
      anchorBlock: anchor.block,
      anchorOffset: anchor.offset,
      focusBlock: focus.block,
      focusOffset: focus.offset,
    );
    _scrollEditorBlockIntoView(focus.block);
  }

  void _collapseAppSelectionTo(SelectionEndpoint target,
      {required String reason}) {
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.refresh();
    }
    setState(() {
      _isGlobalSelection = false;
      _lastArrowDecision = '$reason: ${target.block}:${target.offset}';
    });
    _lastFocusedController = _controllers[target.block];
    _focusNodes[target.block].requestFocus();
    _controllers[target.block].selection =
        TextSelection.collapsed(offset: target.offset);
    _scrollEditorBlockIntoView(target.block);
  }

}
