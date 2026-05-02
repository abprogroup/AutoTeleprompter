part of 'script_editor_screen.dart';

class _BlockSelectionPoint {
  final int blockIndex;
  final int rawOffset;

  const _BlockSelectionPoint({
    required this.blockIndex,
    required this.rawOffset,
  });
}

class _BlockSelectionRange {
  final _BlockSelectionPoint start;
  final _BlockSelectionPoint end;
  final String source;

  const _BlockSelectionRange({
    required this.start,
    required this.end,
    required this.source,
  });
}

extension _ScriptEditorSelectionClipboardParts on _ScriptEditorScreenState {
  static const Duration _globalSelectionSnapshotTtl = Duration(seconds: 20);

  List<String> _snapshotAllControllerMarkup() =>
      _controllers.map((c) => c.text).toList(growable: false);

  int _nonEmptyBlockCount(List<String> blocks) =>
      blocks.where((b) => b.trim().isNotEmpty).length;

  String _blockDebugShape(List<String>? blocks) {
    if (blocks == null) return 'none';
    return blocks
        .asMap()
        .entries
        .map((e) => '${e.key}:${e.value.length}')
        .join(',');
  }

  bool _isBetterBlockSnapshot(List<String> candidate, List<String>? current) {
    if (current == null) return true;
    final candidateNonEmpty = _nonEmptyBlockCount(candidate);
    final currentNonEmpty = _nonEmptyBlockCount(current);
    return candidate.length > current.length ||
        (candidate.length == current.length &&
            candidateNonEmpty >= currentNonEmpty);
  }

  _BlockSelectionRange? _normalizeBlockRange(
    _BlockSelectionPoint a,
    _BlockSelectionPoint b,
    String source,
  ) {
    if (a.blockIndex < 0 ||
        b.blockIndex < 0 ||
        a.blockIndex >= _controllers.length ||
        b.blockIndex >= _controllers.length) {
      return null;
    }

    final aOffset =
        a.rawOffset.clamp(0, _controllers[a.blockIndex].text.length).toInt();
    final bOffset =
        b.rawOffset.clamp(0, _controllers[b.blockIndex].text.length).toInt();
    var start = _BlockSelectionPoint(
      blockIndex: a.blockIndex,
      rawOffset: aOffset,
    );
    var end = _BlockSelectionPoint(
      blockIndex: b.blockIndex,
      rawOffset: bOffset,
    );

    if (start.blockIndex > end.blockIndex ||
        (start.blockIndex == end.blockIndex &&
            start.rawOffset > end.rawOffset)) {
      final t = start;
      start = end;
      end = t;
    }

    if (start.blockIndex == end.blockIndex &&
        start.rawOffset == end.rawOffset) {
      return null;
    }

    return _BlockSelectionRange(start: start, end: end, source: source);
  }

  List<String>? _rawMarkupSlicesForRange(_BlockSelectionRange range) {
    final normalized =
        _normalizeBlockRange(range.start, range.end, range.source);
    if (normalized == null) return null;

    final start = normalized.start;
    final end = normalized.end;
    if (start.blockIndex == end.blockIndex) {
      final text = _controllers[start.blockIndex].text;
      return [text.substring(start.rawOffset, end.rawOffset)];
    }

    final slices = <String>[];
    final startText = _controllers[start.blockIndex].text;
    slices.add(startText.substring(start.rawOffset));
    for (var i = start.blockIndex + 1; i < end.blockIndex; i++) {
      slices.add(_controllers[i].text);
    }
    final endText = _controllers[end.blockIndex].text;
    slices.add(endText.substring(0, end.rawOffset));
    return slices;
  }

  String _recognizedRangeShape(_BlockSelectionRange? range) {
    if (range == null) return 'none';
    final blocks = _rawMarkupSlicesForRange(range);
    final blockShape = _blockDebugShape(blocks);
    return '${range.start.blockIndex}:${range.start.rawOffset}-'
        '${range.end.blockIndex}:${range.end.rawOffset} [$blockShape]';
  }

  void _setRecognizedBlockRange(
    _BlockSelectionRange? range,
    String reason,
  ) {
    _recognizedBlockRange = range;
    _recognizedBlockRangeDebug =
        '$reason: ${_recognizedRangeShape(_recognizedBlockRange)}';
  }

  void _clearRecognizedBlockRange(String reason) {
    if (_recognizedBlockRange == null && _recognizedBlockRangeDebug == 'idle') {
      return;
    }
    _recognizedBlockRange = null;
    _recognizedBlockRangeDebug = '$reason: cleared';
  }

  bool _rangeMatchesOverlay(_BlockSelectionRange range) {
    final raw = _overlayKey.currentState?.currentRawRange;
    if (raw == null) return false;
    final current = _normalizeBlockRange(
      _BlockSelectionPoint(
        blockIndex: raw.startBlock,
        rawOffset: raw.startOffset,
      ),
      _BlockSelectionPoint(
        blockIndex: raw.endBlock,
        rawOffset: raw.endOffset,
      ),
      range.source,
    );
    if (current == null) return false;
    return current.start.blockIndex == range.start.blockIndex &&
        current.start.rawOffset == range.start.rawOffset &&
        current.end.blockIndex == range.end.blockIndex &&
        current.end.rawOffset == range.end.rawOffset;
  }

  List<String>? _recognizedBlocksForCommand(String reason) {
    final range = _recognizedBlockRange;
    if (range == null) return null;
    if (!_rangeMatchesOverlay(range)) {
      _clearRecognizedBlockRange('$reason-stale-range');
      return null;
    }
    final blocks = _rawMarkupSlicesForRange(range);
    if (blocks == null || blocks.isEmpty) return null;
    _selectionClipboardDebug =
        '$reason-recognized: ${blocks.length} slices [${_blockDebugShape(blocks)}]';
    return blocks;
  }

  void _deleteRecognizedRange(_BlockSelectionRange range) {
    final normalized =
        _normalizeBlockRange(range.start, range.end, range.source);
    if (normalized == null) return;

    final start = normalized.start;
    final end = normalized.end;
    _isCommandExecuting = true;
    if (start.blockIndex == end.blockIndex) {
      final controller = _controllers[start.blockIndex];
      controller.value = TextEditingValue(
        text: controller.text.substring(0, start.rawOffset) +
            controller.text.substring(end.rawOffset),
        selection: TextSelection.collapsed(offset: start.rawOffset),
      );
    } else {
      final startController = _controllers[start.blockIndex];
      startController.value = TextEditingValue(
        text: startController.text.substring(0, start.rawOffset),
        selection: TextSelection.collapsed(offset: start.rawOffset),
      );
      for (var i = start.blockIndex + 1; i < end.blockIndex; i++) {
        _controllers[i].value = const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );
      }
      final endController = _controllers[end.blockIndex];
      endController.value = TextEditingValue(
        text: endController.text.substring(end.rawOffset),
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
    _clearGlobalSelection();
    _isCommandExecuting = false;
    _saveHistory(description: 'Cut');
    setState(() {});
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
      _selectionClipboardDebug =
          '$reason: armed ${blocks.length} blocks [${_blockDebugShape(blocks)}]';
    } else {
      _selectionClipboardDebug =
          '$reason: kept armed ${_globalSelectionSnapshot!.length} blocks [${_blockDebugShape(_globalSelectionSnapshot)}]';
    }
  }

  void _repairGlobalSelectionSnapshotBlock(
    int blockIndex,
    String rawMarkup,
    String reason,
  ) {
    if (blockIndex < 0 || rawMarkup.isEmpty) return;

    final repaired = _globalSelectionSnapshot != null
        ? List<String>.of(_globalSelectionSnapshot!)
        : _snapshotAllControllerMarkup();
    while (repaired.length <= blockIndex) {
      repaired.add('');
    }

    if (repaired[blockIndex].trim().isNotEmpty &&
        repaired[blockIndex].length >= rawMarkup.length) {
      _globalSelectionSnapshot = repaired;
      _globalSelectionSnapshotAt = DateTime.now();
      _promoteNativeCutSnapshotToClipboard(repaired, reason);
      _selectionClipboardDebug =
          '$reason: kept block $blockIndex; clipboard ${repaired.length} blocks [${_blockDebugShape(repaired)}]';
      return;
    }

    repaired[blockIndex] = rawMarkup;
    _globalSelectionSnapshot = repaired;
    _globalSelectionSnapshotAt = DateTime.now();
    _promoteNativeCutSnapshotToClipboard(repaired, reason);
    _selectionClipboardDebug =
        '$reason: repaired block $blockIndex; clipboard ${repaired.length} blocks [${_blockDebugShape(repaired)}]';
  }

  void _promoteNativeCutSnapshotToClipboard(
    List<String> blocks,
    String reason,
  ) {
    if (blocks.isEmpty || blocks.every((b) => b.isEmpty)) return;
    _setBlockClipboard(blocks);
    _writePlainClipboardForBlocks(blocks);
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

  void _extendNativeSelectionToOverlay(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return;
    if (_isGlobalSelection || _isCommandExecuting) return;
    if (_overlayKey.currentState?.hasSelection ?? false) return;

    final controller = _controllers[blockIndex];
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = selection.start.clamp(0, controller.text.length).toInt();
    final end = selection.end.clamp(0, controller.text.length).toInt();
    if (start == end) return;
    if (start == 0 && end == controller.text.length) return;

    _lastFocusedController = controller;
    _overlayKey.currentState?.extendNativeBlockSelection(
      blockIndex,
      TextSelection(baseOffset: start, extentOffset: end),
    );
  }

  List<String>? _overlaySelectedMarkupBlocks() {
    if (!(_overlayKey.currentState?.hasSelection ?? false)) return null;
    final blocks = <String>[];
    for (final c in _controllers) {
      String slice = '';
      if (c.isGlobalSelected) {
        slice = c.text;
      } else {
        final sel = c.externalSelection;
        if (sel != null && sel.isValid && !sel.isCollapsed) {
          final start = sel.start.clamp(0, c.text.length);
          final end = sel.end.clamp(0, c.text.length);
          if (start < end) slice = c.text.substring(start, end);
        }
      }
      if (slice.isNotEmpty) blocks.add(slice);
    }
    return blocks.isEmpty ? null : blocks;
  }

  void _syncSelectionSnapshotFromOverlay(
    String reason, {
    required bool allowShrink,
  }) {
    final blocks = _overlaySelectedMarkupBlocks();
    if (blocks == null || blocks.isEmpty) return;
    if (!allowShrink &&
        _globalSelectionSnapshot != null &&
        !_isBetterBlockSnapshot(blocks, _globalSelectionSnapshot)) {
      _selectionClipboardDebug =
          '$reason: kept armed ${_globalSelectionSnapshot!.length} blocks [${_blockDebugShape(_globalSelectionSnapshot)}]';
      return;
    }
    _globalSelectionSnapshot = List<String>.of(blocks);
    _globalSelectionSnapshotAt = DateTime.now();
    _selectionClipboardDebug =
        '$reason: selected ${blocks.length} blocks [${_blockDebugShape(blocks)}]';
  }

  bool get _hasAnyActiveEditorSelection {
    if (_isGlobalSelection ||
        (_overlayKey.currentState?.hasSelection ?? false)) {
      return true;
    }
    for (final c in _controllers) {
      if (c.isGlobalSelected) return true;
      final external = c.externalSelection;
      if (external != null && external.isValid && !external.isCollapsed) {
        return true;
      }
      final native = c.selection;
      if (native.isValid && !native.isCollapsed) return true;
    }
    return false;
  }

  void _dismissEditorSelectionForUserNavigation(String reason) {
    if (!_hasAnyActiveEditorSelection &&
        !_hasRecentGlobalSelectionSnapshot &&
        _recognizedBlockRange == null) {
      return;
    }
    _clearRecognizedBlockRange(reason);
    _globalSelectionSnapshot = null;
    _globalSelectionSnapshotAt = null;
    _selectionClipboardDebug =
        '$reason: dismissed selection; paste clipboard ${_blockDebugShape(_blockClipboard)}';
    _clearGlobalSelection();
  }

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
  }) {
    final protectedBlocks = _globalSelectionSnapshot;
    final selectedBlocks = preferProtectedSnapshot &&
            protectedBlocks != null &&
            _hasRecentGlobalSelectionSnapshot &&
            _isBetterBlockSnapshot(protectedBlocks, blocks)
        ? protectedBlocks
        : blocks;
    _setBlockClipboard(selectedBlocks);
    _selectionClipboardDebug =
        '$reason: stored ${selectedBlocks.length} blocks [${_blockDebugShape(selectedBlocks)}]';
  }

  void _setBlockClipboard(List<String> blocks) {
    _blockClipboard = List<String>.of(blocks);
    _plainBlockClipboardText = _plainTextForBlocks(blocks);
    _blockClipboardTimer?.cancel();
    _blockClipboardTimer = Timer(const Duration(seconds: 60), () {
      _blockClipboard = null;
      _plainBlockClipboardText = null;
    });
  }

  String _plainTextForBlocks(List<String> blocks) => blocks
      .map((t) => StylingService.stripTags(t))
      .where((t) => t.isNotEmpty)
      .join('\n');

  String _normalizePlainClipboardText(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  void _writePlainClipboardForBlocks(List<String> blocks) {
    final plain = _plainTextForBlocks(blocks);
    Clipboard.setData(ClipboardData(text: plain));
  }

  void _writeRichClipboardForBlocks(List<String> blocks) {
    final plainBuf = StringBuffer();
    final htmlBuf = StringBuffer();
    for (final slice in blocks) {
      if (slice.isEmpty) continue;
      if (plainBuf.isNotEmpty) plainBuf.write('\n');
      plainBuf.write(StylingService.stripTags(slice));
      htmlBuf.write(StylingService.markupToHtml(slice));
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

    final recognizedBlocks = _recognizedBlocksForCommand('cut');
    final recognizedRange = _recognizedBlockRange;
    if (recognizedBlocks != null && recognizedRange != null) {
      _storeBlockClipboard(
        recognizedBlocks,
        'cut-recognized',
        preferProtectedSnapshot: false,
      );
      _writePlainClipboardForBlocks(_blockClipboard ?? recognizedBlocks);
      _writeRichClipboardForBlocks(_blockClipboard ?? recognizedBlocks);
      _deleteRecognizedRange(recognizedRange);
      return;
    }

    _onCopyClean();
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (hasOverlay) {
      final overlayBlocks = _overlaySelectedMarkupBlocks();
      if (overlayBlocks != null && overlayBlocks.isNotEmpty) {
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

    final recognizedBlocks = _recognizedBlocksForCommand('copy');
    if (recognizedBlocks != null) {
      _storeBlockClipboard(
        recognizedBlocks,
        'copy-recognized',
        preferProtectedSnapshot: false,
      );
      _writeRichClipboardForBlocks(_blockClipboard ?? recognizedBlocks);
      return;
    }

    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (hasOverlay) {
      final overlayBlocks = _overlaySelectedMarkupBlocks();
      if (overlayBlocks != null && overlayBlocks.isNotEmpty) {
        _storeBlockClipboard(
          overlayBlocks,
          'copy-overlay',
          preferProtectedSnapshot: false,
        );
      }
      final plainBuf = StringBuffer();
      final htmlBuf = StringBuffer();
      final copiedBlocks = overlayBlocks;
      for (final slice in copiedBlocks ?? const <String>[]) {
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
        'paste: restoring ${blocks.length} blocks into ${_controllers.length} controllers [${_blockDebugShape(blocks)}]';
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
    _selectionClipboardDebug =
        'paste: restored ${blocks.length} blocks [${_blockDebugShape(blocks)}]';
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
    _clearRecognizedBlockRange('delete-global-selection');
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
    _clearRecognizedBlockRange('clear-global-selection');
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
