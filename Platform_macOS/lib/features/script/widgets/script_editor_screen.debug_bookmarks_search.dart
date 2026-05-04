part of 'script_editor_screen.dart';

extension _ScriptEditorDebugBookmarkSearchParts on _ScriptEditorScreenState {
  Widget _buildDebugSentry() {
    final activeIdx = _focusNodes.indexWhere((n) => n.hasFocus);
    final sel = _activeController?.selection;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 1)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚙️ EDITOR SENTRY',
              style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text('Blocks: ${_controllers.length}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Active Block: ${activeIdx != -1 ? activeIdx : "None"}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          if (sel != null)
            Text('Cursor: [${sel.baseOffset}, ${sel.extentOffset}]',
                style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Global Selection: $_isGlobalSelection',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Overlay: ${_overlayKey.currentState?.debugSelectionSummary ?? "None"}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Arrow: $_lastArrowDecision',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('History States: ${_history.length}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }

  /// Called on pointer-up to promote the final native selection (after any
  /// drag gesture) into the overlay handles. Only fires if:
  ///  - no global selection is active
  ///  - overlay has no existing selection (cross-block drag already set it)
  ///  - a focused block has a non-collapsed, partial (not full-block) selection
  void _promoteNativeSelectionToOverlay() {
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
      if (!sel.isValid || sel.isCollapsed) continue;
      if (sel.start == 0 && sel.end == _controllers[i].text.length) continue;
      _extendNativeSelectionToOverlay(i);
      return;
    }
  }

  /// Promotes a native single-block partial selection into the app overlay so
  /// that handles appear after double-click or drag-to-select inside one block.
  void _extendNativeSelectionToOverlay(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return;
    if (_isGlobalSelection || _isCommandExecuting) return;
    final overlay = _overlayKey.currentState;
    if (overlay == null ||
        overlay.hasSelection ||
        overlay.isHandleInteractionActive) {
      return;
    }
    final controller = _controllers[blockIndex];
    final selection  = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = selection.start.clamp(0, controller.text.length).toInt();
    final end   = selection.end  .clamp(0, controller.text.length).toInt();
    if (start == end) return;
    if (start == 0 && end == controller.text.length) return;
    _lastFocusedController = controller;
    overlay.extendNativeBlockSelection(
      blockIndex, TextSelection(baseOffset: start, extentOffset: end),
    );
  }

  void _onCopyClean() {
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection || hasOverlay) {
      final plainBuf = StringBuffer();
      final htmlBuf = StringBuffer();
      final markupBuf = StringBuffer();
      for (int i = 0; i < _controllers.length; i++) {
        final c = _controllers[i];
        final sel = c.externalSelection;
        String slice;
        if (c.isGlobalSelected || (sel != null && sel.isValid && !sel.isCollapsed)) {
          if (c.isGlobalSelected || sel == null || !sel.isValid) {
            slice = c.text;
          } else {
            slice = c.text.substring(sel.start, sel.end);
          }
          // Include empty blocks as empty lines — do NOT skip them.
          // Skipping would collapse "line A\n\nline B" into "line A\nline B",
          // losing the empty paragraph.
          if (plainBuf.isNotEmpty) {
            plainBuf.write('\n');
            markupBuf.write('\n');
          }
          plainBuf.write(StylingService.stripTags(slice));
          htmlBuf.write(StylingService.markupToHtml(slice));
          markupBuf.write(slice);
        }
      }
      // Guard: nothing was selected at all (no blocks contributed)
      if (plainBuf.isEmpty && markupBuf.isEmpty) return;
      RichClipboard.setHtml(
        plain: plainBuf.toString(),
        html: htmlBuf.toString(),
        markup: markupBuf.toString(),
      );
      _startClipboardGuard(plainBuf.toString());
      return;
    }
    final controller = _activeController;
    if (controller == null) return;
    final slice = controller.selection.textInside(controller.text);
    if (slice.isEmpty) return;
    final plain = StylingService.stripTags(slice);
    RichClipboard.setHtml(
      plain: plain,
      html: StylingService.markupToHtml(slice),
      markup: slice,
    );
    _startClipboardGuard(plain);
  }

  void _onCut() {
    _onCopyClean();
    _deleteSelection(isCut: true);
  }

  void _deleteSelection({bool isCut = false}) {
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection || hasOverlay) {
      setState(() => _isCommandExecuting = true);
      final List<int> toRemove = [];
      for (int i = 0; i < _controllers.length; i++) {
        final c = _controllers[i];
        final sel = c.externalSelection;
        if (c.isGlobalSelected) {
          toRemove.add(i);
        } else if (sel != null && sel.isValid && !sel.isCollapsed) {
          final before = c.text.substring(0, sel.start);
          final rawAfter = c.text.substring(sel.end);
          final openPrefix = sel.start == 0
              ? MarkupController.openTagsAt(c.text, sel.end)
              : '';
          final after = openPrefix + rawAfter;
          c.text = before + after;
          // Place cursor at the start of the deleted range so it stays at
          // the cut point rather than jumping to the native selection endpoint.
          final cursorAt = (sel.start + openPrefix.length)
              .clamp(0, c.text.length);
          c.selection = TextSelection.collapsed(offset: cursorAt);
          c.externalSelection = null;
          c.refresh();
        }
      }
      // Remove blocks that were fully selected
      if (toRemove.isNotEmpty && _controllers.length > toRemove.length) {
        for (final idx in toRemove.reversed) {
          _removeBlock(idx);
        }
      } else if (toRemove.length == _controllers.length) {
        // Clear all but first
        for (int i = _controllers.length - 1; i > 0; i--) _removeBlock(i);
        _controllers.first.clear();
        _controllers.first.refresh();
      }
      _clearGlobalSelection();
      setState(() => _isCommandExecuting = false);
      _saveHistory(description: isCut ? 'Cut' : 'Delete Selection');
    } else {
      final c = _activeController;
      if (c != null && !c.selection.isCollapsed) {
        final sel = c.selection;
        final before = c.text.substring(0, sel.start);
        final rawAfter = c.text.substring(sel.end);
        final after = sel.start == 0
            ? MarkupController.openTagsAt(c.text, sel.end) + rawAfter
            : rawAfter;
        c.value = TextEditingValue(
          text: before + after,
          selection: TextSelection.collapsed(offset: sel.start),
        );
        _saveHistory(description: isCut ? 'Cut' : 'Delete');
      }
    }
  }

  Future<void> _onPaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;

    // v4.1.13: Use internal markup if the system clipboard matches our clean text.
    // This allows style preservation within the app while keeping system clipboard clean.
    // Normalize line endings: Windows clipboard returns \r\n, but our internal
    // buffer uses \n. Without normalization, multi-block pastes (and any text
    // the OS canonicalizes) miss the match and lose styling.
    String text = data!.text!;
    final normalizedClipboard = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final internalMarkup = RichClipboard.internalMarkup;
    if (internalMarkup != null) {
      final cleanInternal = StylingService.stripTags(internalMarkup);
      // Compare after stripping trailing newlines: some OS clipboard implementations
      // drop the trailing '\n' from multi-block copies that end with an empty block,
      // causing a mismatch that makes the paste lose the last empty paragraph.
      final cmpInternal = cleanInternal.trimRight();
      final cmpClipboard = normalizedClipboard.trimRight();
      if (cmpInternal == cmpClipboard) {
        text = internalMarkup; // use full markup including any trailing empty block
      } else {
        text = normalizedClipboard;
      }
    } else {
      text = normalizedClipboard;
    }

    // 1. Delete selection if any
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection ||
        hasOverlay ||
        (_activeController != null && !_activeController!.selection.isCollapsed)) {
      _deleteSelection();
    }

    // 2. Insert text
    final c = _activeController;
    if (c != null) {
      final sel = c.selection;
      final oldText = c.text;
      final before = oldText.substring(0, sel.start);
      final after = oldText.substring(sel.end);

      if (text.contains('\n')) {
        // Multi-line paste: split into blocks
        final lines = text.split('\n');
        final currentIdx = _controllers.indexOf(c);
        if (currentIdx != -1) {
          setState(() {
            // Update first block
            c.text = before + lines[0];
            // Insert intermediate blocks
            for (int i = 1; i < lines.length - 1; i++) {
              _addBlock(currentIdx + i, text: lines[i]);
            }
            // Insert last block with remainder of original block
            final lastLine = lines.last + after;
            _addBlock(currentIdx + lines.length - 1, text: lastLine);

            // Focus end of paste
            final targetIdx = currentIdx + lines.length - 1;
            Future.delayed(Duration.zero, () {
              if (mounted) {
                _focusNodes[targetIdx].requestFocus();
                _controllers[targetIdx].selection =
                    TextSelection.collapsed(offset: lines.last.length);
              }
            });
          });
        }
      } else {
        c.value = TextEditingValue(
          text: before + text + after,
          selection: TextSelection.collapsed(offset: sel.start + text.length),
        );
      }
      _saveHistory(description: 'Paste');
    }
  }



  void _selectAllBlocks() {
    _overlayKey.currentState?.selectAll();
    _isGlobalSelection = true;
    for (final c in _controllers) {
      c.isGlobalSelected = true;
      c.externalSelection =
          TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
    setState(() {});
    // Refresh after setState so TextFields repaint with new flags.
    for (final c in _controllers) {
      c.refresh();
    }
  }


  /// Re-sync externalSelection after a global style operation changes text lengths.
  void _resyncGlobalSelection() {
    // If the overlay has a selection, refresh its boundaries so handles don't stay
    // at the pre-tag-insertion character offsets which are now mid-sentence.
    if (_overlayKey.currentState?.hasSelection ?? false) {
      _overlayKey.currentState?.selectAll();
    }
    for (final c in _controllers) {
      c.isGlobalSelected = true;
      c.externalSelection =
          TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
    setState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
  }
}
