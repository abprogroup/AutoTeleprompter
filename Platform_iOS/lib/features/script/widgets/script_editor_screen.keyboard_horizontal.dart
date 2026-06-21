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

  KeyEventResult? _handleHorizontalArrowKey({
    required KeyEvent event,
    required LogicalKeyboardKey key,
    required MarkupController controller,
    required int blockIndex,
    required bool isRtl,
    required TextSelection selection,
    required int textLength,
    required bool manualInBlock,
  }) {
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return null;
    }

    final keyboard = HardwareKeyboard.instance;
    if (!selection.isCollapsed) {
      if (_isControlArrowModifierState(keyboard, allowShift: false)) {
        final collapseToEnd = isRtl == (key == LogicalKeyboardKey.arrowLeft);
        final edge = collapseToEnd ? selection.end : selection.start;
        final offset = edge.clamp(0, textLength).toInt();
        _recordNativeArrowTrace(event,
            mode: 'ctrlOnlyNativeCollapse -> $offset');
        controller.selection = TextSelection.collapsed(offset: offset);
        _shiftSelectionAnchor = null;
        _shiftSelectionFocus = null;
        _lastFocusedController = controller;
        _focusNodes[blockIndex].requestFocus();
        return KeyEventResult.handled;
      }
      if (!isRtl) {
        if (keyboard.isAltPressed &&
            !keyboard.isShiftPressed &&
            !keyboard.isMetaPressed) {
          final offset = key == LogicalKeyboardKey.arrowLeft
              ? selection.start.clamp(0, textLength).toInt()
              : selection.end.clamp(0, textLength).toInt();
          _recordNativeArrowTrace(
            event,
            mode: 'focus LTR alt normalized selection collapse -> $offset',
          );
          controller.selection = TextSelection.collapsed(offset: offset);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      final offset = key == LogicalKeyboardKey.arrowLeft
          ? selection.end.clamp(0, textLength).toInt()
          : selection.start.clamp(0, textLength).toInt();
      controller.selection = TextSelection.collapsed(offset: offset);
      return KeyEventResult.handled;
    }

    final plainArrow = _isPlainArrowModifierState(keyboard);
    if (plainArrow) {
      final hiddenPrefixTarget = _leadingHiddenPrefixPlainHorizontalTarget(
        blockIndex: blockIndex,
        rawOffset: selection.baseOffset,
        key: key,
        isRtl: isRtl,
      );
      if (hiddenPrefixTarget != null) {
        _recordNativeArrowTrace(
          event,
          mode:
              'focus hidden-prefix trap -> ${hiddenPrefixTarget.block}:${hiddenPrefixTarget.offset}',
        );
        if (hiddenPrefixTarget.block == blockIndex) {
          controller.selection = TextSelection.collapsed(
            offset: hiddenPrefixTarget.offset,
          );
          _suppressActiveArrowEventOnce();
        } else {
          _crossToBlock(
            hiddenPrefixTarget.block,
            atOffset: hiddenPrefixTarget.offset,
          );
        }
        return KeyEventResult.handled;
      }

      final bookmarkTarget = _leadingBookmarkPlainHorizontalTarget(
        blockIndex: blockIndex,
        rawOffset: selection.baseOffset,
        key: key,
        isRtl: isRtl,
      );
      if (bookmarkTarget != null) {
        _recordNativeArrowTrace(
          event,
          mode:
              'focus leading-bookmark trap -> ${bookmarkTarget.block}:${bookmarkTarget.offset}',
        );
        if (bookmarkTarget.block == blockIndex) {
          controller.selection = TextSelection.collapsed(
            offset: bookmarkTarget.offset,
          );
          _suppressActiveArrowEventOnce();
        } else {
          _crossToBlock(bookmarkTarget.block, atOffset: bookmarkTarget.offset);
        }
        return KeyEventResult.handled;
      }
    }

    if (!isRtl) {
      if (keyboard.isAltPressed &&
          !keyboard.isShiftPressed &&
          !keyboard.isMetaPressed) {
        final target = _isControlArrowModifierState(
          keyboard,
          allowShift: false,
        )
            ? _controlHorizontalWordTarget(
                blockIndex: blockIndex,
                rawOffset: selection.baseOffset,
                key: key,
              )
            : _horizontalTargetFromPosition(
                blockIndex: blockIndex,
                rawOffset: selection.baseOffset,
                key: key,
                allowInBlockStep: true,
              );
        if (target == null) {
          _recordNativeArrowTrace(
            event,
            mode: 'focus LTR alt normalized no-op',
          );
          return KeyEventResult.handled;
        }
        _recordNativeArrowTrace(
          event,
          mode: 'focus LTR alt normalized -> ${target.block}:${target.offset}',
        );
        if (target.block != blockIndex) {
          _crossToBlock(target.block, atOffset: target.offset);
          return KeyEventResult.handled;
        }
        controller.selection = TextSelection.collapsed(offset: target.offset);
        _lastFocusedController = controller;
        _focusNodes[blockIndex].requestFocus();
        return KeyEventResult.handled;
      }
      if (!plainArrow) {
        if (_isControlArrowModifierState(keyboard, allowShift: false)) {
          final target = _controlHorizontalWordTarget(
            blockIndex: blockIndex,
            rawOffset: selection.baseOffset,
            key: key,
          );
          _recordNativeArrowTrace(
            event,
            mode: target == null
                ? 'ctrlWordMove no-op'
                : 'ctrlWordMove -> ${target.block}:${target.offset}',
          );
          if (target == null) return KeyEventResult.handled;
          if (target.block != blockIndex) {
            _crossToBlock(target.block, atOffset: target.offset);
          } else {
            controller.selection = TextSelection.collapsed(
              offset: target.offset,
            );
            _lastFocusedController = controller;
            _focusNodes[blockIndex].requestFocus();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      final hiddenPrefixStep = _ltrHiddenPrefixVisibleStep(
        text: controller.text,
        rawOffset: selection.baseOffset,
        key: key,
      );
      if (hiddenPrefixStep != null) {
        _recordNativeArrowTrace(
          event,
          mode: 'focus LTR hidden-prefix visible step -> $hiddenPrefixStep',
        );
        controller.selection = TextSelection.collapsed(
          offset: hiddenPrefixStep,
        );
        _lastFocusedController = controller;
        _focusNodes[blockIndex].requestFocus();
        _suppressActiveArrowEventOnce();
        return KeyEventResult.handled;
      }
      final boundaryTarget = _horizontalBoundaryTargetFromPosition(
        blockIndex: blockIndex,
        rawOffset: selection.baseOffset,
        key: key,
      );
      if (boundaryTarget == null) return KeyEventResult.ignored;
      _crossToBlock(boundaryTarget.block, atOffset: boundaryTarget.offset);
      return KeyEventResult.handled;
    }

    final isControlWordMove = _isControlArrowModifierState(keyboard);
    final target = isControlWordMove
        ? _controlHorizontalWordTarget(
            blockIndex: blockIndex,
            rawOffset: selection.baseOffset,
            key: key,
          )
        : _horizontalTargetFromPosition(
            blockIndex: blockIndex,
            rawOffset: selection.baseOffset,
            key: key,
            allowInBlockStep: manualInBlock,
          );
    if (target == null) {
      if (isControlWordMove) {
        _recordNativeArrowTrace(event, mode: 'ctrlWordMove no-op');
      }
      return isRtl ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (isControlWordMove) {
      _recordNativeArrowTrace(
        event,
        mode: 'ctrlWordMove -> ${target.block}:${target.offset}',
      );
    }
    if (target.block != blockIndex) {
      _crossToBlock(target.block, atOffset: target.offset);
      return KeyEventResult.handled;
    }
    controller.selection = TextSelection.collapsed(offset: target.offset);
    return KeyEventResult.handled;
  }

  ({int block, int offset})? _leadingHiddenPrefixPlainHorizontalTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
    required bool isRtl,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    if (text.isEmpty) return null;

    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    final firstVisibleRaw = _firstKeyboardVisibleRawOffset(text);
    if (firstVisibleRaw <= 0 || safeRaw >= firstVisibleRaw) return null;

    final enterKey =
        isRtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;
    if (key == enterKey) {
      final afterVisibleBookmark = _rawOffsetAfterLeadingVisibleBookmark(text);
      if (afterVisibleBookmark != null) {
        if (safeRaw < afterVisibleBookmark) {
          final targetRaw = firstVisibleRaw > afterVisibleBookmark
              ? firstVisibleRaw
              : afterVisibleBookmark;
          return (block: blockIndex, offset: targetRaw);
        }
        if (safeRaw < firstVisibleRaw) {
          return (block: blockIndex, offset: firstVisibleRaw);
        }
        if (_visibleTextAfterLeadingBookmarkClusterIsEmpty(text)) {
          if (blockIndex >= _controllers.length - 1) {
            return (block: blockIndex, offset: afterVisibleBookmark);
          }
          return (block: blockIndex + 1, offset: 0);
        }
      }
      final targetRaw = firstVisibleRaw;
      if (targetRaw >= text.length) {
        if (blockIndex >= _controllers.length - 1) return null;
        return (block: blockIndex + 1, offset: 0);
      }
      return (block: blockIndex, offset: targetRaw);
    }

    final exitKey =
        isRtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;
    if (key == exitKey && safeRaw <= 0 && blockIndex > 0) {
      return (
        block: blockIndex - 1,
        offset: MarkupController.safeEndOffset(
          _controllers[blockIndex - 1].text,
        ),
      );
    }
    return null;
  }

  int? _rawOffsetAfterLeadingVisibleBookmark(String text) {
    final visible = EditorTextGeometryService.visibleText(text);
    if (visible.isEmpty || visible[0] != _keyboardBookmarkSign) return null;
    return MarkupController.visualToRawOffset(
      text,
      1,
    ).clamp(0, text.length).toInt();
  }

  int _firstKeyboardVisibleRawOffset(String text) {
    var offset = 0;
    final firstMarkupVisible = MarkupController.visualToRawOffset(
      text,
      0,
    ).clamp(0, text.length).toInt();
    if (firstMarkupVisible > offset) offset = firstMarkupVisible;

    final afterBookmarkCluster = _firstRawOffsetAfterLeadingBookmarkCluster(
      text,
    );
    if (afterBookmarkCluster > offset) offset = afterBookmarkCluster;
    return offset;
  }

  int _blockEntryStartRawOffset(String text) {
    if (text.isEmpty) return 0;
    final visible = EditorTextGeometryService.visibleText(text);
    if (visible.isEmpty) return 0;
    return MarkupController.visualToRawOffset(
      text,
      0,
    ).clamp(0, text.length).toInt();
  }

  int? _ltrHiddenPrefixVisibleStep({
    required String text,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (key != LogicalKeyboardKey.arrowRight || text.isEmpty) return null;
    final visible = EditorTextGeometryService.visibleText(text);
    if (visible.isEmpty) return null;
    final firstVisibleRaw = MarkupController.visualToRawOffset(
      text,
      0,
    ).clamp(0, text.length).toInt();
    if (firstVisibleRaw <= 0) return null;
    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    if (safeRaw < firstVisibleRaw) return firstVisibleRaw;
    final visibleOffset = MarkupController.rawToVisualOffset(
      text,
      safeRaw,
    ).clamp(0, visible.length).toInt();
    if (safeRaw == firstVisibleRaw && visibleOffset == 0) {
      return MarkupController.visualToRawOffset(
        text,
        1,
      ).clamp(0, text.length).toInt();
    }
    return null;
  }

  ({int block, int offset})? _leadingBookmarkPlainHorizontalTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
    required bool isRtl,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    final afterVisibleBookmark = _rawOffsetAfterLeadingVisibleBookmark(text);
    if (afterVisibleBookmark == null) return null;
    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    final afterLeadingBookmarks = _firstRawOffsetAfterLeadingBookmarkCluster(
      text,
    );
    final enterKey =
        isRtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;
    final exitKey =
        isRtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;

    if (key == enterKey) {
      if (safeRaw < afterVisibleBookmark) {
        final targetRaw = afterLeadingBookmarks > afterVisibleBookmark
            ? afterLeadingBookmarks
            : afterVisibleBookmark;
        return (block: blockIndex, offset: targetRaw);
      }
      if (_visibleTextAfterLeadingBookmarkClusterIsEmpty(text)) {
        if (blockIndex < _controllers.length - 1) {
          return (block: blockIndex + 1, offset: 0);
        }
        return (block: blockIndex, offset: afterVisibleBookmark);
      }
      if (afterLeadingBookmarks >= text.length &&
          safeRaw >= afterLeadingBookmarks &&
          blockIndex < _controllers.length - 1) {
        return (block: blockIndex + 1, offset: 0);
      }
      if (safeRaw >= afterLeadingBookmarks) return null;
      if (afterLeadingBookmarks >= text.length &&
          blockIndex < _controllers.length - 1) {
        return (block: blockIndex + 1, offset: 0);
      }
      return (block: blockIndex, offset: afterLeadingBookmarks);
    }
    if (key == exitKey &&
        safeRaw > afterVisibleBookmark &&
        safeRaw <= afterLeadingBookmarks) {
      return (block: blockIndex, offset: afterVisibleBookmark);
    }
    if (key == exitKey && safeRaw > 0 && safeRaw <= afterVisibleBookmark) {
      return (block: blockIndex, offset: 0);
    }
    return null;
  }

  bool _visibleTextAfterLeadingBookmarkClusterIsEmpty(String text) {
    final visible = EditorTextGeometryService.visibleText(text);
    if (visible.isEmpty || visible[0] != _keyboardBookmarkSign) return false;
    var index = 0;
    while (index < visible.length && visible[index] == _keyboardBookmarkSign) {
      index++;
    }
    return visible.substring(index).trim().isEmpty;
  }

  int _firstRawOffsetAfterLeadingBookmarkCluster(String text) {
    var offset = 0;
    var moved = true;
    var sawBookmark = false;
    while (moved && offset < text.length) {
      moved = false;
      while (offset < text.length && text[offset] == _keyboardBookmarkSign) {
        offset++;
        moved = true;
        sawBookmark = true;
      }
      if (sawBookmark) {
        while (offset < text.length &&
            (text.codeUnitAt(offset) == 0x0A ||
                text.codeUnitAt(offset) == 0x0D)) {
          offset++;
          moved = true;
        }
      }
      final tagMatch = MarkupDecorationParser.tagRegex.matchAsPrefix(
        text,
        offset,
      );
      if (tagMatch != null && tagMatch.start == offset) {
        offset = tagMatch.end;
        moved = true;
      }
    }
    return offset;
  }
}
