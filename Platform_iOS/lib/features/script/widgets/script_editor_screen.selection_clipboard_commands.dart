part of 'script_editor_screen.dart';

extension _ScriptEditorSelectionClipboardCommandParts
    on _ScriptEditorScreenState {
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
    if (_overlayKey.currentState?.hasSelection ?? false) {
      return null;
    }
    if (_hasActivePartialNativeSelection) {
      return null;
    }
    if (_hasRecentGlobalSelectionSnapshot) {
      _selectionClipboardDebug =
          '$reason: using armed ${_globalSelectionSnapshot!.length} blocks [${_blockDebugShape(_globalSelectionSnapshot)}]';
      return List<String>.of(_globalSelectionSnapshot!);
    }
    return null;
  }

  void _storeBlockClipboard(
    List<String> blocks,
    String reason, {
    bool preferProtectedSnapshot = true,
    _BlockClipboardKind kind = _BlockClipboardKind.partialSelection,
  }) {
    final protectedBlocks = _globalSelectionSnapshot;
    final selectedBlocks = preferProtectedSnapshot &&
            protectedBlocks != null &&
            _hasRecentGlobalSelectionSnapshot &&
            _isBetterBlockSnapshot(protectedBlocks, blocks)
        ? protectedBlocks
        : blocks;
    _setBlockClipboard(selectedBlocks, kind: kind);
    _selectionClipboardDebug =
        '$reason: stored ${selectedBlocks.length} ${kind.name} blocks [${_blockDebugShape(selectedBlocks)}]';
  }

  void _setBlockClipboard(
    List<String> blocks, {
    _BlockClipboardKind kind = _BlockClipboardKind.partialSelection,
  }) {
    _blockClipboard = List<String>.of(blocks);
    _blockClipboardKind = kind;
    _plainBlockClipboardText = _plainTextForBlocks(blocks);
    _blockClipboardTimer?.cancel();
    _blockClipboardTimer = Timer(const Duration(seconds: 60), () {
      _blockClipboard = null;
      _plainBlockClipboardText = null;
    });
  }

  String _plainTextForBlocks(List<String> blocks) =>
      blocks.map((t) => StylingService.stripTags(t)).join('\n');

  String _normalizePlainClipboardText(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  void _writePlainClipboardForBlocks(List<String> blocks) {
    final plain = _plainTextForBlocks(blocks);
    Clipboard.setData(ClipboardData(text: plain));
  }

  void _writeRichClipboardForBlocks(List<String> blocks) {
    final plainBuf = StringBuffer();
    final htmlBuf = StringBuffer();
    for (var i = 0; i < blocks.length; i++) {
      final slice = blocks[i];
      if (i > 0) plainBuf.write('\n');
      plainBuf.write(StylingService.stripTags(slice));
      if (slice.isNotEmpty) {
        htmlBuf.write(StylingService.markupToHtml(slice));
      } else {
        htmlBuf.write('<br>');
      }
    }
    if (plainBuf.isEmpty) return;
    RichClipboard.setHtml(
      plain: plainBuf.toString(),
      html: htmlBuf.toString(),
    );
  }

  bool _consumeNativePlainBlockPasteIfNeeded(
    MarkupController controller,
    String previousText,
  ) {
    final blocks = _blockClipboard;
    final plain = _plainBlockClipboardText;
    if (_isCommandExecuting ||
        blocks == null ||
        blocks.isEmpty ||
        plain == null ||
        plain.isEmpty ||
        controller.text == previousText) {
      return false;
    }

    final normalizedCurrent = _normalizePlainClipboardText(controller.text);
    final normalizedPlain = _normalizePlainClipboardText(plain);
    final normalizedInserted =
        previousText.isNotEmpty && controller.text.startsWith(previousText)
            ? _normalizePlainClipboardText(
                controller.text.substring(previousText.length),
              )
            : normalizedCurrent;

    if (normalizedCurrent != normalizedPlain &&
        normalizedInserted != normalizedPlain) {
      return false;
    }

    _selectionClipboardDebug =
        'native-paste: intercepted plain text; restoring ${blocks.length} blocks [${_blockDebugShape(blocks)}]';
    _pasteFromGlobalClipboard();
    return true;
  }

  void _ensureCutUndoBaseline() {
    _commitHistory('Before Cut');
  }

  void _onCutClean() {
    final globalBlocks = _globalBlocksForCommand('cut');
    if (globalBlocks != null && globalBlocks.isNotEmpty) {
      _recordSelectionCommandDebug(
        'cut',
        recognized: null,
        visible: null,
        overlay: null,
        chosen: 'global',
      );
      _ensureCutUndoBaseline();
      _storeBlockClipboard(
        globalBlocks,
        'cut',
        kind: _BlockClipboardKind.fullScript,
      );
      _writePlainClipboardForBlocks(_blockClipboard ?? globalBlocks);
      _isCommandExecuting = true;
      for (final c in _controllers) {
        c.text = '';
      }
      _clearGlobalSelection();
      _isCommandExecuting = false;
      unawaited(_syncBookmarksFromEditorSigns(notify: true, save: true));
      _saveHistory(description: 'Cut');
      setState(() {});
      return;
    }

    final visibleBlocks = _visibleAppSelectedMarkupBlocks('cut');
    final recognizedBlocks = _recognizedBlocksForCommand(
      'cut',
      allowStoredRange: visibleBlocks != null && visibleBlocks.isNotEmpty,
    );
    final overlayBlocks = _overlaySelectedMarkupBlocks();
    final recognizedRange = _recognizedBlockRange;
    if (recognizedBlocks != null &&
        recognizedRange != null &&
        _shouldPreferRecognizedBlocks(recognizedBlocks, visibleBlocks)) {
      _recordSelectionCommandDebug(
        'cut',
        recognized: recognizedBlocks,
        visible: visibleBlocks,
        overlay: overlayBlocks,
        chosen: 'recognized',
      );
      _ensureCutUndoBaseline();
      _storeBlockClipboard(
        recognizedBlocks,
        'cut-recognized',
        preferProtectedSnapshot: false,
      );
      _writePlainClipboardForBlocks(_blockClipboard ?? recognizedBlocks);
      _writeRichClipboardForBlocks(_blockClipboard ?? recognizedBlocks);
      _deleteRecognizedRange(recognizedRange);
      unawaited(_syncBookmarksFromEditorSigns(notify: true, save: true));
      return;
    }

    if (visibleBlocks != null && visibleBlocks.isNotEmpty) {
      _recordSelectionCommandDebug(
        'cut',
        recognized: recognizedBlocks,
        visible: visibleBlocks,
        overlay: overlayBlocks,
        chosen: 'visible',
      );
      _ensureCutUndoBaseline();
      _storeBlockClipboard(
        visibleBlocks,
        'cut-visible-app',
        preferProtectedSnapshot: false,
      );
      _writePlainClipboardForBlocks(_blockClipboard ?? visibleBlocks);
      _writeRichClipboardForBlocks(_blockClipboard ?? visibleBlocks);
      _deleteVisibleAppSelectionRanges();
      unawaited(_syncBookmarksFromEditorSigns(notify: true, save: true));
      return;
    }

    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (hasOverlay) {
      if (overlayBlocks != null && overlayBlocks.isNotEmpty) {
        _recordSelectionCommandDebug(
          'cut',
          recognized: recognizedBlocks,
          visible: visibleBlocks,
          overlay: overlayBlocks,
          chosen: 'overlay',
        );
        _ensureCutUndoBaseline();
        _storeBlockClipboard(
          overlayBlocks,
          'cut-overlay',
          preferProtectedSnapshot: false,
        );
        _writePlainClipboardForBlocks(_blockClipboard ?? overlayBlocks);
      }
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
      unawaited(_syncBookmarksFromEditorSigns(notify: true, save: true));
      _saveHistory(description: 'Cut');
      setState(() {});
      return;
    }

    final c = _activeController;
    if (c == null) return;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    _recordSelectionCommandDebug(
      'cut',
      recognized: recognizedBlocks,
      visible: visibleBlocks,
      overlay: overlayBlocks,
      chosen: 'native:${sel.start}-${sel.end}',
    );
    _ensureCutUndoBaseline();
    final slice = _rawSlicePreservingEnclosingStyles(
      c.text,
      sel.start,
      sel.end,
    );
    if (slice.isNotEmpty) {
      _setBlockClipboard([slice]);
      _writeRichClipboardForBlocks(_blockClipboard ?? [slice]);
    }
    c.value = TextEditingValue(
      text: c.text.substring(0, sel.start) + c.text.substring(sel.end),
      selection: TextSelection.collapsed(offset: sel.start),
    );
    unawaited(_syncBookmarksFromEditorSigns(notify: true, save: true));
    _saveHistory(description: 'Cut');
  }

  void _onCopyClean() {
    final globalBlocks = _globalBlocksForCommand('copy');
    if (globalBlocks != null && globalBlocks.isNotEmpty) {
      _recordSelectionCommandDebug(
        'copy',
        recognized: null,
        visible: null,
        overlay: null,
        chosen: 'global',
      );
      _storeBlockClipboard(
        globalBlocks,
        'copy',
        kind: _BlockClipboardKind.fullScript,
      );
      final copiedBlocks = _blockClipboard ?? globalBlocks;
      _writeRichClipboardForBlocks(copiedBlocks);
      return;
    }

    final visibleBlocks = _visibleAppSelectedMarkupBlocks('copy');
    final recognizedBlocks = _recognizedBlocksForCommand(
      'copy',
      allowStoredRange: visibleBlocks != null && visibleBlocks.isNotEmpty,
    );
    final overlayBlocks = _overlaySelectedMarkupBlocks();
    if (recognizedBlocks != null &&
        _shouldPreferRecognizedBlocks(recognizedBlocks, visibleBlocks)) {
      _recordSelectionCommandDebug(
        'copy',
        recognized: recognizedBlocks,
        visible: visibleBlocks,
        overlay: overlayBlocks,
        chosen: 'recognized',
      );
      _storeBlockClipboard(
        recognizedBlocks,
        'copy-recognized',
        preferProtectedSnapshot: false,
      );
      _writeRichClipboardForBlocks(_blockClipboard ?? recognizedBlocks);
      return;
    }

    if (visibleBlocks != null && visibleBlocks.isNotEmpty) {
      _recordSelectionCommandDebug(
        'copy',
        recognized: recognizedBlocks,
        visible: visibleBlocks,
        overlay: overlayBlocks,
        chosen: 'visible',
      );
      _storeBlockClipboard(
        visibleBlocks,
        'copy-visible-app',
        preferProtectedSnapshot: false,
      );
      _writeRichClipboardForBlocks(_blockClipboard ?? visibleBlocks);
      return;
    }

    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (hasOverlay) {
      if (overlayBlocks != null && overlayBlocks.isNotEmpty) {
        _recordSelectionCommandDebug(
          'copy',
          recognized: recognizedBlocks,
          visible: visibleBlocks,
          overlay: overlayBlocks,
          chosen: 'overlay',
        );
        _storeBlockClipboard(
          overlayBlocks,
          'copy-overlay',
          preferProtectedSnapshot: false,
        );
        _writeRichClipboardForBlocks(_blockClipboard ?? overlayBlocks);
        return;
      }
      _recordSelectionCommandDebug(
        'copy',
        recognized: recognizedBlocks,
        visible: visibleBlocks,
        overlay: overlayBlocks,
        chosen: 'overlay-empty',
      );
      return;
    }

    final controller = _activeController;
    if (controller == null) return;
    final slice = _rawSlicePreservingEnclosingStyles(
      controller.text,
      controller.selection.start,
      controller.selection.end,
    );
    if (slice.isEmpty) return;
    _recordSelectionCommandDebug(
      'copy',
      recognized: recognizedBlocks,
      visible: visibleBlocks,
      overlay: overlayBlocks,
      chosen:
          'native:${controller.selection.start}-${controller.selection.end}',
    );
    _setBlockClipboard([slice]);
    RichClipboard.setHtml(
      plain: StylingService.stripTags(slice),
      html: StylingService.markupToHtml(slice),
    );
  }
}
