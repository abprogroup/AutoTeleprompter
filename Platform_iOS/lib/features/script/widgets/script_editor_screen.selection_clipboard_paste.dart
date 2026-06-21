part of 'script_editor_screen.dart';

extension _ScriptEditorSelectionClipboardPasteGlobalParts
    on _ScriptEditorScreenState {
  _BlockSelectionRange? _activePasteTargetRange() {
    final raw = _overlayKey.currentState?.currentRawRange;
    if (raw != null) {
      final range = _rangeFromOverlayRaw(raw, 'paste-overlay');
      if (range != null) return range;
    }

    final recognized = _recognizedBlockRange;
    if (recognized != null) {
      return recognized;
    }

    _BlockSelectionPoint? start;
    _BlockSelectionPoint? end;
    for (var i = 0; i < _controllers.length; i++) {
      final sel = _visibleAppSelectionForController(_controllers[i]);
      if (sel == null) continue;
      start ??= _BlockSelectionPoint(blockIndex: i, rawOffset: sel.start);
      end = _BlockSelectionPoint(blockIndex: i, rawOffset: sel.end);
    }
    if (start != null && end != null) {
      return _normalizeBlockRange(start, end, 'paste-visible-app');
    }

    final controller = _activeController;
    if (controller == null) return null;
    final blockIndex = _controllers.indexOf(controller);
    if (blockIndex < 0) return null;
    final sel = controller.selection;
    if (!sel.isValid || sel.isCollapsed) return null;
    return _normalizeBlockRange(
      _BlockSelectionPoint(blockIndex: blockIndex, rawOffset: sel.start),
      _BlockSelectionPoint(blockIndex: blockIndex, rawOffset: sel.end),
      'paste-native',
    );
  }

  int _activePasteBlockIndex() {
    final controller = _activeController;
    if (controller == null) return _controllers.isEmpty ? -1 : 0;
    final index = _controllers.indexOf(controller);
    return index < 0 ? (_controllers.isEmpty ? -1 : 0) : index;
  }

  int _activePasteOffset(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return 0;
    final controller = _controllers[blockIndex];
    final sel = controller.selection;
    if (!sel.isValid) return controller.text.length;
    return sel.extentOffset.clamp(0, controller.text.length).toInt();
  }

  void _replaceRangeWithPastedBlocks(
    _BlockSelectionRange range,
    List<String> pastedBlocks,
  ) {
    final normalized =
        _normalizeBlockRange(range.start, range.end, range.source);
    if (normalized == null || pastedBlocks.isEmpty) return;
    final start = normalized.start;
    final end = normalized.end;
    final startController = _controllers[start.blockIndex];
    final endController = _controllers[end.blockIndex];
    final before = startController.text.substring(0, start.rawOffset);
    final after = endController.text.substring(end.rawOffset);

    _isCommandExecuting = true;
    for (var i = end.blockIndex; i > start.blockIndex; i--) {
      _controllers[i].dispose();
      _focusNodes[i].dispose();
      _controllers.removeAt(i);
      _focusNodes.removeAt(i);
      _blockKeys.removeAt(i);
    }
    if (pastedBlocks.length == 1) {
      startController.value = TextEditingValue(
        text: before + pastedBlocks.first + after,
        selection: TextSelection.collapsed(
          offset: before.length + pastedBlocks.first.length,
        ),
      );
      _lastFocusedController = startController;
    } else {
      startController.value = TextEditingValue(
        text: before + pastedBlocks.first,
        selection: TextSelection.collapsed(
          offset: before.length + pastedBlocks.first.length,
        ),
      );
      for (var i = 1; i < pastedBlocks.length; i++) {
        final isLast = i == pastedBlocks.length - 1;
        _addBlock(
          start.blockIndex + i,
          text: isLast ? pastedBlocks[i] + after : pastedBlocks[i],
        );
        if (isLast) {
          _controllers[start.blockIndex + i].selection =
              TextSelection.collapsed(offset: pastedBlocks[i].length);
        }
      }
      _lastFocusedController =
          _controllers[start.blockIndex + pastedBlocks.length - 1];
    }
    _clearGlobalSelection();
    _isCommandExecuting = false;
  }

  void _insertPastedBlocksAtCursor(
    int blockIndex,
    int offset,
    List<String> pastedBlocks,
  ) {
    if (blockIndex < 0 ||
        blockIndex >= _controllers.length ||
        pastedBlocks.isEmpty) {
      return;
    }
    final controller = _controllers[blockIndex];
    final safeOffset = offset.clamp(0, controller.text.length).toInt();
    final before = controller.text.substring(0, safeOffset);
    final after = controller.text.substring(safeOffset);

    _isCommandExecuting = true;
    if (pastedBlocks.length == 1) {
      controller.value = TextEditingValue(
        text: before + pastedBlocks.first + after,
        selection: TextSelection.collapsed(
          offset: before.length + pastedBlocks.first.length,
        ),
      );
      _lastFocusedController = controller;
    } else {
      controller.value = TextEditingValue(
        text: before + pastedBlocks.first,
        selection: TextSelection.collapsed(
          offset: before.length + pastedBlocks.first.length,
        ),
      );
      for (var i = 1; i < pastedBlocks.length; i++) {
        final targetIndex = blockIndex + i;
        final isLast = i == pastedBlocks.length - 1;
        final text = isLast ? pastedBlocks[i] + after : pastedBlocks[i];
        if (targetIndex >= _controllers.length) {
          _addBlock(_controllers.length, text: text);
        } else {
          _addBlock(targetIndex, text: text);
        }
        if (isLast) {
          _controllers[targetIndex].selection =
              TextSelection.collapsed(offset: pastedBlocks[i].length);
          _lastFocusedController = _controllers[targetIndex];
        }
      }
    }
    _clearGlobalSelection();
    _isCommandExecuting = false;
  }

  void _restoreFullScriptClipboard(List<String> pastedBlocks) {
    _selectionClipboardDebug =
        'paste-full: restoring ${pastedBlocks.length} blocks into ${_controllers.length} controllers [${_blockDebugShape(pastedBlocks)}]';
    _isCommandExecuting = true;
    while (_controllers.length < pastedBlocks.length) {
      _addBlock(_controllers.length);
    }
    for (int i = 0; i < pastedBlocks.length; i++) {
      _controllers[i].value = TextEditingValue(
        text: pastedBlocks[i],
        selection: TextSelection.collapsed(offset: pastedBlocks[i].length),
      );
    }
    while (
        _controllers.length > pastedBlocks.length && _controllers.length > 1) {
      _controllers.last.dispose();
      _focusNodes.last.dispose();
      _blockKeys.removeLast();
      _controllers.removeLast();
      _focusNodes.removeLast();
    }
    _lastFocusedController =
        _controllers.isNotEmpty ? _controllers.first : null;
    _isCommandExecuting = false;
  }

  void _pasteFromGlobalClipboard() {
    var blocks = _blockClipboard;
    var kind = _blockClipboardKind;
    final protectedBlocks = _globalSelectionSnapshot;
    if (blocks == null &&
        protectedBlocks != null &&
        _hasRecentGlobalSelectionSnapshot) {
      blocks = protectedBlocks;
      kind = _BlockClipboardKind.fullScript;
    } else if (kind == _BlockClipboardKind.fullScript &&
        protectedBlocks != null &&
        _hasRecentGlobalSelectionSnapshot &&
        _isBetterBlockSnapshot(protectedBlocks, blocks)) {
      blocks = protectedBlocks;
    }
    if (blocks == null || blocks.isEmpty || _controllers.isEmpty) return;
    final pastedBlocks = List<String>.of(blocks);

    if (kind == _BlockClipboardKind.fullScript) {
      _restoreFullScriptClipboard(pastedBlocks);
    } else {
      final targetRange = _activePasteTargetRange();
      if (targetRange != null) {
        _replaceRangeWithPastedBlocks(targetRange, pastedBlocks);
        _selectionClipboardDebug =
            'paste-partial: replaced ${targetRange.source} with ${pastedBlocks.length} slices [${_blockDebugShape(pastedBlocks)}]';
      } else {
        final blockIndex = _activePasteBlockIndex();
        _insertPastedBlocksAtCursor(
          blockIndex,
          _activePasteOffset(blockIndex),
          pastedBlocks,
        );
        _selectionClipboardDebug =
            'paste-partial: inserted ${pastedBlocks.length} slices at block $blockIndex [${_blockDebugShape(pastedBlocks)}]';
      }
    }

    _setBlockClipboard(pastedBlocks, kind: kind);
    unawaited(_syncBookmarksFromEditorSigns(notify: true, save: true));
    _setEditorState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
    if (!_keyboardDismissedForSelection) {
      final focusIndex = _lastFocusedController == null
          ? -1
          : _controllers.indexOf(_lastFocusedController!);
      if (focusIndex >= 0) {
        _focusNodes[focusIndex].requestFocus();
      }
    }
    _saveHistory(description: 'Paste');
  }

  void _selectAllBlocks() {
    _isCommandExecuting = true;
    _globalSelectionLockUntil =
        DateTime.now().add(_globalSelectionNativeMenuGuard);

    // Set full-block native selection on the focused block so the soft keyboard
    // can delete the selection (backspace on a full-block selection clears it).
    // GhostSelectionControls hides the native teardrop handles so no visible
    // handles appear from this; selectionColor is transparent when isGlobalSelected.
    final active = _activeController;
    if (active != null) {
      active.selection =
          TextSelection(baseOffset: 0, extentOffset: active.text.length);
    }

    _overlayKey.currentState?.selectAll();
    _isGlobalSelection = true;
    for (final c in _controllers) {
      c.isGlobalSelected = true;
      c.externalSelection =
          TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }

    // Arm a protected raw-markup selection snapshot for iOS context-menu timing.
    // Do not write the paste clipboard here; only Cut/Copy may do that.
    _captureGlobalSelectionSnapshot('select-all');
    _isCommandExecuting = false;
    _setEditorState(() {});
    // Refresh after setState so TextFields repaint with new flags.
    for (final c in _controllers) {
      c.refresh();
    }
  }

  void _deleteGlobalSelection() {
    _isCommandExecuting = true;
    _clearRecognizedBlockRange('delete-global-selection');
    _overlayKey.currentState?.clearSelection();
    _isGlobalSelection = false;
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.text = '';
    }
    _setEditorState(() {
      while (_controllers.length > 1) {
        _controllers.last.dispose();
        _focusNodes.last.dispose();
        _blockKeys.removeLast();
        _controllers.removeLast();
        _focusNodes.removeLast();
      }
    });
    if (_focusNodes.isNotEmpty) _focusNodes.first.requestFocus();
    _isCommandExecuting = false;
    _isDirty = false;
    _saveHistory(description: 'Delete Selection');
  }

  void _clearGlobalSelection() {
    _clearRecognizedBlockRange('clear-global-selection');
    _globalSelectionLockUntil = null;
    _overlayKey.currentState?.clearSelection();
    _isGlobalSelection = false;
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      // Collapse native selection to prevent residual highlight in buildTextSpan.
      // For RTL text, use baseOffset (cursor stays at visual tap position).
      if (!c.selection.isCollapsed) {
        final collapseAt = c.selection.baseOffset.clamp(0, c.text.length);
        c.selection = TextSelection.collapsed(offset: collapseAt);
      }
    }
    _setEditorState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
    // Safety net: re-clear after Flutter's TextField processes the tap gesture,
    // which can re-establish selection in RTL blocks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bool needsRefresh = false;
      for (final c in _controllers) {
        if (c.externalSelection != null) {
          c.externalSelection = null;
          needsRefresh = true;
        }
        if (c.isGlobalSelected) {
          c.isGlobalSelected = false;
          needsRefresh = true;
        }
      }
      if (needsRefresh) {
        for (final c in _controllers) {
          c.refresh();
        }
        _setEditorState(() {});
      }
    });
  }

  /// Re-sync externalSelection after a global style operation changes text lengths.
  void _resyncGlobalSelection() {
    for (final c in _controllers) {
      c.isGlobalSelected = true;
      c.externalSelection =
          TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
    _setEditorState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
    // Recalculate overlay handle positions after layout updates with new text.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _overlayKey.currentState?.selectAll();
    });
  }
}
