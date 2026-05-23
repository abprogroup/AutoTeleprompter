part of 'script_editor_screen.dart';

extension _ScriptEditorArrowTraceParts on _ScriptEditorScreenState {
  bool get _shouldCaptureArrowTrace {
    if (!mounted) return false;
    return ref.read(settingsProvider).debugMode;
  }

  void _recordVerticalArrowTrace({
    required LogicalKeyboardKey key,
    required int blockIndex,
    required int rawOffset,
    required bool isRtl,
    required _VerticalLayoutInfo layout,
    required double preferredX,
    required ({int block, int offset})? target,
  }) {
    if (!_shouldCaptureArrowTrace) return;

    final sequence = ++_arrowTraceSequence;
    final beforeTrace = _buildVerticalArrowTrace(
      sequence: sequence,
      key: key,
      blockIndex: blockIndex,
      rawOffset: rawOffset,
      isRtl: isRtl,
      layout: layout,
      preferredX: preferredX,
      target: target,
    );

    _setEditorState(() {
      _lastArrowTrace = '$beforeTrace\n\nAFTER: waiting for next frame...';
      _lastArrowTraceScreenshotPath = null;
      _lastArrowTraceLogPath = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_finishVerticalArrowTrace(sequence, beforeTrace));
    });
  }

  void _recordNativeArrowTrace(
    KeyEvent event, {
    String mode = 'native TextField pass-through',
  }) {
    if (!_shouldCaptureArrowTrace) return;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return;
    }

    final blockIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    if (blockIndex < 0 || blockIndex >= _controllers.length) return;
    final controller = _controllers[blockIndex];
    final selection = controller.selection.isValid
        ? controller.selection
        : const TextSelection.collapsed(offset: 0);
    final rawOffset =
        selection.extentOffset.clamp(0, controller.text.length).toInt();
    final isRtl = _editorBlockResolvedRtl(blockIndex);
    final layout = _getVerticalLayout(
      blockIndex,
      selection: TextSelection.collapsed(
        offset: rawOffset,
        affinity: selection.affinity,
      ),
    );
    final sequence = ++_arrowTraceSequence;
    final beforeTrace = (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)
        ? '${_buildVerticalArrowTrace(sequence: sequence, key: key, blockIndex: blockIndex, rawOffset: rawOffset, isRtl: isRtl, layout: layout, preferredX: layout.currentX, target: null)}\nmode=$mode'
        : _buildHorizontalArrowTrace(
            sequence: sequence,
            key: key,
            blockIndex: blockIndex,
            rawOffset: rawOffset,
            isRtl: isRtl,
            layout: layout,
            mode: mode,
          );

    _setEditorState(() {
      _lastArrowTrace = '$beforeTrace\n\nAFTER: waiting for next frame...';
      _lastArrowTraceScreenshotPath = null;
      _lastArrowTraceLogPath = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_finishVerticalArrowTrace(sequence, beforeTrace));
    });
  }

  String _buildVerticalArrowTrace({
    required int sequence,
    required LogicalKeyboardKey key,
    required int blockIndex,
    required int rawOffset,
    required bool isRtl,
    required _VerticalLayoutInfo layout,
    required double preferredX,
    required ({int block, int offset})? target,
  }) {
    final controller = _controllers[blockIndex];
    final rawText = controller.text;
    final visibleText = EditorTextGeometryService.visibleText(rawText);
    final safeRaw = rawOffset.clamp(0, rawText.length).toInt();
    final visibleOffset = MarkupController.rawToVisualOffset(
      rawText,
      safeRaw,
    ).clamp(0, visibleText.length).toInt();
    final currentLine = layout.lineIndexForOffset(safeRaw);
    final targetLine =
        currentLine + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
    final currentStops = layout.debugCaretStopsForLine(
      rawText: rawText,
      line: currentLine,
    );
    final targetStops = targetLine >= 0
        ? layout.debugCaretStopsForLine(rawText: rawText, line: targetLine)
        : const <String>[];
    final selectedTarget = target == null
        ? 'none'
        : '${target.block}:${target.offset}'
            ' visible=${_debugVisibleOffsetForBlock(target.block, target.offset)}';

    return [
      'ARROW TRACE #$sequence',
      'time=${DateTime.now().toIso8601String()}',
      'key=${key.keyLabel} block=$blockIndex raw=$safeRaw visible=$visibleOffset',
      _arrowModifierTraceLine(),
      _debugFocusAuthorityLine(),
      'direction=${isRtl ? "RTL" : "LTR"} align=${layout.painter.textAlign} width=${layout.layoutWidth.toStringAsFixed(1)}',
      'line=$currentLine targetLine=$targetLine lines=${layout.lineCount}',
      'currentX=${layout.currentX.toStringAsFixed(2)} preferredX=${preferredX.toStringAsFixed(2)}',
      'target=$selectedTarget',
      'visibleContext=${_debugVisibleContext(visibleText, visibleOffset)}',
      'lineMetrics:',
      layout.debugLineMetrics(),
      'currentLineStops:',
      if (currentStops.isEmpty) '  <none>' else ...currentStops,
      'targetLineStops:',
      if (targetStops.isEmpty) '  <none>' else ...targetStops,
    ].join('\n');
  }

  String _buildHorizontalArrowTrace({
    required int sequence,
    required LogicalKeyboardKey key,
    required int blockIndex,
    required int rawOffset,
    required bool isRtl,
    required _VerticalLayoutInfo layout,
    String mode = 'native TextField pass-through',
  }) {
    final controller = _controllers[blockIndex];
    final rawText = controller.text;
    final visibleText = EditorTextGeometryService.visibleText(rawText);
    final safeRaw = rawOffset.clamp(0, rawText.length).toInt();
    final visibleOffset = MarkupController.rawToVisualOffset(
      rawText,
      safeRaw,
    ).clamp(0, visibleText.length).toInt();
    final line = layout.lineIndexForOffset(safeRaw);
    final lineStops = layout.debugCaretStopsForLine(
      rawText: rawText,
      line: line,
    );

    return [
      'ARROW TRACE #$sequence',
      'time=${DateTime.now().toIso8601String()}',
      'key=${key.keyLabel} block=$blockIndex raw=$safeRaw visible=$visibleOffset',
      _arrowModifierTraceLine(),
      _debugFocusAuthorityLine(),
      'direction=${isRtl ? "RTL" : "LTR"} align=${layout.painter.textAlign} width=${layout.layoutWidth.toStringAsFixed(1)}',
      'line=$line lines=${layout.lineCount}',
      'currentX=${layout.currentX.toStringAsFixed(2)}',
      'mode=$mode',
      'visibleContext=${_debugVisibleContext(visibleText, visibleOffset)}',
      'lineMetrics:',
      layout.debugLineMetrics(),
      'lineStops:',
      if (lineStops.isEmpty) '  <none>' else ...lineStops,
    ].join('\n');
  }

  Future<void> _finishVerticalArrowTrace(
    int sequence,
    String beforeTrace,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted || !_shouldCaptureArrowTrace) return;

    final afterTrace = _buildPostArrowTrace();
    final directory = await _ensureDebugArtifactDirectory(
      _EditorDebugArtifactType.arrowTraces,
      _arrowTraceSessionId,
    );
    if (directory == null) return;
    final screenshotPath = await _captureArrowTraceScreenshot(
      directory: directory,
      sequence: sequence,
    );
    final logPath = await _writeArrowTraceLog(
      directory: directory,
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
    _setEditorState(() {
      _lastArrowTrace = [
        beforeTrace,
        '',
        afterTrace,
        '',
        'screenshot=${screenshotPath ?? "not captured"}',
        'log=$logPath',
      ].join('\n');
      _lastArrowTraceScreenshotPath = screenshotPath;
      _lastArrowTraceLogPath = logPath;
    });
  }

  String _buildPostArrowTrace() {
    if (_controllers.isEmpty) return 'AFTER: no controllers';
    final focusedBlock = _focusNodes.indexWhere((node) => node.hasFocus);
    final activeBlock = focusedBlock >= 0
        ? focusedBlock
        : _controllers.indexOf(_lastFocusedController ?? _controllers.first);
    if (activeBlock < 0 || activeBlock >= _controllers.length) {
      return 'AFTER: no active block';
    }
    final controller = _controllers[activeBlock];
    final selection = controller.selection;
    final safeOffset =
        selection.extentOffset.clamp(0, controller.text.length).toInt();
    final layout = _getVerticalLayout(
      activeBlock,
      selection: TextSelection.collapsed(
        offset: safeOffset,
        affinity: selection.affinity,
      ),
    );
    final visibleText = EditorTextGeometryService.visibleText(controller.text);
    final visibleOffset = MarkupController.rawToVisualOffset(
      controller.text,
      safeOffset,
    ).clamp(0, visibleText.length).toInt();
    final renderPoint = _debugRenderEditableCaretPoint(
      blockIndex: activeBlock,
      offset: safeOffset,
    );
    return [
      'AFTER:',
      _debugFocusAuthorityLine(),
      _debugSelectionAuthorityLine(),
      'activeBlock=$activeBlock raw=$safeOffset visible=$visibleOffset',
      'selection=[${selection.baseOffset}, ${selection.extentOffset}] affinity=${selection.affinity.name}',
      'line=${layout.lineIndexForOffset(safeOffset)} x=${layout.currentX.toStringAsFixed(2)} preferredX=${_verticalArrowPreferredX?.toStringAsFixed(2) ?? "null"}',
      'renderEditableCaret=${renderPoint ?? "not found"}',
      'visibleContext=${_debugVisibleContext(visibleText, visibleOffset)}',
    ].join('\n');
  }

  String _debugFocusAuthorityLine() {
    final focusedBlock = _focusNodes.indexWhere((node) => node.hasFocus);
    final lastControllerBlock = _lastFocusedController == null
        ? -1
        : _controllers.indexOf(_lastFocusedController!);
    final activeController = _activeController;
    final activeControllerBlock =
        activeController == null ? -1 : _controllers.indexOf(activeController);
    return 'focusAuthority focused=$focusedBlock last=$lastControllerBlock active=$activeControllerBlock';
  }

  String _arrowModifierTraceLine() {
    final keyboard = HardwareKeyboard.instance;
    final modifiers = <String>[
      if (keyboard.isControlPressed) 'ctrl',
      if (keyboard.isShiftPressed) 'shift',
      if (keyboard.isAltPressed) 'alt',
      if (keyboard.isMetaPressed) 'meta',
    ];
    return 'modifiers=${modifiers.isEmpty ? "none" : modifiers.join("+")}';
  }

  String? _debugRenderEditableCaretPoint({
    required int blockIndex,
    required int offset,
  }) {
    if (blockIndex < 0 || blockIndex >= _blockKeys.length) return null;
    final renderObject =
        _blockKeys[blockIndex].currentContext?.findRenderObject();
    final editable = _findRenderEditable(renderObject);
    if (editable == null) return null;
    final safeOffset =
        offset.clamp(0, _controllers[blockIndex].text.length).toInt();
    final endpoints = editable.getEndpointsForSelection(
      TextSelection.collapsed(offset: safeOffset),
    );
    if (endpoints.isEmpty) return null;
    final point = endpoints.first.point;
    return 'x=${point.dx.toStringAsFixed(2)} y=${point.dy.toStringAsFixed(2)}';
  }

  RenderEditable? _findRenderEditable(RenderObject? root) {
    if (root == null) return null;
    if (root is RenderEditable) return root;
    RenderEditable? result;
    root.visitChildren((child) {
      result ??= _findRenderEditable(child);
    });
    return result;
  }

  Future<String?> _captureArrowTraceScreenshot({
    required Directory directory,
    required int sequence,
  }) async {
    return _captureEditorDebugScreenshot(
      directory: directory,
      prefix: 'arrow',
      sequence: sequence,
    );
  }

  Future<String?> _writeArrowTraceLog({
    required Directory directory,
    required int sequence,
    required String trace,
  }) async {
    return _writeDebugArtifactLog(
      directory: directory,
      prefix: 'arrow',
      sequence: sequence,
      trace: trace,
    );
  }

  void _resetArrowTraceSession(String reason) {
    _arrowTraceSequence = 0;
    _arrowTraceSessionId = _newEditorDebugSessionId();
    _lastArrowTrace = 'Arrow trace session reset: $reason';
    _lastArrowTraceScreenshotPath = null;
    _lastArrowTraceLogPath = null;
  }

  int _debugVisibleOffsetForBlock(int blockIndex, int rawOffset) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return -1;
    final rawText = _controllers[blockIndex].text;
    final visibleText = EditorTextGeometryService.visibleText(rawText);
    return MarkupController.rawToVisualOffset(
      rawText,
      rawOffset,
    ).clamp(0, visibleText.length).toInt();
  }

  String _debugVisibleContext(String visibleText, int visibleOffset) {
    final safeOffset = visibleOffset.clamp(0, visibleText.length).toInt();
    final start = (safeOffset - 28).clamp(0, visibleText.length).toInt();
    final end = (safeOffset + 28).clamp(start, visibleText.length).toInt();
    final before = visibleText.substring(start, safeOffset);
    final after = visibleText.substring(safeOffset, end);
    return '"${_debugSanitize(before)}|${_debugSanitize(after)}"';
  }

  String _debugSanitize(String value) {
    return value.replaceAll('\n', r'\n').replaceAll('\r', r'\r');
  }

  Future<void> _copyLastArrowTrace() async {
    await Clipboard.setData(ClipboardData(text: _lastArrowTrace));
  }

  Future<void> _openArrowTraceFolder() async {
    await _openDebugArtifactFolder(
      _EditorDebugArtifactType.arrowTraces,
      _arrowTraceSessionId,
    );
  }
}
