part of 'script_editor_screen.dart';

extension _ScriptEditorSelectionClipboardParts on _ScriptEditorScreenState {
  void _onCutClean() {
    final snap = _blockClipboard;
    if (snap != null) {
      // Global cut — use blocks pre-captured at Select-All time.
      // Immune to iOS timing: _blockClipboard is set before any events fire.
      _blockClipboardTimer?.cancel();
      _blockClipboardTimer =
          Timer(const Duration(seconds: 60), () => _blockClipboard = null);
      final plain = snap
          .map((t) => StylingService.stripTags(t).replaceAll('\n', ' ').trim())
          .where((t) => t.isNotEmpty)
          .join(' ');
      Clipboard.setData(ClipboardData(text: plain));
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
    // Single-block native cut — no global selection was active.
    _onCopyClean();
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
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection || hasOverlay) {
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
    final blocks = _blockClipboard;
    if (blocks == null || blocks.isEmpty || _controllers.isEmpty) return;
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
    // Pre-capture raw markup NOW — before any iOS events can clear _isGlobalSelection.
    // Never downgrade to fewer entries: a spurious second call (via escalation after
    // _isGlobalSelection is cleared) could have fewer controllers and would overwrite
    // the correct full-script clipboard with a single-block version.
    final _snap = _controllers.map((c) => c.text).toList();
    if (_blockClipboard == null || _snap.length >= _blockClipboard!.length) {
      _blockClipboard = _snap;
      _blockClipboardTimer?.cancel();
      _blockClipboardTimer =
          Timer(const Duration(seconds: 60), () => _blockClipboard = null);
    }
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
