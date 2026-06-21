part of 'script_editor_screen.dart';

const Duration _globalSelectionSnapshotTtl = Duration(seconds: 20);
const Duration _globalSelectionNativeMenuGuard = Duration(milliseconds: 650);

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
    _setEditorState(() {});
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

  void _promoteNativeSelectionToOverlay() {
    if (_isGlobalSelection || _isCommandExecuting) return;
    final overlay = _overlayKey.currentState;
    if (overlay == null || overlay.hasSelection) return;
    for (var i = 0; i < _controllers.length; i++) {
      if (!_focusNodes[i].hasFocus) continue;
      final selection = _controllers[i].selection;
      if (!selection.isValid || selection.isCollapsed) continue;
      if (selection.start == 0 &&
          selection.end == _controllers[i].text.length) {
        continue;
      }
      _extendNativeSelectionToOverlay(i);
      return;
    }
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
    _setEditorState(() {});
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
}
