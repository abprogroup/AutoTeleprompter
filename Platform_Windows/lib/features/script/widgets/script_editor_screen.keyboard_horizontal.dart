part of 'script_editor_screen.dart';

extension _ScriptEditorKeyboardHorizontalParts on _ScriptEditorScreenState {
  ({int block, int offset})? _arrowTargetFromPosition({
    required LogicalKeyboardKey key,
    required int block,
    required int offset,
    required HardwareKeyboard keyboard,
    required bool allowInBlockHorizontalStep,
    required bool allowInBlockVerticalStep,
  }) {
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (keyboard.isControlPressed) {
        return _controlVerticalTarget(
          blockIndex: block,
          focusOffset: offset,
          moveUp: key == LogicalKeyboardKey.arrowUp,
        );
      }
      return _verticalBoundaryTarget(
        blockIndex: block,
        focusOffset: offset,
        moveUp: key == LogicalKeyboardKey.arrowUp,
        allowInBlockStep: allowInBlockVerticalStep,
      );
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (_isControlArrowModifierState(keyboard)) {
        return _controlHorizontalWordTarget(
          blockIndex: block,
          rawOffset: offset,
          key: key,
        );
      }
      return _horizontalTargetFromPosition(
        blockIndex: block,
        rawOffset: offset,
        key: key,
        allowInBlockStep: allowInBlockHorizontalStep,
      );
    }
    if (_isHomeEndKey(key)) {
      if (keyboard.isControlPressed || keyboard.isMetaPressed) {
        return null;
      }
      return _homeEndTarget(
        blockIndex: block,
        rawOffset: offset,
        key: key,
      );
    }
    return null;
  }

  ({int block, int offset})? _controlHorizontalWordTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final rawText = _controllers[blockIndex].text;
    final safeRaw = rawOffset.clamp(0, rawText.length).toInt();
    final effectiveRaw = _effectiveVisibleCaretRawOffset(rawText, safeRaw);
    final layout = _getVerticalLayout(
      blockIndex,
      selection: TextSelection.collapsed(offset: effectiveRaw),
    );
    final visualTarget = layout.visualWordTargetRawOffset(
      rawText: rawText,
      rawOffset: effectiveRaw,
      moveLeft: key == LogicalKeyboardKey.arrowLeft,
    );
    if (visualTarget != null) {
      final safeTarget = visualTarget.clamp(0, rawText.length).toInt();
      if (safeTarget != effectiveRaw || effectiveRaw != safeRaw) {
        if (!_renderOffsetsShareVisualLine(
          blockIndex: blockIndex,
          firstRaw: effectiveRaw,
          secondRaw: safeTarget,
        )) {
          final edgeTarget = _lineEdgeTargetInBlock(
            blockIndex: blockIndex,
            rawOffset: effectiveRaw,
            visualRight: key == LogicalKeyboardKey.arrowRight,
          );
          if (edgeTarget != null && edgeTarget.offset != effectiveRaw) {
            return edgeTarget;
          }
          return _horizontalBoundaryTargetFromPosition(
            blockIndex: blockIndex,
            rawOffset: effectiveRaw,
            key: key,
          );
        }
        return (block: blockIndex, offset: safeTarget);
      }
    }

    return _horizontalBoundaryTargetFromPosition(
      blockIndex: blockIndex,
      rawOffset: effectiveRaw,
      key: key,
    );
  }

  bool _renderOffsetsShareVisualLine({
    required int blockIndex,
    required int firstRaw,
    required int secondRaw,
  }) {
    final lines = _renderEditableLinesForBlock(blockIndex);
    if (lines.isEmpty) return true;
    final firstLine = _renderEditableLineIndexForOffset(
      block: blockIndex,
      offset: firstRaw,
      lines: lines,
    );
    final secondLine = _renderEditableLineIndexForOffset(
      block: blockIndex,
      offset: secondRaw,
      lines: lines,
    );
    return firstLine == null || secondLine == null || firstLine == secondLine;
  }

  ({int block, int offset})? _lineEdgeTargetInBlock({
    required int blockIndex,
    required int rawOffset,
    required bool visualRight,
  }) {
    if (_isEditorBlockVisiblyBlank(blockIndex)) return null;
    final lines = _renderEditableLinesForBlock(blockIndex);
    if (lines.isEmpty) return null;
    final currentLine = _renderEditableLineIndexForOffset(
      block: blockIndex,
      offset: rawOffset,
      lines: lines,
    );
    if (currentLine == null) return null;
    final candidate = _lineEdgeCandidate(
      blockIndex: blockIndex,
      line: lines[currentLine],
      visualRight: visualRight,
    );
    if (candidate == null) return null;
    return (block: blockIndex, offset: candidate.raw);
  }

  List<List<_RenderCaretCandidate>> _renderEditableLinesForBlock(
    int blockIndex,
  ) {
    final candidates = _renderEditableCaretCandidatesForBlock(blockIndex);
    if (candidates.isEmpty) return const [];
    return _groupRenderCaretCandidatesByLine(candidates);
  }

  _RenderCaretCandidate? _lineEdgeCandidate({
    required int blockIndex,
    required List<_RenderCaretCandidate> line,
    required bool visualRight,
  }) {
    if (line.isEmpty) return null;
    final isRtl = _editorBlockResolvedRtl(blockIndex);
    final edgeX = visualRight
        ? line.map((candidate) => candidate.x).reduce((a, b) => a > b ? a : b)
        : line.map((candidate) => candidate.x).reduce((a, b) => a < b ? a : b);
    final edgeCandidates =
        line.where((candidate) => (candidate.x - edgeX).abs() <= 0.75).toList();
    if (edgeCandidates.isEmpty) return null;
    edgeCandidates.sort((a, b) => a.raw.compareTo(b.raw));
    final preferLowRaw = visualRight ? isRtl : !isRtl;
    final selected = preferLowRaw ? edgeCandidates.first : edgeCandidates.last;
    final trimmed = _trimLineEdgeOffset(
      blockIndex: blockIndex,
      rawOffset: selected.raw,
      line: line,
      visualRight: visualRight,
    );
    return _RenderCaretCandidate(raw: trimmed, x: selected.x, y: selected.y);
  }

  int _trimLineEdgeOffset({
    required int blockIndex,
    required int rawOffset,
    required List<_RenderCaretCandidate> line,
    required bool visualRight,
  }) {
    final rawText = _controllers[blockIndex].text;
    final visible = EditorTextGeometryService.visibleText(rawText);
    if (visible.isEmpty) return 0;
    var start = visible.length;
    var end = 0;
    for (final candidate in line) {
      final visibleOffset = MarkupController.rawToVisualOffset(
        rawText,
        candidate.raw.clamp(0, rawText.length).toInt(),
      ).clamp(0, visible.length).toInt();
      if (visibleOffset < start) start = visibleOffset;
      if (visibleOffset > end) end = visibleOffset;
    }
    if (start > end) return rawOffset.clamp(0, rawText.length).toInt();
    final isRtl = _editorBlockResolvedRtl(blockIndex);
    final semanticStart = visualRight == isRtl;
    var visibleOffset = MarkupController.rawToVisualOffset(
      rawText,
      rawOffset.clamp(0, rawText.length).toInt(),
    ).clamp(start, end).toInt();
    if (semanticStart) {
      while (visibleOffset < end && visible[visibleOffset].trim().isEmpty) {
        visibleOffset++;
      }
    } else {
      while (
          visibleOffset > start && visible[visibleOffset - 1].trim().isEmpty) {
        visibleOffset--;
      }
    }
    return MarkupController.visualToRawOffset(rawText, visibleOffset)
        .clamp(0, rawText.length)
        .toInt();
  }

  ({int block, int offset})? _verticalBoundaryTarget({
    required int blockIndex,
    required int focusOffset,
    required bool moveUp,
    required bool allowInBlockStep,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    final safeFocus = focusOffset.clamp(0, text.length).toInt();
    final endOffset = MarkupController.safeEndOffset(text);
    if (moveUp) {
      if (safeFocus > 0 && allowInBlockStep) {
        return (block: blockIndex, offset: 0);
      }
      if (safeFocus <= 0 && blockIndex > 0) {
        return (
          block: blockIndex - 1,
          offset: MarkupController.safeEndOffset(
            _controllers[blockIndex - 1].text,
          ),
        );
      }
      return null;
    }
    if (safeFocus < endOffset && allowInBlockStep) {
      return (block: blockIndex, offset: endOffset);
    }
    if (safeFocus >= endOffset && blockIndex < _controllers.length - 1) {
      return (block: blockIndex + 1, offset: 0);
    }
    return null;
  }

  ({int block, int offset})? _horizontalTargetFromPosition({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
    required bool allowInBlockStep,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final rawText = _controllers[blockIndex].text;
    final visibleText = StylingService.stripTags(rawText);
    if (visibleText.isEmpty) {
      return _horizontalBoundaryTargetFromPosition(
        blockIndex: blockIndex,
        rawOffset: rawOffset,
        key: key,
      );
    }

    final safeRaw = rawOffset.clamp(0, rawText.length).toInt();
    final currentVisible = MarkupController.rawToVisualOffset(
      rawText,
      safeRaw,
    ).clamp(0, visibleText.length).toInt();
    final currentRaw = MarkupController.visualToRawOffset(
      rawText,
      currentVisible,
    );

    final layout = _getVerticalLayout(
      blockIndex,
      selection: TextSelection.collapsed(offset: currentRaw),
    );
    final targetRaw = layout.visualHorizontalTargetRawOffset(
      rawText: rawText,
      rawOffset: currentRaw,
      moveLeft: key == LogicalKeyboardKey.arrowLeft,
    );
    if (targetRaw != null) {
      if (!allowInBlockStep) return null;
      final target = targetRaw.clamp(0, rawText.length).toInt();
      if (target == safeRaw) return null;
      return (block: blockIndex, offset: target);
    }

    return _horizontalBoundaryTargetFromPosition(
      blockIndex: blockIndex,
      rawOffset: rawOffset,
      key: key,
    );
  }

  ({int block, int offset})? _horizontalBoundaryTargetFromPosition({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final controller = _controllers[blockIndex];
    final isRtl = _editorBlockResolvedRtl(blockIndex);
    final visibleText = StylingService.stripTags(controller.text);
    final visibleLength = visibleText.length;
    final safeRaw = rawOffset.clamp(0, controller.text.length).toInt();
    final visibleOffset = MarkupController.rawToVisualOffset(
      controller.text,
      safeRaw,
    ).clamp(0, visibleLength).toInt();
    final atVisibleStart = visibleOffset <= 0;
    final atVisibleEnd = visibleOffset >= visibleLength;

    if (!isRtl) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (!atVisibleStart) return null;
        if (blockIndex <= 0) return null;
        return (
          block: blockIndex - 1,
          offset: MarkupController.safeEndOffset(
            _controllers[blockIndex - 1].text,
          ),
        );
      }
      if (!atVisibleEnd) return null;
      if (blockIndex >= _controllers.length - 1) return null;
      return (block: blockIndex + 1, offset: 0);
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!atVisibleEnd) return null;
      if (blockIndex >= _controllers.length - 1) return null;
      return (block: blockIndex + 1, offset: 0);
    }
    if (!atVisibleStart) return null;
    if (blockIndex <= 0) return null;
    return (
      block: blockIndex - 1,
      offset: MarkupController.safeEndOffset(_controllers[blockIndex - 1].text),
    );
  }
}
