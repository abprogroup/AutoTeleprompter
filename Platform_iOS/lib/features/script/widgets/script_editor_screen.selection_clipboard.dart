part of 'script_editor_screen.dart';

extension _ScriptEditorSelectionClipboardParts on _ScriptEditorScreenState {
  static const Duration _globalSelectionSnapshotTtl = Duration(seconds: 20);

  List<String> _snapshotAllControllerMarkup() =>
      _controllers.map((c) => c.text).toList(growable: false);

  int _nonEmptyBlockCount(List<String> blocks) =>
      blocks.where((b) => b.trim().isNotEmpty).length;

  bool _isBetterBlockSnapshot(List<String> candidate, List<String>? current) {
    if (current == null) return true;
    final candidateNonEmpty = _nonEmptyBlockCount(candidate);
    final currentNonEmpty = _nonEmptyBlockCount(current);
    return candidate.length > current.length ||
        (candidate.length == current.length &&
            candidateNonEmpty >= currentNonEmpty);
  }

  void _captureGlobalSelectionSnapshot(String reason) {
    final blocks = _snapshotAllControllerMarkup();
    if (blocks.isEmpty || blocks.every((b) => b.isEmpty)) {
      _selectionClipboardDebug = '$reason: ignored empty snapshot';
      return;
    }
    if (_isBetterBlockSnapshot(blocks, _globalSelectionSnapshot)) {
      _globalSelectionSnapshot = blocks;
      _globalSelectionSnapshotAt = DateTime.now();
      _selectionClipboardDebug = '$reason: armed ${blocks.length} blocks';
    } else {
      _selectionClipboardDebug =
          '$reason: kept armed ${_globalSelectionSnapshot!.length} blocks';
    }
  }

  bool get _hasRecentGlobalSelectionSnapshot {
    final capturedAt = _globalSelectionSnapshotAt;
    return _globalSelectionSnapshot != null &&
        capturedAt != null &&
        DateTime.now().difference(capturedAt) < _globalSelectionSnapshotTtl;
  }

  bool get _hasPasteableBlockClipboard =>
      (_blockClipboard != null && _blockClipboard!.isNotEmpty) ||
      (_hasRecentGlobalSelectionSnapshot &&
          _globalSelectionSnapshot != null &&
          _globalSelectionSnapshot!.isNotEmpty);

  List<String>? _globalBlocksForCommand(String reason) {
    final allBlocksSelected = _controllers.isNotEmpty &&
        _controllers.every((c) => c.isGlobalSelected);
    if (_isGlobalSelection || allBlocksSelected) {
      final before = _globalSelectionSnapshot;
      _captureGlobalSelectionSnapshot(reason);
      final after = _globalSelectionSnapshot;
      if (before != null &&
          after != null &&
          before.length > after.length &&
          _hasRecentGlobalSelectionSnapshot) {
        return List<String>.of(before);
      }
      return after == null ? null : List<String>.of(after);
    }
    if (_hasRecentGlobalSelectionSnapshot) {
      _selectionClipboardDebug =
          '$reason: using armed ${_globalSelectionSnapshot!.length} blocks';
      return List<String>.of(_globalSelectionSnapshot!);
    }
    return null;
  }

  void _storeBlockClipboard(List<String> blocks, String reason) {
    final protectedBlocks = _globalSelectionSnapshot;
    final selectedBlocks = protectedBlocks != null &&
            _hasRecentGlobalSelectionSnapshot &&
            _isBetterBlockSnapshot(protectedBlocks, blocks)
        ? protectedBlocks
        : blocks;
    _blockClipboard = List<String>.of(selectedBlocks);
    _blockClipboardTimer?.cancel();
    _blockClipboardTimer =
        Timer(const Duration(seconds: 60), () => _blockClipboard = null);
    _selectionClipboardDebug =
        '$reason: stored ${selectedBlocks.length} blocks';
  }

  void _writePlainClipboardForBlocks(List<String> blocks) {
    final plain = blocks
        .map((t) => StylingService.stripTags(t).replaceAll('\n', ' ').trim())
        .where((t) => t.isNotEmpty)
        .join(' ');
    Clipboard.setData(ClipboardData(text: plain));
  }

  void _onCutClean() {
    final globalBlocks = _globalBlocksForCommand('cut');
    if (globalBlocks != null && globalBlocks.isNotEmpty) {
      _storeBlockClipboard(globalBlocks, 'cut');
      _writePlainClipboardForBlocks(_blockClipboard ?? globalBlocks);
      _isCommandExecuting = true;
      for (final c in _controllers) {
        c.text = '';
      }
      _clearGlobalSelection();
      _isCommandExecuting = false;
      _saveHistory(description: 'Cut');
      setState(() {});
      return;
    }

    _onCopyClean();
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (hasOverlay) {
      _isCommandExecuting = true;
      for (final c in _controllers) {
        final sel = c.externalSelection;
        if (sel == null || !sel.isValid || sel.isCollapsed) continue;
        c.value = TextEditingValue(
          text: c.text.substring(0, sel.start) + c.text.substring(sel.end),
          selection: TextSelection.collapsed(offset: sel.start),
        );
      }
      _clearGlobalSelection();
      _isCommandExecuting = false;
      _saveHistory(description: 'Cut');
      setState(() {});
      return;
    }

    final c = _activeController;
    if (c == null) return;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    c.value = TextEditingValue(
      text: c.text.substring(0, sel.start) + c.text.substring(sel.end),
      selection: TextSelection.collapsed(offset: sel.start),
    );
    _saveHistory(description: 'Cut');
  }

  void _onCopyClean() {
    final globalBlocks = _globalBlocksForCommand('copy');
    if (globalBlocks != null && globalBlocks.isNotEmpty) {
      _storeBlockClipboard(globalBlocks, 'copy');
      final copiedBlocks = _blockClipboard ?? globalBlocks;
      final plainBuf = StringBuffer();
      final htmlBuf = StringBuffer();
      for (final slice in copiedBlocks) {
        if (slice.isEmpty) continue;
        if (plainBuf.isNotEmpty) plainBuf.write('\n');
        plainBuf.write(StylingService.stripTags(slice));
        htmlBuf.write(StylingService.markupToHtml(slice));
      }
      if (plainBuf.isEmpty) return;
      RichClipboard.setHtml(
          plain: plainBuf.toString(), html: htmlBuf.toString());
      return;
    }

    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (hasOverlay) {
      final plainBuf = StringBuffer();
      final htmlBuf = StringBuffer();
      for (int i = 0; i < _controllers.length; i++) {
        final c = _controllers[i];
        final sel = c.externalSelection;
        String slice;
        if (c.isGlobalSelected || sel == null || !sel.isValid) {
          slice = c.text;
        } else if (sel.isCollapsed) {
          continue;
        } else {
          slice = c.text.substring(sel.start, sel.end);
        }
        if (slice.isEmpty) continue;
        if (plainBuf.isNotEmpty) plainBuf.write('\n');
        plainBuf.write(StylingService.stripTags(slice));
        htmlBuf.write(StylingService.markupToHtml(slice));
      }
      if (plainBuf.isEmpty) return;
      RichClipboard.setHtml(
          plain: plainBuf.toString(), html: htmlBuf.toString());
      return;
    }

    final controller = _activeController;
    if (controller == null) return;
    final slice = controller.selection.textInside(controller.text);
    if (slice.isEmpty) return;
    RichClipboard.setHtml(
      plain: StylingService.stripTags(slice),
      html: StylingService.markupToHtml(slice),
    );
  }

  void _pasteFromGlobalClipboard() {
    var blocks = _blockClipboard;
    final protectedBlocks = _globalSelectionSnapshot;
    if (protectedBlocks != null &&
        _hasRecentGlobalSelectionSnapshot &&
        _isBetterBlockSnapshot(protectedBlocks, blocks)) {
      blocks = protectedBlocks;
    }
    if (blocks == null || blocks.isEmpty || _controllers.isEmpty) return;
    _selectionClipboardDebug =
        'paste: restoring ${blocks.length} blocks into ${_controllers.length} controllers';
    _isCommandExecuting = true;
    while (_controllers.length < blocks.length) {
      _addBlock(_controllers.length);
    }
    for (int i = 0; i < blocks.length; i++) {
      _controllers[i].value = TextEditingValue(
        text: blocks[i],
        selection: TextSelection.collapsed(offset: blocks[i].length),
      );
    }
    _isCommandExecuting = false;
    setState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
    if (_focusNodes.isNotEmpty) _focusNodes.first.requestFocus();
    _saveHistory(description: 'Paste');
    _selectionClipboardDebug = 'paste: restored ${blocks.length} blocks';
  }

  void _selectAllBlocks() {
    _isCommandExecuting = true;

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
    setState(() {});
    // Refresh after setState so TextFields repaint with new flags.
    for (final c in _controllers) {
      c.refresh();
    }
  }

  void _deleteGlobalSelection() {
    _isCommandExecuting = true;
    _overlayKey.currentState?.clearSelection();
    _isGlobalSelection = false;
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.text = '';
    }
    setState(() {
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
    setState(() {});
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
        setState(() {});
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
    setState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
    // Recalculate overlay handle positions after layout updates with new text.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _overlayKey.currentState?.selectAll();
    });
  }
}
