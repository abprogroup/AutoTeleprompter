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
  static const Duration _globalSelectionNativeMenuGuard =
      Duration(milliseconds: 650);

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

  void _recordSelectionCommandDebug(
    String command, {
    required List<String>? recognized,
    required List<String>? visible,
    required List<String>? overlay,
    required String chosen,
  }) {
    _selectionCommandDebug = '$command chosen=$chosen '
        'r=[${_blockDebugShape(recognized)}] '
        'v=[${_blockDebugShape(visible)}] '
        'o=[${_blockDebugShape(overlay)}] '
        'clip=${_blockClipboardKind.name}';
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

  String _rawSlicePreservingEnclosingStyles(
    String text,
    int start,
    int end,
  ) {
    final safeStart = start.clamp(0, text.length).toInt();
    final safeEnd = end.clamp(safeStart, text.length).toInt();
    final selected = text.substring(safeStart, safeEnd);
    if (selected.isEmpty) return selected;

    final wrappers = <({int index, String open, String close})>[];
    final bracketOpen = RegExp(
        r'\[(u|i|color|bg|font|size|align|rtl|ltr|center|left|right)(?:=[^\]]+)?\]');
    for (final match in bracketOpen.allMatches(text)) {
      if (match.start >= safeStart) break;
      final family = match.group(1)!;
      final close = family == 'align' && match.group(0)!.startsWith('[align=')
          ? '[/${match.group(0)!.substring(1)}'
          : '[/$family]';
      final closeIndex = text.indexOf(close, match.end);
      if (closeIndex >= safeEnd) {
        wrappers.add((index: match.start, open: match.group(0)!, close: close));
      }
    }

    final boldBefore =
        RegExp(r'\*\*').allMatches(text.substring(0, safeStart)).length;
    if (boldBefore.isOdd) {
      final closeIndex = text.indexOf('**', safeStart);
      if (closeIndex >= safeEnd) {
        wrappers.add((
          index: text.lastIndexOf('**', safeStart),
          open: '**',
          close: '**'
        ));
      }
    }

    if (wrappers.isEmpty) return selected;
    wrappers.sort((a, b) => a.index.compareTo(b.index));
    final buffer = StringBuffer();
    for (final wrapper in wrappers) {
      buffer.write(wrapper.open);
    }
    buffer.write(selected);
    for (final wrapper in wrappers.reversed) {
      buffer.write(wrapper.close);
    }
    return buffer.toString();
  }

  List<String>? _rawMarkupSlicesForRange(_BlockSelectionRange range) {
    final normalized =
        _normalizeBlockRange(range.start, range.end, range.source);
    if (normalized == null) return null;

    final start = normalized.start;
    final end = normalized.end;
    if (start.blockIndex == end.blockIndex) {
      final text = _controllers[start.blockIndex].text;
      return [
        _rawSlicePreservingEnclosingStyles(
          text,
          start.rawOffset,
          end.rawOffset,
        )
      ];
    }

    final slices = <String>[];
    final startText = _controllers[start.blockIndex].text;
    slices.add(_rawSlicePreservingEnclosingStyles(
      startText,
      start.rawOffset,
      startText.length,
    ));
    for (var i = start.blockIndex + 1; i < end.blockIndex; i++) {
      slices.add(_controllers[i].text);
    }
    final endText = _controllers[end.blockIndex].text;
    slices.add(_rawSlicePreservingEnclosingStyles(
      endText,
      0,
      end.rawOffset,
    ));
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
    final current = _rangeFromOverlayRaw(raw, range.source);
    if (current == null) return false;
    return _rangesEqual(current, range);
  }

  bool _rangesEqual(_BlockSelectionRange a, _BlockSelectionRange b) {
    return a.start.blockIndex == b.start.blockIndex &&
        a.start.rawOffset == b.start.rawOffset &&
        a.end.blockIndex == b.end.blockIndex &&
        a.end.rawOffset == b.end.rawOffset;
  }

  _BlockSelectionRange? _rangeFromOverlayRaw(
    ({
      int startBlock,
      int startOffset,
      int endBlock,
      int endOffset,
    }) raw,
    String source,
  ) {
    return _normalizeBlockRange(
      _BlockSelectionPoint(
        blockIndex: raw.startBlock,
        rawOffset: raw.startOffset,
      ),
      _BlockSelectionPoint(
        blockIndex: raw.endBlock,
        rawOffset: raw.endOffset,
      ),
      source,
    );
  }

  List<String>? _recognizedBlocksForCommand(
    String reason, {
    bool allowStoredRange = false,
  }) {
    var range = _recognizedBlockRange;
    final raw = _overlayKey.currentState?.currentRawRange;
    var usedStoredRange = false;
    if (raw != null) {
      final liveRange = _rangeFromOverlayRaw(raw, '$reason-overlay');
      if (liveRange != null &&
          (range == null || !_rangesEqual(range, liveRange))) {
        _setRecognizedBlockRange(liveRange, '$reason-live-overlay');
        range = liveRange;
      }
    }
    if (range == null) return null;
    if (raw == null) {
      if (!allowStoredRange) {
        _clearRecognizedBlockRange('$reason-stale-range');
        return null;
      }
      usedStoredRange = true;
    } else if (!_rangeMatchesOverlay(range)) {
      _clearRecognizedBlockRange('$reason-stale-range');
      return null;
    }
    final blocks = _rawMarkupSlicesForRange(range);
    if (blocks == null || blocks.isEmpty) return null;
    _selectionClipboardDebug =
        '$reason-recognized${usedStoredRange ? "-stored" : ""}: ${blocks.length} slices [${_blockDebugShape(blocks)}]';
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
    _setBlockClipboard(blocks, kind: _BlockClipboardKind.fullScript);
    _writePlainClipboardForBlocks(blocks);
  }

  bool get _hasRecentGlobalSelectionSnapshot {
    final capturedAt = _globalSelectionSnapshotAt;
    return _globalSelectionSnapshot != null &&
        capturedAt != null &&
        DateTime.now().difference(capturedAt) < _globalSelectionSnapshotTtl;
  }

  bool get _isGlobalSelectionNativeGuardActive {
    final until = _globalSelectionLockUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  bool get _hasPasteableBlockClipboard =>
      (_blockClipboard != null && _blockClipboard!.isNotEmpty) ||
      (_hasRecentGlobalSelectionSnapshot &&
          _globalSelectionSnapshot != null &&
          _globalSelectionSnapshot!.isNotEmpty);

  bool get _hasActivePartialNativeSelection {
    final controller = _activeController;
    if (controller == null) return false;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return false;
    return !(selection.start == 0 && selection.end == controller.text.length);
  }

  void _extendNativeSelectionToOverlay(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return;
    if (_isGlobalSelection || _isCommandExecuting) return;
    if (_isGlobalSelectionNativeGuardActive) return;
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
          if (start < end) {
            slice = _rawSlicePreservingEnclosingStyles(c.text, start, end);
          }
        }
      }
      if (slice.isNotEmpty) blocks.add(slice);
    }
    return blocks.isEmpty ? null : blocks;
  }

  TextSelection? _visibleAppSelectionForController(MarkupController c) {
    if (c.isGlobalSelected) {
      return TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
    final sel = c.externalSelection;
    if (sel == null || !sel.isValid || sel.isCollapsed) return null;
    final start = sel.start.clamp(0, c.text.length).toInt();
    final end = sel.end.clamp(0, c.text.length).toInt();
    if (start == end) return null;
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  List<String>? _visibleAppSelectedMarkupBlocks(String reason) {
    final blocks = <String>[];
    for (final c in _controllers) {
      final sel = _visibleAppSelectionForController(c);
      if (sel == null) continue;
      final start = sel.start.clamp(0, c.text.length).toInt();
      final end = sel.end.clamp(0, c.text.length).toInt();
      if (start == end) continue;
      blocks.add(_rawSlicePreservingEnclosingStyles(c.text, start, end));
    }
    if (blocks.isEmpty) return null;
    _selectionClipboardDebug =
        '$reason-visible-app: ${blocks.length} slices [${_blockDebugShape(blocks)}]';
    return blocks;
  }

  bool _shouldPreferRecognizedBlocks(
    List<String> recognizedBlocks,
    List<String>? visibleBlocks,
  ) {
    if (visibleBlocks == null || visibleBlocks.isEmpty) return true;
    if (recognizedBlocks.length > visibleBlocks.length) return true;
    if (recognizedBlocks.length < visibleBlocks.length) return false;
    return _nonEmptyBlockCount(recognizedBlocks) >=
        _nonEmptyBlockCount(visibleBlocks);
  }

  void _deleteVisibleAppSelectionRanges() {
    _isCommandExecuting = true;
    for (final c in _controllers) {
      final sel = _visibleAppSelectionForController(c);
      if (sel == null) continue;
      final start = sel.start.clamp(0, c.text.length).toInt();
      final end = sel.end.clamp(0, c.text.length).toInt();
      if (start == end) continue;
      c.value = TextEditingValue(
        text: c.text.substring(0, start) + c.text.substring(end),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    _clearGlobalSelection();
    _isCommandExecuting = false;
    _saveHistory(description: 'Cut');
    setState(() {});
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
    setState(() {});
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
