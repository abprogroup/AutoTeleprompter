part of 'script_editor_screen.dart';

extension _ScriptEditorKeyboardSelectionParts on _ScriptEditorScreenState {
  ({int block, int offset})? _appSelectionEdge({required bool collapseToEnd}) {
    ({int block, int offset})? first;
    ({int block, int offset})? last;
    for (var i = 0; i < _controllers.length; i++) {
      final c = _controllers[i];
      final sel = c.externalSelection;
      final fullBlock = c.isGlobalSelected;
      final hasRange =
          fullBlock || (sel != null && sel.isValid && !sel.isCollapsed);
      if (!hasRange) continue;
      final start = fullBlock ? 0 : sel!.start.clamp(0, c.text.length).toInt();
      final end =
          fullBlock ? c.text.length : sel!.end.clamp(0, c.text.length).toInt();
      final low = start < end ? start : end;
      final high = start > end ? start : end;
      first ??= (block: i, offset: low);
      last = (block: i, offset: high);
    }
    if (first == null || last == null) {
      final active = _activeController;
      if (active == null) return null;
      final idx = _controllers.indexOf(active);
      if (idx < 0) return null;
      final sel = active.selection;
      final offset = collapseToEnd
          ? sel.end.clamp(0, active.text.length).toInt()
          : sel.start.clamp(0, active.text.length).toInt();
      return (block: idx, offset: offset);
    }
    return collapseToEnd ? last : first;
  }

  bool _extendAppSelectionForArrow(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard, {
    String? eventSignature,
  }) {
    final actionLabel = _shiftSelectionActionLabel(key, keyboard);
    final targetMode = _shiftSelectionTargetMode(key, keyboard);
    if (eventSignature != null &&
        _shiftSelectionEventWasHandled(eventSignature)) {
      _lastArrowDecision = '$actionLabel duplicate suppressed ${key.keyLabel}';
      return true;
    }
    if (eventSignature != null) {
      _markShiftSelectionEventHandled(eventSignature);
    }
    if (!(_overlayKey.currentState?.hasSelection ?? false)) {
      _promoteNativeSelectionToOverlay();
    }
    final seed = _shiftSelectionSeed();
    if (seed == null) {
      _lastArrowDecision = '$actionLabel ${key.keyLabel}: no focused caret';
      _recordSelectionTrace(
        '$actionLabel ${key.keyLabel}: no focused caret',
        key: key,
        seedSource: 'none',
        targetMode: targetMode,
      );
      return true;
    }
    final anchor = seed.anchor;
    final focus = seed.focus;
    final seedSource = seed.seedSource;
    final staleOverlayRejected = seed.staleOverlayRejected;
    final target = _shiftArrowTarget(
      key: key,
      keyboard: keyboard,
      anchor: anchor,
      focus: focus,
    );
    if (target == null) {
      _lastArrowDecision =
          '$actionLabel ${key.keyLabel}: boundary ${focus.block}:${focus.offset}';
      _recordSelectionTrace(
        '$actionLabel ${key.keyLabel}: boundary',
        key: key,
        anchor: anchor,
        focus: focus,
        seedSource: seedSource,
        targetMode: targetMode,
        staleOverlayRejected: staleOverlayRejected,
      );
      return true;
    }
    if (target.block == focus.block && target.offset == focus.offset) {
      _lastArrowDecision =
          '$actionLabel ${key.keyLabel}: unchanged ${focus.block}:${focus.offset}';
      _recordSelectionTrace(
        '$actionLabel ${key.keyLabel}: unchanged',
        key: key,
        anchor: anchor,
        focus: focus,
        seedSource: seedSource,
        targetMode: targetMode,
        staleOverlayRejected: staleOverlayRejected,
      );
      return true;
    }
    final adjusted = SelectionEndpoint(
      block: target.block,
      offset: target.offset,
    );
    final crossesAnchor = _targetCrossesAnchor(
      anchor: anchor,
      focus: focus,
      target: adjusted,
    );
    if (_sameEndpoint(anchor, adjusted)) {
      _setCollapsedShiftSeed(anchor);
      _recordSelectionTrace(
        '$actionLabel ${key.keyLabel}: collapsed shift seed',
        key: key,
        anchor: anchor,
        focus: adjusted,
        seedSource: seedSource,
        targetMode: targetMode,
        anchorCrossing: crossesAnchor,
        collapsedShiftSeed: true,
        staleOverlayRejected: staleOverlayRejected,
      );
      return true;
    }
    _setAppSelectionFromAnchorToFocus(anchor, adjusted);
    _lastArrowDecision =
        '$actionLabel ${key.keyLabel}: ${anchor.block}:${anchor.offset}-${adjusted.block}:${adjusted.offset}';
    _recordSelectionTrace(
      '$actionLabel ${key.keyLabel}: extended',
      key: key,
      anchor: anchor,
      focus: adjusted,
      seedSource: seedSource,
      targetMode: targetMode,
      anchorCrossing: crossesAnchor,
      staleOverlayRejected: staleOverlayRejected,
    );
    return true;
  }

  String _shiftSelectionActionLabel(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard,
  ) {
    if (!keyboard.isControlPressed) return 'shift';
    final vertical = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    return vertical ? 'ctrlShiftVerticalExtend' : 'ctrlShiftWordExtend';
  }

  String _shiftSelectionTargetMode(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard,
  ) {
    final vertical = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    if (keyboard.isControlPressed) {
      return vertical ? 'ctrlVertical' : 'ctrlWord';
    }
    return vertical ? 'shiftVisualLine' : 'shiftVisualStep';
  }

  ({
    SelectionEndpoint anchor,
    SelectionEndpoint focus,
    String seedSource,
    bool staleOverlayRejected,
  })? _shiftSelectionSeed() {
    final controller = _lastFocusedController ?? _activeController;
    final overlayHasSelection = _overlayKey.currentState?.hasSelection ?? false;
    final visibleOverlayRange = _hasVisibleAppSelectionRange();
    final session = _overlayKey.currentState?.selectionSessionSnapshot;

    if (controller == null) {
      if (overlayHasSelection && session != null) {
        _shiftSelectionAnchor = session.anchor;
        _shiftSelectionFocus = session.focus;
        return (
          anchor: session.anchor,
          focus: session.focus,
          seedSource: 'overlay-no-native-focus',
          staleOverlayRejected: false,
        );
      }
      return null;
    }

    final block = _controllers.indexOf(controller);
    if (block < 0) return null;
    final selection = controller.selection.isValid
        ? controller.selection
        : const TextSelection.collapsed(offset: 0);
    final realAnchor = SelectionEndpoint(
      block: block,
      offset: selection.baseOffset.clamp(0, controller.text.length).toInt(),
    );
    final realFocus = SelectionEndpoint(
      block: block,
      offset: selection.extentOffset.clamp(0, controller.text.length).toInt(),
    );

    if (session != null &&
        overlayHasSelection &&
        _overlaySessionOwnsShiftContinuation(session)) {
      _shiftSelectionAnchor = session.anchor;
      _shiftSelectionFocus = session.focus;
      return (
        anchor: session.anchor,
        focus: session.focus,
        seedSource: 'overlay-app-session',
        staleOverlayRejected: false,
      );
    }

    if (session != null &&
        overlayHasSelection &&
        _nativeSelectionContinuesOverlaySession(
          session: session,
          nativeAnchor: realAnchor,
          nativeFocus: realFocus,
          isNativeCollapsed: selection.isCollapsed,
        )) {
      _shiftSelectionAnchor = session.anchor;
      _shiftSelectionFocus = session.focus;
      return (
        anchor: session.anchor,
        focus: session.focus,
        seedSource: 'overlay',
        staleOverlayRejected: false,
      );
    }
    if (session != null && overlayHasSelection && !selection.isCollapsed) {
      _shiftSelectionAnchor = session.anchor;
      _shiftSelectionFocus = session.focus;
      return (
        anchor: session.anchor,
        focus: session.focus,
        seedSource: 'overlay-over-native-range',
        staleOverlayRejected: false,
      );
    }

    final rememberedAnchor = _shiftSelectionAnchor;
    final rememberedFocus = _shiftSelectionFocus;
    if (rememberedAnchor != null &&
        rememberedFocus != null &&
        _sameEndpoint(rememberedFocus, realFocus)) {
      return (
        anchor: rememberedAnchor,
        focus: rememberedFocus,
        seedSource: visibleOverlayRange
            ? 'remembered-overlay'
            : 'remembered-collapsed-shift',
        staleOverlayRejected: false,
      );
    }

    var staleOverlayRejected = false;
    if (overlayHasSelection || visibleOverlayRange || _isGlobalSelection) {
      staleOverlayRejected = true;
      _clearSelectionForNativeShiftSeed(
        reason: 'staleOverlayRejected before shift seed',
      );
    }
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    return (
      anchor: realAnchor,
      focus: realFocus,
      seedSource: selection.isCollapsed ? 'native-caret' : 'native-range',
      staleOverlayRejected: staleOverlayRejected,
    );
  }

  bool _overlaySessionOwnsShiftContinuation(
    SelectionSessionSnapshot session,
  ) {
    return session.mode == SelectionSessionMode.overlaySelection ||
        session.mode == SelectionSessionMode.handleDrag;
  }

  bool _nativeSelectionContinuesOverlaySession({
    required SelectionSessionSnapshot session,
    required SelectionEndpoint nativeAnchor,
    required SelectionEndpoint nativeFocus,
    required bool isNativeCollapsed,
  }) {
    if (isNativeCollapsed) {
      return _sameEndpoint(nativeFocus, session.focus);
    }
    if (_sameEndpoint(nativeAnchor, session.anchor) &&
        _sameEndpoint(nativeFocus, session.focus)) {
      return true;
    }
    return _sameEndpoint(nativeAnchor, session.focus) &&
        _sameEndpoint(nativeFocus, session.anchor);
  }

  void _clearSelectionForNativeShiftSeed({required String reason}) {
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.externalVisibleSelection = null;
      c.refresh();
    }
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    // ignore: invalid_use_of_protected_member
    _setEditorState(() {
      _isGlobalSelection = false;
      _lastArrowDecision = reason;
    });
  }

  ({int block, int offset})? _shiftArrowTarget({
    required LogicalKeyboardKey key,
    required HardwareKeyboard keyboard,
    required SelectionEndpoint anchor,
    required SelectionEndpoint focus,
  }) {
    if (keyboard.isControlPressed) {
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        return _ctrlShiftVerticalTarget(
          anchor: anchor,
          focus: focus,
          moveUp: key == LogicalKeyboardKey.arrowUp,
        );
      }
      return _arrowTargetFromPosition(
        key: key,
        block: focus.block,
        offset: focus.offset,
        keyboard: keyboard,
        allowInBlockHorizontalStep: false,
        allowInBlockVerticalStep: true,
      );
    }
    if (_isShiftVerticalArrow(key, keyboard)) {
      return _plainShiftVerticalLineTarget(
        block: focus.block,
        offset: focus.offset,
        key: key,
      );
    }
    return _arrowTargetFromPosition(
      key: key,
      block: focus.block,
      offset: focus.offset,
      keyboard: keyboard,
      allowInBlockHorizontalStep: !keyboard.isControlPressed,
      allowInBlockVerticalStep: true,
    );
  }

  bool _isShiftVerticalArrow(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard,
  ) {
    return keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown);
  }

  ({int block, int offset})? _plainShiftVerticalLineTarget({
    required int block,
    required int offset,
    required LogicalKeyboardKey key,
    bool crossBlockOnly = false,
    double? preferredX,
  }) {
    if (block < 0 || block >= _controllers.length) return null;
    final moveUp = key == LogicalKeyboardKey.arrowUp;
    final renderedTarget = _renderEditableVerticalTarget(
      block: block,
      offset: offset,
      moveUp: moveUp,
      crossBlockOnly: crossBlockOnly,
      preferredX: preferredX,
    );
    if (renderedTarget != null) return renderedTarget;

    final controller = _controllers[block];
    final safeOffset = offset.clamp(0, controller.text.length).toInt();
    final layout = _getVerticalLayout(
      block,
      selection: TextSelection.collapsed(offset: safeOffset),
    );
    final targetX = preferredX ?? layout.currentX;
    final visibleText = StylingService.stripTags(controller.text);
    if (visibleText.trim().isEmpty) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: moveUp,
        preferredX: targetX,
      );
    }

    final plainText = layout.painter.text?.toPlainText() ?? '';
    if (plainText.isEmpty) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: moveUp,
        preferredX: targetX,
      );
    }

    final painterOffset = safeOffset.clamp(0, plainText.length).toInt();
    final line = layout.painter.getLineBoundary(
      TextPosition(offset: painterOffset),
    );
    if (moveUp && line.start <= 0) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: true,
        preferredX: targetX,
      );
    }
    if (!moveUp && line.end >= plainText.length) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: false,
        preferredX: targetX,
      );
    }
    if (crossBlockOnly) return null;

    final targetOffset = layout
        .visualVerticalTargetRawOffset(
          rawText: controller.text,
          rawOffset: safeOffset,
          moveUp: moveUp,
          preferredX: targetX,
        )
        ?.clamp(0, controller.text.length)
        .toInt();
    if (targetOffset == null) return null;
    if (targetOffset == safeOffset) return null;
    return (block: block, offset: targetOffset);
  }

  ({int block, int offset})? _plainShiftVerticalCrossBlockTarget({
    required int fromBlock,
    required bool moveUp,
    required double preferredX,
  }) {
    final targetBlock = fromBlock + (moveUp ? -1 : 1);
    if (targetBlock < 0 || targetBlock >= _controllers.length) return null;
    final targetController = _controllers[targetBlock];
    if (StylingService.stripTags(targetController.text).trim().isEmpty) {
      return (block: targetBlock, offset: 0);
    }
    final fallbackOffset =
        moveUp ? MarkupController.safeEndOffset(targetController.text) : 0;
    final layout = _getVerticalLayout(
      targetBlock,
      selection: TextSelection.collapsed(offset: fallbackOffset),
    );
    final offset = layout
        .getPositionAtX(
          preferredX,
          fromBottom: moveUp,
          rawText: targetController.text,
        )
        .clamp(0, targetController.text.length)
        .toInt();
    return (block: targetBlock, offset: offset);
  }

  ({int block, int offset})? _renderEditableVerticalTarget({
    required int block,
    required int offset,
    required bool moveUp,
    required bool crossBlockOnly,
    double? preferredX,
  }) {
    if (block < 0 || block >= _controllers.length) return null;
    final targetX =
        preferredX ?? _renderEditableCaretX(blockIndex: block, offset: offset);
    if (targetX == null) return null;

    final candidates = _renderEditableCaretCandidatesForBlock(block);
    if (candidates.isNotEmpty) {
      final lines = _groupRenderCaretCandidatesByLine(candidates);
      final currentLine = _renderEditableLineIndexForOffset(
        block: block,
        offset: offset,
        lines: lines,
      );
      if (currentLine != null) {
        final targetLine = currentLine + (moveUp ? -1 : 1);
        if (targetLine >= 0 && targetLine < lines.length) {
          if (crossBlockOnly) return null;
          final target = _nearestRenderCaretCandidate(
            lines[targetLine],
            targetX,
          );
          return target == null ? null : (block: block, offset: target.raw);
        }
      }
    }

    return _renderEditableCrossBlockVerticalTarget(
      fromBlock: block,
      moveUp: moveUp,
      preferredX: targetX,
    );
  }

  ({int block, int offset})? _renderEditableCrossBlockVerticalTarget({
    required int fromBlock,
    required bool moveUp,
    required double preferredX,
  }) {
    final targetBlock = fromBlock + (moveUp ? -1 : 1);
    if (targetBlock < 0 || targetBlock >= _controllers.length) return null;
    final targetText = _controllers[targetBlock].text;
    if (StylingService.stripTags(targetText).trim().isEmpty) {
      return (block: targetBlock, offset: 0);
    }
    final candidates = _renderEditableCaretCandidatesForBlock(targetBlock);
    if (candidates.isEmpty) return null;
    final lines = _groupRenderCaretCandidatesByLine(candidates);
    if (lines.isEmpty) return null;
    final targetLine = moveUp ? lines.length - 1 : 0;
    final target = _nearestRenderCaretCandidate(
      lines[targetLine],
      preferredX,
    );
    return target == null ? null : (block: targetBlock, offset: target.raw);
  }

  double? _renderEditableCaretX({
    required int blockIndex,
    required int offset,
  }) {
    final editable = _renderEditableForBlock(blockIndex);
    if (editable == null) return null;
    final textLength = _controllers[blockIndex].text.length;
    final safeOffset = offset.clamp(0, textLength).toInt();
    final endpoints = editable.getEndpointsForSelection(
      TextSelection.collapsed(offset: safeOffset),
    );
    if (endpoints.isEmpty) return null;
    return endpoints.first.point.dx;
  }

  RenderEditable? _renderEditableForBlock(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _blockKeys.length) return null;
    return _findRenderEditable(
      _blockKeys[blockIndex].currentContext?.findRenderObject(),
    );
  }

  List<_RenderCaretCandidate> _renderEditableCaretCandidatesForBlock(
    int blockIndex,
  ) {
    final editable = _renderEditableForBlock(blockIndex);
    if (editable == null) return const [];
    final rawText = _controllers[blockIndex].text;
    final visible = EditorTextGeometryService.visibleText(rawText);
    if (visible.isEmpty) return const [];
    final rawStops = <int>{};
    for (var visibleOffset = 0;
        visibleOffset <= visible.length;
        visibleOffset++) {
      rawStops.add(
        MarkupController.visualToRawOffset(rawText, visibleOffset)
            .clamp(0, rawText.length)
            .toInt(),
      );
    }

    final candidates = <_RenderCaretCandidate>[];
    for (final raw in rawStops) {
      for (final affinity in const [
        TextAffinity.downstream,
        TextAffinity.upstream,
      ]) {
        final endpoints = editable.getEndpointsForSelection(
          TextSelection.collapsed(offset: raw, affinity: affinity),
        );
        if (endpoints.isEmpty) continue;
        final point = endpoints.first.point;
        final duplicate = candidates.any((existing) =>
            existing.raw == raw &&
            (existing.x - point.dx).abs() <= 0.75 &&
            (existing.y - point.dy).abs() <= 0.75);
        if (duplicate) continue;
        candidates.add(_RenderCaretCandidate(
          raw: raw,
          x: point.dx,
          y: point.dy,
        ));
      }
    }
    candidates.sort((a, b) {
      final yCompare = a.y.compareTo(b.y);
      if (yCompare != 0) return yCompare;
      final xCompare = a.x.compareTo(b.x);
      if (xCompare != 0) return xCompare;
      return a.raw.compareTo(b.raw);
    });
    return candidates;
  }

  List<List<_RenderCaretCandidate>> _groupRenderCaretCandidatesByLine(
    List<_RenderCaretCandidate> candidates,
  ) {
    if (candidates.isEmpty) return const [];
    const tolerance = 3.0;
    final sorted = [...candidates]..sort((a, b) => a.y.compareTo(b.y));
    final lines = <List<_RenderCaretCandidate>>[];
    for (final candidate in sorted) {
      if (lines.isEmpty ||
          (lines.last.first.y - candidate.y).abs() > tolerance) {
        lines.add([candidate]);
      } else {
        lines.last.add(candidate);
      }
    }
    for (final line in lines) {
      line.sort((a, b) {
        final xCompare = a.x.compareTo(b.x);
        if (xCompare != 0) return xCompare;
        return a.raw.compareTo(b.raw);
      });
    }
    return lines;
  }

  int? _renderEditableLineIndexForOffset({
    required int block,
    required int offset,
    required List<List<_RenderCaretCandidate>> lines,
  }) {
    final editable = _renderEditableForBlock(block);
    if (editable == null || lines.isEmpty) return null;
    final safeOffset = offset.clamp(0, _controllers[block].text.length).toInt();
    final endpoints = editable.getEndpointsForSelection(
      TextSelection.collapsed(offset: safeOffset),
    );
    if (endpoints.isEmpty) return null;
    final y = endpoints.first.point.dy;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < lines.length; i++) {
      final distance = (lines[i].first.y - y).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  _RenderCaretCandidate? _nearestRenderCaretCandidate(
    List<_RenderCaretCandidate> line,
    double preferredX,
  ) {
    if (line.isEmpty) return null;
    _RenderCaretCandidate? best;
    var bestDistance = double.infinity;
    for (final candidate in line) {
      final distance = (candidate.x - preferredX).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }

  bool _sameEndpoint(SelectionEndpoint a, SelectionEndpoint b) =>
      a.block == b.block && a.offset == b.offset;

  int _compareEndpoints(SelectionEndpoint a, SelectionEndpoint b) {
    if (a.block != b.block) return a.block.compareTo(b.block);
    return a.offset.compareTo(b.offset);
  }

  bool _targetCrossesAnchor({
    required SelectionEndpoint anchor,
    required SelectionEndpoint focus,
    required SelectionEndpoint target,
  }) {
    final focusSide = _compareEndpoints(focus, anchor);
    final targetSide = _compareEndpoints(target, anchor);
    if (focusSide == 0 || targetSide == 0) return false;
    return (focusSide < 0 && targetSide > 0) ||
        (focusSide > 0 && targetSide < 0);
  }

  void _setAppSelectionFromAnchorToFocus(
    SelectionEndpoint anchor,
    SelectionEndpoint focus,
  ) {
    _shiftSelectionAnchor = anchor;
    _shiftSelectionFocus = focus;
    _lastFocusedController = _controllers[focus.block];
    _focusNodes[focus.block].requestFocus();
    _controllers[focus.block].selection = TextSelection.collapsed(
      offset: focus.offset,
    );
    _overlayKey.currentState?.setKeyboardSelection(
      anchorBlock: anchor.block,
      anchorOffset: anchor.offset,
      focusBlock: focus.block,
      focusOffset: focus.offset,
    );
    _scrollEditorBlockIntoView(focus.block);
  }

  void _setCollapsedShiftSeed(SelectionEndpoint target) {
    _shiftSelectionAnchor = target;
    _shiftSelectionFocus = target;
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.externalVisibleSelection = null;
      c.refresh();
    }
    _setEditorState(() {
      _isGlobalSelection = false;
      _lastArrowDecision = 'collapsed shift seed: $target';
    });
    _lastFocusedController = _controllers[target.block];
    _focusNodes[target.block].requestFocus();
    _controllers[target.block].selection = TextSelection.collapsed(
      offset: target.offset,
    );
    _scrollEditorBlockIntoView(target.block);
  }
}
