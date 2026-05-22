part of 'script_editor_screen.dart';

extension _ScriptEditorHighlightTraceParts on _ScriptEditorScreenState {
  void _scheduleHighlightTrace(String reason) {
    if (!mounted || !ref.read(settingsProvider).debugMode) return;
    _highlightTraceTimer?.cancel();
    _highlightTraceTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted) {
        unawaited(_captureCurrentHighlightTrace(reason: reason));
      }
    });
  }

  Future<void> _captureCurrentHighlightTrace({
    String reason = 'manual',
  }) async {
    final sequence = ++_highlightTraceSequence;
    final trace = _buildHighlightTrace(sequence, reason);
    setState(() {
      _lastHighlightTrace = '$trace\n\nscreenshot=waiting...';
      _lastHighlightTraceScreenshotPath = null;
      _lastHighlightTraceLogPath = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 90));
    final directory = await _ensureHighlightTraceDirectory();
    final screenshotPath = await _captureHighlightTraceScreenshot(
      directory: directory,
      sequence: sequence,
    );
    final logPath = await _writeHighlightTraceLog(
      directory: directory,
      sequence: sequence,
      trace: [
        trace,
        '',
        'screenshot=${screenshotPath ?? "not captured"}',
      ].join('\n'),
    );

    if (!mounted) return;
    setState(() {
      _lastHighlightTrace = [
        trace,
        '',
        'screenshot=${screenshotPath ?? "not captured"}',
        'log=$logPath',
      ].join('\n');
      _lastHighlightTraceScreenshotPath = screenshotPath;
      _lastHighlightTraceLogPath = logPath;
    });
  }

  String _buildHighlightTrace(int sequence, String reason) {
    final settings = ref.read(settingsProvider);
    final blocks = _highlightTraceBlocks();
    return [
      'HIGHLIGHT TRACE #$sequence',
      'time=${DateTime.now().toIso8601String()}',
      'reason=$reason',
      'font=${settings.fontSize.toStringAsFixed(2)} '
          'line=${settings.lineSpacing.toStringAsFixed(3)} '
          'letter=${settings.letterSpacing.toStringAsFixed(2)} '
          'word=${settings.wordSpacing.toStringAsFixed(2)}',
      'search=${_editorSearchToolbarVisible ? "${_editorSearchMatchIndex + 1}/${_editorSearchMatches.length}" : "off"} '
          'global=$_isGlobalSelection overlay=${_overlayKey.currentState?.debugSelectionSummary ?? "none"}',
      if (blocks.isEmpty) '<no highlighted/visible selected blocks found>',
      for (final block in blocks) _buildHighlightBlockTrace(block),
    ].join('\n');
  }

  List<int> _highlightTraceBlocks() {
    if (_editorSearchToolbarVisible &&
        _editorSearchMatchIndex >= 0 &&
        _editorSearchMatchIndex < _editorSearchMatches.length) {
      return [_editorSearchMatches[_editorSearchMatchIndex].blockIndex];
    }

    final selected = <int>[];
    for (var i = 0; i < _controllers.length; i++) {
      final c = _controllers[i];
      final hasSelection = c.isGlobalSelected ||
          (c.externalSelection != null &&
              c.externalSelection!.isValid &&
              !c.externalSelection!.isCollapsed) ||
          (_focusNodes[i].hasFocus &&
              c.selection.isValid &&
              !c.selection.isCollapsed);
      if (hasSelection && _isEditorBlockVisibleForTrace(i)) {
        selected.add(i);
      }
    }
    if (selected.isNotEmpty) return selected.take(12).toList(growable: false);

    final focused = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focused >= 0) return [focused];
    final active = _lastFocusedController == null
        ? -1
        : _controllers.indexOf(_lastFocusedController!);
    if (active >= 0) return [active];
    return const [];
  }

  bool _isEditorBlockVisibleForTrace(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _blockKeys.length) return false;
    final boundaryBox = _editorArrowTraceBoundaryKey.currentContext
        ?.findRenderObject() as RenderBox?;
    final blockBox =
        _blockKeys[blockIndex].currentContext?.findRenderObject() as RenderBox?;
    if (boundaryBox == null || blockBox == null) return true;
    final topLeft = blockBox.localToGlobal(Offset.zero, ancestor: boundaryBox);
    final rect = topLeft & blockBox.size;
    final viewport = Offset.zero & boundaryBox.size;
    return rect.overlaps(viewport.inflate(80));
  }

  String _buildHighlightBlockTrace(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) {
      return 'block=$blockIndex <invalid>';
    }
    final c = _controllers[blockIndex];
    final settings = ref.read(settingsProvider);
    final raw = c.text;
    final visible = MarkupDecorationParser.visibleText(raw);
    final rawSelection = _highlightRawSelectionForBlock(blockIndex);
    final visibleSelection = _highlightVisibleSelectionForBlock(
      blockIndex,
      rawSelection,
    );
    final isRtl = _editorBlockResolvedRtl(blockIndex);
    final textDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;
    final textAlign = _highlightTextAlign(raw, isRtl);
    final textScaler = MediaQuery.textScalerOf(context);
    final editable = _findRenderEditable(
      _blockKeys[blockIndex].currentContext?.findRenderObject(),
    );
    final layoutWidth = (editable?.size.width ?? 0) > 0
        ? editable!.size.width
        : _fallbackTraceWidth(blockIndex);
    final style = TextStyle(
      color: Colors.white,
      fontSize: settings.fontSize,
      height: settings.lineSpacing,
      letterSpacing: settings.letterSpacing,
      wordSpacing: settings.wordSpacing,
    );
    final strut = StrutStyle(
      fontSize: EditorTextGeometryService.maxFontSize(raw, settings.fontSize),
      height: settings.lineSpacing,
      forceStrutHeight: true,
    );
    final visibleGeometry = MarkupTextLayoutGeometry(
      textSpan: MarkupDecorationParser.visibleTextSpan(raw, style: style),
      width: layoutWidth,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      strutStyle: strut,
    );
    final rawGeometry = MarkupTextLayoutGeometry(
      textSpan: c.buildTextSpan(
        context: context,
        style: style,
        withComposing: false,
      ),
      width: layoutWidth,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      strutStyle: strut,
    );

    final fullVisibleSelection = visibleSelection != null &&
        visibleSelection.start <= 0 &&
        visibleSelection.end >= visible.length;
    final renderEditableBoxes = rawSelection == null || editable == null
        ? const <Rect>[]
        : MarkupRenderEditableGeometry.selectionRects(
            editable,
            rawSelection,
          );
    final finalRenderBands = rawSelection == null || editable == null
        ? const <Rect>[]
        : MarkupRenderEditableGeometry.mergedBandsForSelection(
            editable,
            rawSelection,
          );
    final rawPainterBoxes = rawSelection == null
        ? const <Rect>[]
        : rawGeometry.selectionRects(
            rawSelection,
            boxHeightStyle: ui.BoxHeightStyle.strut,
            alignToVisualLine: false,
          );
    final rawAlignedPainterBoxes = rawSelection == null
        ? const <Rect>[]
        : rawGeometry.selectionRects(
            rawSelection,
            boxHeightStyle: ui.BoxHeightStyle.strut,
          );
    final rawOwnershipBoxes = rawSelection == null
        ? const <Rect>[]
        : rawGeometry.selectionRects(rawSelection);
    final visiblePainterBoxes = visibleSelection == null
        ? const <Rect>[]
        : visibleGeometry.selectionRects(
            visibleSelection,
            boxHeightStyle: ui.BoxHeightStyle.strut,
            alignToVisualLine: fullVisibleSelection,
          );
    final visibleActiveMergedRects = visibleSelection == null
        ? const <Rect>[]
        : visibleGeometry.mergedActiveSelectionRects(
            visibleSelection,
            fluidFullLine: true,
          );
    final rawActiveMergedRects = rawSelection == null
        ? const <Rect>[]
        : rawGeometry.mergedActiveSelectionRects(
            rawSelection,
            fluidFullLine: true,
          );
    final finalPaintRects = finalRenderBands;
    final tightVisibleBoxes = visibleSelection == null
        ? const <Rect>[]
        : visibleGeometry.selectionRects(
            visibleSelection,
            alignToVisualLine: false,
          );

    return [
      '',
      'BLOCK $blockIndex',
      'rawLen=${raw.length} visibleLen=${visible.length} '
          'direction=${isRtl ? "RTL" : "LTR"} align=$textAlign '
          'editableWidth=${editable?.size.width.toStringAsFixed(2) ?? "none"} '
          'layoutWidth=${layoutWidth.toStringAsFixed(2)}',
      'rawSelection=${_formatSelection(rawSelection)} '
          'visibleSelection=${_formatSelection(visibleSelection)} '
          'fullVisible=$fullVisibleSelection',
      'visibleContext=${visibleSelection == null ? "none" : _debugVisibleContext(visible, visibleSelection.start)}',
      'paintMode=render-editable-selection-band',
      'ownershipBoxes=RenderEditable.getBoxesForSelection(raw actual)',
      'renderEditableBoxes(raw actual): ${_formatRects(renderEditableBoxes)}',
      'finalRenderBands(raw actual): ${_formatRects(finalRenderBands)}',
      'rawPainterBoxes(raw hidden-tags): ${_formatRects(rawPainterBoxes)}',
      'rawAlignedPainterBoxes(active input): ${_formatRects(rawAlignedPainterBoxes)}',
      'serviceTightBoxes(diagnostic only): ${_formatRects(rawOwnershipBoxes)}',
      'visiblePainterBoxes(active input): ${_formatRects(visiblePainterBoxes)}',
      'tightVisibleBoxes(no strut/no align): ${_formatRects(tightVisibleBoxes)}',
      'SERVICE_RAW_ACTIVE_SELECTION_BANDS: ${_formatRects(rawActiveMergedRects)}',
      'VISIBLE_ACTIVE_SELECTION_BANDS: ${_formatRects(visibleActiveMergedRects)}',
      'ACTIVE_SELECTION_BANDS: ${_formatRects(finalPaintRects)}',
      _highlightDeltaLine(
          'renderBoxes->final', renderEditableBoxes, finalPaintRects),
      _highlightDeltaLine(
          'rawPainter->final', rawPainterBoxes, finalPaintRects),
      _highlightDeltaLine(
          'visiblePainter->final', visiblePainterBoxes, finalPaintRects),
      _decorationTrace(raw, rawGeometry),
    ].join('\n');
  }

  TextSelection? _highlightRawSelectionForBlock(int blockIndex) {
    final c = _controllers[blockIndex];
    if (_editorSearchToolbarVisible &&
        _editorSearchMatchIndex >= 0 &&
        _editorSearchMatchIndex < _editorSearchMatches.length) {
      final match = _editorSearchMatches[_editorSearchMatchIndex];
      if (match.blockIndex == blockIndex) {
        final rawStart = MarkupController.visualToRawOffset(
          c.text,
          match.visibleStart,
        );
        final rawEnd = MarkupController.visualToRawOffset(
          c.text,
          match.visibleEnd,
        ).clamp(rawStart, c.text.length);
        return TextSelection(baseOffset: rawStart, extentOffset: rawEnd);
      }
    }
    if (c.isGlobalSelected || _isGlobalSelection) {
      return TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
    if (c.externalSelection != null &&
        c.externalSelection!.isValid &&
        !c.externalSelection!.isCollapsed) {
      return c.externalSelection;
    }
    if (c.selection.isValid && !c.selection.isCollapsed) return c.selection;
    return null;
  }

  TextSelection? _highlightVisibleSelectionForBlock(
    int blockIndex,
    TextSelection? rawSelection,
  ) {
    final c = _controllers[blockIndex];
    final visibleLength = MarkupDecorationParser.visibleText(c.text).length;
    if (_editorSearchToolbarVisible &&
        _editorSearchMatchIndex >= 0 &&
        _editorSearchMatchIndex < _editorSearchMatches.length) {
      final match = _editorSearchMatches[_editorSearchMatchIndex];
      if (match.blockIndex == blockIndex) {
        return TextSelection(
          baseOffset: match.visibleStart.clamp(0, visibleLength),
          extentOffset: match.visibleEnd.clamp(0, visibleLength),
        );
      }
    }
    if (c.isGlobalSelected || _isGlobalSelection) {
      return TextSelection(baseOffset: 0, extentOffset: visibleLength);
    }
    if (c.externalVisibleSelection != null &&
        c.externalVisibleSelection!.isValid &&
        !c.externalVisibleSelection!.isCollapsed) {
      return c.externalVisibleSelection;
    }
    if (rawSelection == null) return null;
    return MarkupDecorationParser.rawToVisibleSelection(c.text, rawSelection);
  }

  TextAlign _highlightTextAlign(String text, bool isRtl) {
    if (RegExp(r'\[(?:align=)?center\]').hasMatch(text)) {
      return TextAlign.center;
    }
    if (RegExp(r'\[(?:align=)?right\]').hasMatch(text)) {
      return TextAlign.right;
    }
    if (RegExp(r'\[(?:align=)?left\]').hasMatch(text)) {
      return TextAlign.left;
    }
    return isRtl ? TextAlign.right : TextAlign.left;
  }

  double _fallbackTraceWidth(int blockIndex) {
    final box =
        _blockKeys[blockIndex].currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 30) return 800;
    return box.size.width - 30;
  }

  String _decorationTrace(
    String raw,
    MarkupTextLayoutGeometry geometry,
  ) {
    final lines = <String>['decorations:'];
    var count = 0;
    for (final range in MarkupDecorationParser.decorationRanges(raw)) {
      if (count++ >= 8) {
        lines.add('  ...');
        break;
      }
      final paintable =
          MarkupDecorationParser.paintableContentRange(raw, range);
      if (paintable == null) {
        lines.add('  ${range.type.name} raw=${range.start}-${range.end} empty');
        continue;
      }
      final selection = TextSelection(
        baseOffset: paintable.start,
        extentOffset: paintable.end,
      );
      final rects = geometry.mergedDecorationRects(
        selection,
        type: range.type,
      );
      final visibleSelection =
          MarkupDecorationParser.rawToVisibleSelection(raw, selection);
      lines.add(
        '  ${range.type.name} raw=${paintable.start}-${paintable.end} '
        'visible=${visibleSelection.start}-${visibleSelection.end} '
        'rects=${_formatRects(rects)}',
      );
    }
    return lines.join('\n');
  }

  String _highlightDeltaLine(
    String label,
    List<Rect> source,
    List<Rect> target,
  ) {
    if (source.isEmpty || target.isEmpty) return '$label delta=<none>';
    final a = source.first;
    final b = target.first;
    return '$label firstDelta='
        'left=${(b.left - a.left).toStringAsFixed(2)} '
        'top=${(b.top - a.top).toStringAsFixed(2)} '
        'right=${(b.right - a.right).toStringAsFixed(2)} '
        'bottom=${(b.bottom - a.bottom).toStringAsFixed(2)}';
  }

  String _formatSelection(TextSelection? selection) {
    if (selection == null) return 'none';
    return '[${selection.baseOffset}, ${selection.extentOffset}] '
        'start=${selection.start} end=${selection.end}';
  }

  String _formatRects(List<Rect> rects) {
    if (rects.isEmpty) return '<none>';
    final shown = rects.take(8).map((rect) {
      return '(${rect.left.toStringAsFixed(1)},'
          '${rect.top.toStringAsFixed(1)} '
          '${rect.right.toStringAsFixed(1)},'
          '${rect.bottom.toStringAsFixed(1)} '
          'w=${rect.width.toStringAsFixed(1)} '
          'h=${rect.height.toStringAsFixed(1)})';
    }).join(' ');
    return rects.length > 8 ? '$shown ... total=${rects.length}' : shown;
  }

  Future<Directory> _ensureHighlightTraceDirectory() async {
    final projectRoot = _resolveProjectRootForDebugArtifacts();
    final directory = Directory(
      '${projectRoot.path}${Platform.pathSeparator}_debug'
      '${Platform.pathSeparator}Windows'
      '${Platform.pathSeparator}highlight_traces',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<String?> _captureHighlightTraceScreenshot({
    required Directory directory,
    required int sequence,
  }) async {
    try {
      final boundary = _editorArrowTraceBoundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final path = _highlightTracePath(directory, sequence, 'png');
      await File(path).writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      return path;
    } catch (error) {
      return 'capture failed: $error';
    }
  }

  Future<String> _writeHighlightTraceLog({
    required Directory directory,
    required int sequence,
    required String trace,
  }) async {
    final path = _highlightTracePath(directory, sequence, 'txt');
    await File(path).writeAsString(trace, flush: true);
    return path;
  }

  String _highlightTracePath(
    Directory directory,
    int sequence,
    String extension,
  ) {
    final timestamp = DateTime.now().toIso8601String().replaceAll(
          RegExp(r'[:.]'),
          '-',
        );
    return '${directory.path}${Platform.pathSeparator}'
        'highlight_${sequence.toString().padLeft(4, "0")}_$timestamp.$extension';
  }

  Future<void> _copyLastHighlightTrace() async {
    await Clipboard.setData(ClipboardData(text: _lastHighlightTrace));
  }
}
