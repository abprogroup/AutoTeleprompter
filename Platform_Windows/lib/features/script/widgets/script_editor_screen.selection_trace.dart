part of 'script_editor_screen.dart';

extension _ScriptEditorSelectionTraceParts on _ScriptEditorScreenState {
  void _recordSelectionTrace(
    String reason, {
    LogicalKeyboardKey? key,
    SelectionEndpoint? anchor,
    SelectionEndpoint? focus,
    String? seedSource,
    String? targetMode,
    String? gestureKind,
    TextSelection? nativeSelection,
    bool? anchorCrossing,
    bool? collapsedShiftSeed,
    bool? staleOverlayRejected,
  }) {
    if (!_shouldWriteDebugArtifacts) return;
    final sequence = ++_selectionTraceSequence;
    final beforeTrace = _buildSelectionTrace(
      sequence: sequence,
      reason: reason,
      key: key,
      anchor: anchor,
      focus: focus,
      seedSource: seedSource,
      targetMode: targetMode,
      gestureKind: gestureKind,
      nativeSelection: nativeSelection,
      anchorCrossing: anchorCrossing,
      collapsedShiftSeed: collapsedShiftSeed,
      staleOverlayRejected: staleOverlayRejected,
    );
    // ignore: invalid_use_of_protected_member
    setState(() {
      _lastSelectionTrace = '$beforeTrace\n\nAFTER: waiting for next frame...';
      _lastSelectionTraceScreenshotPath = null;
      _lastSelectionTraceLogPath = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_finishSelectionTrace(
        sequence: sequence,
        beforeTrace: beforeTrace,
        reason: reason,
        key: key,
        seedSource: seedSource,
        targetMode: targetMode,
        gestureKind: gestureKind,
        nativeSelection: nativeSelection,
        anchorCrossing: anchorCrossing,
        collapsedShiftSeed: collapsedShiftSeed,
        staleOverlayRejected: staleOverlayRejected,
      ));
    });
  }

  Future<void> _finishSelectionTrace({
    required int sequence,
    required String beforeTrace,
    required String reason,
    LogicalKeyboardKey? key,
    String? seedSource,
    String? targetMode,
    String? gestureKind,
    TextSelection? nativeSelection,
    bool? anchorCrossing,
    bool? collapsedShiftSeed,
    bool? staleOverlayRejected,
  }) async {
    if (!mounted || !_shouldWriteDebugArtifacts) return;
    final afterTrace = _buildSelectionTrace(
      sequence: sequence,
      reason: '$reason after',
      key: key,
      seedSource: seedSource,
      targetMode: targetMode,
      gestureKind: gestureKind,
      nativeSelection: nativeSelection,
      anchorCrossing: anchorCrossing,
      collapsedShiftSeed: collapsedShiftSeed,
      staleOverlayRejected: staleOverlayRejected,
    );
    final directory = await _ensureDebugArtifactDirectory(
      _EditorDebugArtifactType.selectionTraces,
      _selectionTraceSessionId,
    );
    if (directory == null) return;
    final screenshotPath = await _captureEditorDebugScreenshot(
      directory: directory,
      prefix: 'selection',
      sequence: sequence,
    );
    final logPath = await _writeDebugArtifactLog(
      directory: directory,
      prefix: 'selection',
      sequence: sequence,
      trace: [
        beforeTrace,
        '',
        afterTrace,
        '',
        'screenshot=${screenshotPath ?? "not captured"}',
      ].join('\n'),
    );
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _lastSelectionTrace = [
        beforeTrace,
        '',
        afterTrace,
        '',
        'screenshot=${screenshotPath ?? "not captured"}',
        'log=$logPath',
      ].join('\n');
      _lastSelectionTraceScreenshotPath = screenshotPath;
      _lastSelectionTraceLogPath = logPath;
    });
  }

  String _buildSelectionTrace({
    required int sequence,
    required String reason,
    LogicalKeyboardKey? key,
    SelectionEndpoint? anchor,
    SelectionEndpoint? focus,
    String? seedSource,
    String? targetMode,
    String? gestureKind,
    TextSelection? nativeSelection,
    bool? anchorCrossing,
    bool? collapsedShiftSeed,
    bool? staleOverlayRejected,
  }) {
    return [
      'SELECTION TRACE #$sequence',
      'time=${DateTime.now().toIso8601String()}',
      'reason=$reason',
      if (key != null) 'key=${key.keyLabel}',
      if (seedSource != null) 'seedSource=$seedSource',
      if (targetMode != null) 'targetMode=$targetMode',
      if (gestureKind != null) 'gestureKind=$gestureKind',
      if (nativeSelection != null)
        'native=${_formatSelection(nativeSelection)}',
      if (anchorCrossing != null) 'anchorCrossing=$anchorCrossing',
      if (collapsedShiftSeed != null) 'collapsedShiftSeed=$collapsedShiftSeed',
      if (staleOverlayRejected != null)
        'staleOverlayRejected=$staleOverlayRejected',
      _arrowModifierTraceLine(),
      _debugFocusAuthorityLine(),
      _debugSelectionAuthorityLine(),
      if (anchor != null || focus != null)
        'requested anchor=${anchor ?? "none"} focus=${focus ?? "none"}',
      for (final block in _selectionTraceBlocks())
        _buildSelectionBlockTrace(block),
    ].join('\n');
  }

  String _debugSelectionAuthorityLine() {
    final overlay = _overlayKey.currentState;
    final selectedBlocks = <String>[];
    for (var i = 0; i < _controllers.length; i++) {
      final c = _controllers[i];
      final external = c.externalSelection;
      final native = c.selection;
      if (c.isGlobalSelected) {
        selectedBlocks.add('$i:global');
      } else if (external != null &&
          external.isValid &&
          !external.isCollapsed) {
        selectedBlocks.add('$i:external(${external.start}-${external.end})');
      } else if (native.isValid && !native.isCollapsed) {
        selectedBlocks.add('$i:native(${native.start}-${native.end})');
      }
    }
    return 'selectionAuthority global=$_isGlobalSelection '
        'overlay=${overlay?.debugSelectionSummary ?? "none"} '
        'blocks=${selectedBlocks.isEmpty ? "none" : selectedBlocks.join(",")}';
  }

  List<int> _selectionTraceBlocks() {
    final blocks = <int>{};
    final focused = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focused >= 0) blocks.add(focused);
    final active = _lastFocusedController == null
        ? -1
        : _controllers.indexOf(_lastFocusedController!);
    if (active >= 0) blocks.add(active);
    for (var i = 0; i < _controllers.length; i++) {
      final c = _controllers[i];
      final external = c.externalSelection;
      if (c.isGlobalSelected ||
          (external != null && external.isValid && !external.isCollapsed) ||
          (c.selection.isValid && !c.selection.isCollapsed)) {
        blocks.add(i);
      }
    }
    return blocks.take(12).toList(growable: false);
  }

  String _buildSelectionBlockTrace(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) {
      return 'BLOCK $blockIndex <invalid>';
    }
    final controller = _controllers[blockIndex];
    final raw = controller.text;
    final visible = EditorTextGeometryService.visibleText(raw);
    final selection = controller.isGlobalSelected
        ? TextSelection(baseOffset: 0, extentOffset: raw.length)
        : controller.externalSelection ??
            (controller.selection.isValid ? controller.selection : null);
    final safeSelection =
        selection == null || !selection.isValid || selection.isCollapsed
            ? null
            : TextSelection(
                baseOffset: selection.start.clamp(0, raw.length).toInt(),
                extentOffset: selection.end.clamp(0, raw.length).toInt(),
              );
    final visibleSelection = safeSelection == null
        ? null
        : MarkupDecorationParser.rawToVisibleSelection(raw, safeSelection);
    final editable = _renderEditableForBlock(blockIndex);
    final rects = safeSelection == null || editable == null
        ? const <Rect>[]
        : MarkupRenderEditableGeometry.mergedBandsForSelection(
            editable,
            safeSelection,
            rawText: raw,
          );
    return [
      '',
      'BLOCK $blockIndex',
      'rawLen=${raw.length} visibleLen=${visible.length} '
          'direction=${_editorBlockResolvedRtl(blockIndex) ? "RTL" : "LTR"}',
      'native=${_formatSelection(controller.selection)} '
          'external=${_formatSelection(controller.externalSelection)} '
          'global=${controller.isGlobalSelected}',
      'effective=${_formatSelection(safeSelection)} '
          'visible=${_formatSelection(visibleSelection)}',
      'visibleContext=${visibleSelection == null ? "none" : _debugVisibleContext(visible, visibleSelection.start)}',
      'renderEditableBands=${_formatRects(rects)}',
    ].join('\n');
  }

  Future<void> _copyLastSelectionTrace() async {
    await Clipboard.setData(ClipboardData(text: _lastSelectionTrace));
  }

  Future<void> _openSelectionTraceFolder() async {
    await _openDebugArtifactFolder(
      _EditorDebugArtifactType.selectionTraces,
      _selectionTraceSessionId,
    );
  }

  void _resetSelectionTraceSession(String reason) {
    _selectionTraceSequence = 0;
    _selectionTraceSessionId = _newEditorDebugSessionId();
    _lastSelectionTrace = 'Selection trace session reset: $reason';
    _lastSelectionTraceScreenshotPath = null;
    _lastSelectionTraceLogPath = null;
  }
}
