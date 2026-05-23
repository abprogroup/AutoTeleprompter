part of 'script_editor_screen.dart';

extension _ScriptEditorDebugBookmarkSearchParts on _ScriptEditorScreenState {
  Widget _buildDebugSentry() {
    if (_debugSentryCollapsed) {
      return Material(
        color: Colors.transparent,
        child: Tooltip(
          message: 'Show Editor Sentry',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _setEditorState(() => _debugSentryCollapsed = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bug_report_outlined,
                      color: Colors.amber, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'SENTRY',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final activeIdx = _focusNodes.indexWhere((n) => n.hasFocus);
    final sel = _activeController?.selection;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 1)
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 360),
        child: SingleChildScrollView(
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
              Text(
                  'Overlay: ${_overlayKey.currentState?.debugSelectionSummary ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text('Arrow: $_lastArrowDecision',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Arrow Trace PNG: ${_lastArrowTraceScreenshotPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text('Arrow Trace Log: ${_lastArrowTraceLogPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Highlight Trace PNG: ${_lastHighlightTraceScreenshotPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Highlight Trace Log: ${_lastHighlightTraceLogPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Selection Trace PNG: ${_lastSelectionTraceScreenshotPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text(
                  'Selection Trace Log: ${_lastSelectionTraceLogPath ?? "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              Text('History States: ${_history.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () =>
                        _setEditorState(() => _debugSentryCollapsed = true),
                    icon: const Icon(Icons.expand_more, size: 14),
                    label: const Text(
                      'Minimize',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _copyLastArrowTrace,
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text(
                      'Copy Trace',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _openArrowTraceFolder,
                    icon: const Icon(Icons.folder_open, size: 14),
                    label: const Text(
                      'Open Trace Folder',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _captureCurrentHighlightTrace,
                    icon: const Icon(Icons.highlight_alt, size: 14),
                    label: const Text(
                      'Highlight Trace',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _copyLastHighlightTrace,
                    icon: const Icon(Icons.copy_all, size: 14),
                    label: const Text(
                      'Copy Highlight',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _openSelectionTraceFolder,
                    icon: const Icon(Icons.folder_copy, size: 14),
                    label: const Text(
                      'Open Selection',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _copyLastSelectionTrace,
                    icon: const Icon(Icons.copy_all, size: 14),
                    label: const Text(
                      'Copy Selection',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _lastSelectionTrace,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _lastHighlightTrace,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _lastArrowTrace,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Called on pointer-up to promote the final native selection (after any
  /// drag gesture) into the overlay handles. Only fires if:
  ///  - no global selection is active
  ///  - overlay has no existing selection (cross-block drag already set it)
  ///  - a focused block has a non-collapsed, partial (not full-block) selection
  void _promoteNativeSelectionToOverlay({
    String gestureKind = 'nativeDrag',
  }) {
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
      if (gestureKind == 'tripleClickBlock') {
        _extendNativeSelectionToOverlay(i, gestureKind: gestureKind);
        _recordSelectionTrace(
          'native selection promoted',
          gestureKind: gestureKind,
          nativeSelection: sel.isValid ? sel : null,
        );
        return;
      }
      if (!sel.isValid || sel.isCollapsed) continue;
      if (sel.start == 0 && sel.end == _controllers[i].text.length) continue;
      _extendNativeSelectionToOverlay(i, gestureKind: gestureKind);
      _recordSelectionTrace(
        'native selection promoted',
        anchor: null,
        focus: null,
        gestureKind: gestureKind,
        nativeSelection: sel,
      );
      return;
    }
  }

  /// Promotes a native single-block partial selection into the app overlay so
  /// that handles appear after double-click or drag-to-select inside one block.
  void _extendNativeSelectionToOverlay(
    int blockIndex, {
    String gestureKind = 'nativeDrag',
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return;
    if (_isGlobalSelection || _isCommandExecuting) return;
    final overlay = _overlayKey.currentState;
    if (overlay == null ||
        overlay.hasSelection ||
        overlay.isHandleInteractionActive) {
      return;
    }
    final controller = _controllers[blockIndex];
    final selection = controller.selection;
    if (gestureKind == 'tripleClickBlock') {
      final end = controller.text.length;
      _shiftSelectionAnchor = SelectionEndpoint(block: blockIndex, offset: 0);
      _shiftSelectionFocus = SelectionEndpoint(block: blockIndex, offset: end);
      _lastFocusedController = controller;
      overlay.setKeyboardSelection(
        anchorBlock: blockIndex,
        anchorOffset: 0,
        focusBlock: blockIndex,
        focusOffset: end,
      );
      return;
    }
    if (!selection.isValid || selection.isCollapsed) return;
    final start = selection.start.clamp(0, controller.text.length).toInt();
    final end = selection.end.clamp(0, controller.text.length).toInt();
    if (start == end) return;
    if (start == 0 &&
        end == controller.text.length &&
        gestureKind != 'doubleClickWord') {
      return;
    }
    final promotedSelection = gestureKind == 'doubleClickWord'
        ? _doubleClickWordSelection(controller.text, selection)
        : TextSelection(baseOffset: start, extentOffset: end);
    _lastFocusedController = controller;
    _shiftSelectionAnchor = SelectionEndpoint(
      block: blockIndex,
      offset: promotedSelection.baseOffset,
    );
    _shiftSelectionFocus = SelectionEndpoint(
      block: blockIndex,
      offset: promotedSelection.extentOffset,
    );
    overlay.extendNativeBlockSelection(
      blockIndex,
      promotedSelection,
      allowFullBlock: gestureKind == 'doubleClickWord',
    );
  }

  void _registerEditorPrimaryClick(PointerDownEvent event) {
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    const maxClickGap = Duration(milliseconds: 500);
    const maxClickDistance = 8.0;
    final lastTime = _lastEditorPrimaryClickTime;
    final lastPosition = _lastEditorPrimaryClickPosition;
    final repeated = lastTime != null &&
        lastPosition != null &&
        event.timeStamp - lastTime <= maxClickGap &&
        (event.position - lastPosition).distance <= maxClickDistance;
    _editorPrimaryClickCount = repeated ? _editorPrimaryClickCount + 1 : 1;
    if (_editorPrimaryClickCount > 3) _editorPrimaryClickCount = 1;
    _lastEditorPrimaryClickTime = event.timeStamp;
    _lastEditorPrimaryClickPosition = event.position;
    _pendingNativeSelectionGestureKind = switch (_editorPrimaryClickCount) {
      2 => 'doubleClickWord',
      3 => 'tripleClickBlock',
      _ => 'nativeDrag',
    };
  }

  bool _hasAppSelectionForPointerReplacement() {
    if (_isGlobalSelection ||
        (_overlayKey.currentState?.hasSelection ?? false)) {
      return true;
    }
    for (final controller in _controllers) {
      final external = controller.externalSelection;
      final native = controller.selection;
      if (controller.isGlobalSelected) return true;
      if (external != null && external.isValid && !external.isCollapsed) {
        return true;
      }
      if (native.isValid && !native.isCollapsed) return true;
    }
    return false;
  }

  void _clearAppSelectionForPointerReplacement({
    String reason = 'replaceAppSelection',
  }) {
    _overlayKey.currentState?.clearSelection();
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    for (final controller in _controllers) {
      controller.isGlobalSelected = false;
      controller.externalSelection = null;
      controller.externalVisibleSelection = null;
      final native = controller.selection;
      if (native.isValid && !native.isCollapsed) {
        final collapseAt = native.extentOffset.clamp(0, controller.text.length);
        controller.selection = TextSelection.collapsed(offset: collapseAt);
      }
      controller.refresh();
    }
    if (!mounted) return;
    _setEditorState(() {
      _isGlobalSelection = false;
    });
    _recordSelectionTrace(reason);
  }

  TextSelection _doubleClickWordSelection(
    String rawText,
    TextSelection nativeSelection,
  ) {
    final start = nativeSelection.start.clamp(0, rawText.length).toInt();
    final end = nativeSelection.end.clamp(0, rawText.length).toInt();
    if (start == end) return nativeSelection;
    final visible = EditorTextGeometryService.visibleText(rawText);
    if (visible.isEmpty) {
      return TextSelection(baseOffset: start, extentOffset: end);
    }
    final visibleStart = MarkupController.rawToVisualOffset(rawText, start)
        .clamp(
          0,
          visible.length,
        )
        .toInt();
    final visibleEnd = MarkupController.rawToVisualOffset(rawText, end)
        .clamp(
          0,
          visible.length,
        )
        .toInt();
    final probe = _doubleClickWordProbe(
      visible,
      visibleStart,
      visibleEnd,
    );
    if (probe == null) {
      return TextSelection(baseOffset: start, extentOffset: end);
    }
    var wordStart = probe;
    var wordEnd = probe + 1;
    while (wordStart > 0 && _isEditorWordChar(visible[wordStart - 1])) {
      wordStart--;
    }
    while (wordEnd < visible.length && _isEditorWordChar(visible[wordEnd])) {
      wordEnd++;
    }
    final rawStart = MarkupController.visualToRawOffset(rawText, wordStart)
        .clamp(0, rawText.length)
        .toInt();
    final rawEnd = MarkupController.visualToRawOffset(rawText, wordEnd)
        .clamp(0, rawText.length)
        .toInt();
    if (rawStart >= rawEnd) {
      return TextSelection(baseOffset: start, extentOffset: end);
    }
    return TextSelection(baseOffset: rawStart, extentOffset: rawEnd);
  }

  int? _doubleClickWordProbe(String visible, int start, int end) {
    if (start < visible.length && _isEditorWordChar(visible[start])) {
      return start;
    }
    if (start > 0 && _isEditorWordChar(visible[start - 1])) {
      return start - 1;
    }
    final safeEnd = end.clamp(start, visible.length).toInt();
    for (var i = start; i < safeEnd; i++) {
      if (_isEditorWordChar(visible[i])) return i;
    }
    return null;
  }

  bool _isEditorWordChar(String char) {
    if (char.trim().isEmpty || char.isEmpty) return false;
    final code = char.runes.first;
    if (code >= 0x30 && code <= 0x39) return true;
    if (code >= 0x41 && code <= 0x5A) return true;
    if (code >= 0x61 && code <= 0x7A) return true;
    if (code == 0x5F) return true;
    if (code >= 0x0590 && code <= 0x05FF) return true;
    if (code >= 0x0600 && code <= 0x06FF) return true;
    return false;
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
        if (c.isGlobalSelected ||
            (sel != null && sel.isValid && !sel.isCollapsed)) {
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
      _setEditorState(() => _isCommandExecuting = true);
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
          final cursorAt =
              (sel.start + openPrefix.length).clamp(0, c.text.length);
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
        for (int i = _controllers.length - 1; i > 0; i--) {
          _removeBlock(i);
        }
        _controllers.first.clear();
        _controllers.first.refresh();
      }
      _clearGlobalSelection();
      _setEditorState(() => _isCommandExecuting = false);
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
    final normalizedClipboard =
        text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final internalMarkup = RichClipboard.internalMarkup;
    if (internalMarkup != null) {
      final cleanInternal = StylingService.stripTags(internalMarkup);
      // Compare after stripping trailing newlines: some OS clipboard implementations
      // drop the trailing '\n' from multi-block copies that end with an empty block,
      // causing a mismatch that makes the paste lose the last empty paragraph.
      final cmpInternal = cleanInternal.trimRight();
      final cmpClipboard = normalizedClipboard.trimRight();
      if (cmpInternal == cmpClipboard) {
        text =
            internalMarkup; // use full markup including any trailing empty block
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
        (_activeController != null &&
            !_activeController!.selection.isCollapsed)) {
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
          _setEditorState(() {
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
    final lastBlock = _controllers.isEmpty ? -1 : _controllers.length - 1;
    const scriptStart = SelectionEndpoint(block: 0, offset: 0);
    final scriptEnd = lastBlock < 0
        ? scriptStart
        : SelectionEndpoint(
            block: lastBlock,
            offset: _controllers[lastBlock].text.length,
          );
    for (final c in _controllers) {
      c.isGlobalSelected = true;
      c.externalSelection =
          TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.externalVisibleSelection = TextSelection(
        baseOffset: 0,
        extentOffset: MarkupDecorationParser.visibleText(c.text).length,
      );
    }
    _shiftSelectionAnchor = scriptStart;
    _shiftSelectionFocus = scriptEnd;
    if (lastBlock >= 0) {
      _lastFocusedController = _controllers[lastBlock];
      _focusNodes[lastBlock].requestFocus();
      _controllers[lastBlock].selection = TextSelection.collapsed(
        offset: _controllers[lastBlock].text.length,
      );
    }
    _setEditorState(() {});
    // Refresh after setState so TextFields repaint with new flags.
    for (final c in _controllers) {
      c.refresh();
    }
    _scheduleHighlightTrace('select-all');
    _recordSelectionTrace('select-all');
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
      c.externalVisibleSelection = TextSelection(
        baseOffset: 0,
        extentOffset: MarkupDecorationParser.visibleText(c.text).length,
      );
    }
    _setEditorState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
    _scheduleHighlightTrace('resync-global-selection');
    _recordSelectionTrace('resync-global-selection');
  }
}
