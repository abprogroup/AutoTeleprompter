part of 'script_editor_screen.dart';

extension _ScriptEditorSelectionClipboardParts on _ScriptEditorScreenState {
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
          // Include empty blocks as empty lines; do not collapse paragraphs.
          if (plainBuf.isNotEmpty) {
            plainBuf.write('\n');
            markupBuf.write('\n');
          }
          plainBuf.write(StylingService.stripTags(slice));
          htmlBuf.write(StylingService.markupToHtml(slice));
          markupBuf.write(slice);
        }
      }
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
          final cursorAt =
              (sel.start + openPrefix.length).clamp(0, c.text.length);
          c.selection = TextSelection.collapsed(offset: cursorAt);
          c.externalSelection = null;
          c.refresh();
        }
      }
      if (toRemove.isNotEmpty && _controllers.length > toRemove.length) {
        for (final idx in toRemove.reversed) {
          _removeBlock(idx);
        }
      } else if (toRemove.length == _controllers.length) {
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

    String text = data!.text!;
    final normalizedClipboard =
        text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final internalMarkup = RichClipboard.internalMarkup;
    if (internalMarkup != null) {
      final cleanInternal = StylingService.stripTags(internalMarkup);
      final cmpInternal = cleanInternal.trimRight();
      final cmpClipboard = normalizedClipboard.trimRight();
      if (cmpInternal == cmpClipboard) {
        text = internalMarkup;
      } else {
        text = normalizedClipboard;
      }
    } else {
      text = normalizedClipboard;
    }

    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection ||
        hasOverlay ||
        (_activeController != null &&
            !_activeController!.selection.isCollapsed)) {
      _deleteSelection();
    }

    final c = _activeController;
    if (c != null) {
      final sel = c.selection;
      final oldText = c.text;
      final before = oldText.substring(0, sel.start);
      final after = oldText.substring(sel.end);

      if (text.contains('\n')) {
        final lines = text.split('\n');
        final currentIdx = _controllers.indexOf(c);
        if (currentIdx != -1) {
          _setEditorState(() {
            c.text = before + lines[0];
            for (int i = 1; i < lines.length - 1; i++) {
              _addBlock(currentIdx + i, text: lines[i]);
            }
            final lastLine = lines.last + after;
            _addBlock(currentIdx + lines.length - 1, text: lastLine);

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
    for (final c in _controllers) {
      c.refresh();
    }
    _scheduleHighlightTrace('select-all');
    _recordSelectionTrace('select-all');
  }

  /// Re-sync externalSelection after a global style operation changes text lengths.
  void _resyncGlobalSelection() {
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
