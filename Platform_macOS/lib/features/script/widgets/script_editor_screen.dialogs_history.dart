part of 'script_editor_screen.dart';

extension _ScriptEditorDialogsHistoryParts on _ScriptEditorScreenState {
  void _showRenameDialog() {
    final controller = TextEditingController(text: _currentTitle);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text('Rename Production',
                  style: TextStyle(color: Colors.white)),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      final newName = controller.text.trim();
                      if (newName.isNotEmpty) {
                        _setEditorState(() => _currentTitle = newName);
                        _forceRecentUpdate();
                        Navigator.pop(ctx);
                      }
                    },
                    child: const Text('Rename',
                        style: TextStyle(color: Color(0xFFFFBF00)))),
              ],
            ));
  }

  String _getRefinedFullText() => _controllers.map((c) => c.text).join('\n');

  EditorState _buildHistoryState(String description) {
    final settings = ref.read(settingsProvider);
    final focusIndex = _focusedBlockIndexForHistory();
    final focusSelection =
        focusIndex == null ? null : _controllers[focusIndex].selection;
    final appSelection = _appSelectionForHistory();
    return EditorState(
      text: _getRefinedFullText(),
      timestamp: DateTime.now(),
      description: description,
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      lineSpacing: settings.lineSpacing,
      letterSpacing: settings.letterSpacing,
      wordSpacing: settings.wordSpacing,
      scriptBgColor: settings.scriptBgColor,
      currentWordColor: settings.currentWordColor,
      futureWordColor: settings.futureWordColor,
      textAlign: settings.textAlign,
      focusBlockIndex: focusIndex,
      selectionBaseOffset: focusSelection?.baseOffset,
      selectionExtentOffset: focusSelection?.extentOffset,
      appSelectionActive: appSelection.active,
      appSelectionStartBlock: appSelection.startBlock,
      appSelectionStartOffset: appSelection.startOffset,
      appSelectionEndBlock: appSelection.endBlock,
      appSelectionEndOffset: appSelection.endOffset,
      scrollOffset: _editorScrollController.hasClients
          ? _editorScrollController.offset
          : null,
    );
  }

  bool _historyContentEquals(EditorState a, EditorState b) {
    return a.text == b.text &&
        a.fontSize == b.fontSize &&
        a.fontFamily == b.fontFamily &&
        a.lineSpacing == b.lineSpacing &&
        a.letterSpacing == b.letterSpacing &&
        a.wordSpacing == b.wordSpacing &&
        a.scriptBgColor == b.scriptBgColor &&
        a.currentWordColor == b.currentWordColor &&
        a.futureWordColor == b.futureWordColor &&
        a.textAlign == b.textAlign;
  }

  bool _historyVisibleStyleEquals(EditorState a, EditorState b) {
    return a.fontSize == b.fontSize &&
        a.fontFamily == b.fontFamily &&
        a.lineSpacing == b.lineSpacing &&
        a.letterSpacing == b.letterSpacing &&
        a.wordSpacing == b.wordSpacing &&
        a.scriptBgColor == b.scriptBgColor &&
        a.currentWordColor == b.currentWordColor &&
        a.futureWordColor == b.futureWordColor &&
        a.textAlign == b.textAlign &&
        StylingService.semanticStyleSignature(a.text) ==
            StylingService.semanticStyleSignature(b.text);
  }

  /// Commit a history snapshot immediately (no debounce).
  void _commitHistory(String description) {
    if (_isCleaning) return;
    _historyTimer?.cancel();
    _typingBulkTimer?.cancel();
    _suiteAutoSaveTimer?.cancel();
    _typingCharCount = 0;

    final state = _buildHistoryState(description);
    // Skip duplicate: don't commit if text + settings match the current head
    if (_historyIndex >= 0 && _historyIndex < _history.length) {
      final head = _history[_historyIndex];
      if (_historyContentEquals(head, state)) {
        return; // No change — skip
      }
    }

    _setEditorState(() {
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(state);
      if (_history.length > _ScriptEditorScreenState._maxHistory) {
        _history.removeAt(0);
      }
      _historyIndex = _history.length - 1;
    });
    _scheduleRecentUpdate();
  }

  void _beginSuiteHistoryTransaction(EditorSuite suite) {
    if (suite == EditorSuite.none) return;
    _suiteAutoSaveTimer?.cancel();
    _suiteTransactionSuite = suite;
    _suiteBaselineState = _historyIndex >= 0 && _historyIndex < _history.length
        ? _history[_historyIndex]
        : _buildHistoryState('${suite.name} Baseline');
    _suiteLiveHistoryIndex = null;
    _suiteSection = null;
    _isSuiteDirty = false;
  }

  void _endSuiteHistoryTransaction() {
    _suiteAutoSaveTimer?.cancel();
    _suiteTransactionSuite = null;
    _suiteBaselineState = null;
    _suiteLiveHistoryIndex = null;
    _suiteSection = null;
    _isSuiteDirty = false;
  }

  void _removeSuiteLiveHistoryEntry() {
    final index = _suiteLiveHistoryIndex;
    if (index == null || index < 0 || index >= _history.length) {
      _suiteLiveHistoryIndex = null;
      _isSuiteDirty = false;
      return;
    }
    _setEditorState(() {
      _history.removeAt(index);
      if (_history.isEmpty) {
        _historyIndex = -1;
      } else if (_historyIndex > index) {
        _historyIndex--;
      } else {
        _historyIndex = (index - 1).clamp(0, _history.length - 1).toInt();
      }
    });
    _suiteLiveHistoryIndex = null;
    _isSuiteDirty = false;
    _scheduleRecentUpdate();
  }

  void _recordSuiteHistoryChange(String description) {
    if (_activeSuite == EditorSuite.none) {
      _commitHistory(description);
      return;
    }
    if (_suiteBaselineState == null || _suiteTransactionSuite != _activeSuite) {
      _beginSuiteHistoryTransaction(_activeSuite);
    }
    final baseline = _suiteBaselineState;
    if (baseline == null) return;

    _suiteSection = description;
    final state = _buildHistoryState(description);
    if (_historyContentEquals(state, baseline) ||
        _historyVisibleStyleEquals(state, baseline)) {
      _removeSuiteLiveHistoryEntry();
      return;
    }

    _setEditorState(() {
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
        _suiteLiveHistoryIndex = null;
      }
      final liveIndex = _suiteLiveHistoryIndex;
      if (liveIndex != null && liveIndex >= 0 && liveIndex < _history.length) {
        _history[liveIndex] = state;
        _historyIndex = liveIndex;
      } else {
        _history.add(state);
        if (_history.length > _ScriptEditorScreenState._maxHistory) {
          _history.removeAt(0);
        }
        _suiteLiveHistoryIndex = _history.length - 1;
        _historyIndex = _suiteLiveHistoryIndex!;
      }
    });
    _isSuiteDirty = true;
    _scheduleRecentUpdate();
  }

  int? _focusedBlockIndexForHistory() {
    final active = _lastFocusedController ?? _activeController;
    if (active == null) return _controllers.isEmpty ? null : 0;
    final index = _controllers.indexOf(active);
    if (index >= 0) return index;
    return _controllers.isEmpty ? null : 0;
  }

  ({
    bool active,
    int? startBlock,
    int? startOffset,
    int? endBlock,
    int? endOffset,
  }) _appSelectionForHistory() {
    final selected = <({int block, int start, int end})>[];
    for (var i = 0; i < _controllers.length; i++) {
      final controller = _controllers[i];
      final external = controller.externalSelection;
      if (controller.isGlobalSelected) {
        selected.add((block: i, start: 0, end: controller.text.length));
      } else if (external != null &&
          external.isValid &&
          !external.isCollapsed) {
        selected.add((
          block: i,
          start: external.start.clamp(0, controller.text.length).toInt(),
          end: external.end.clamp(0, controller.text.length).toInt(),
        ));
      }
    }
    if (selected.isEmpty) {
      return (
        active: false,
        startBlock: null,
        startOffset: null,
        endBlock: null,
        endOffset: null,
      );
    }
    selected.sort((a, b) => a.block.compareTo(b.block));
    final first = selected.first;
    final last = selected.last;
    return (
      active: true,
      startBlock: first.block,
      startOffset: first.start,
      endBlock: last.block,
      endOffset: last.end,
    );
  }

  void _flushPendingTypingHistoryForTraversal() {
    if (_isCleaning) return;
    final hasPendingTyping =
        _typingCharCount > 0 || (_typingBulkTimer?.isActive ?? false);
    if (!hasPendingTyping) return;
    _commitHistory('Edit Text');
  }

  void _flushPendingHistoryForTraversal() {
    _flushPendingTypingHistoryForTraversal();
    if (_isCleaning) return;
    if (_activeSuite == EditorSuite.none || !_isSuiteDirty) return;
    _recordSuiteHistoryChange(_suiteSection ?? '${_activeSuite.name} Session');
  }

  bool _hasPendingHistoryContentChange() {
    if (_isCleaning) return false;
    if (_historyIndex < 0 || _historyIndex >= _history.length) {
      return _controllers.any((controller) => controller.text.isNotEmpty);
    }
    final state = _buildHistoryState('Pending');
    return !_historyContentEquals(state, _history[_historyIndex]);
  }

  /// Legacy-compatible entry point used by style commands and explicit saves.
  void _saveHistory({String description = 'Edit Text', bool debounce = false}) {
    if (_isCleaning) return;
    if (debounce) {
      // Typing bulk: accumulate chars, commit after 10 chars or 10 seconds
      _onTypingBulk(description);
      return;
    }
    _commitHistory(description);
  }

  /// Track which control inside the open suite produced the live history entry.
  void _trackSuiteSection(String section) {
    if (_activeSuite == EditorSuite.none) return;
    if (_suiteBaselineState == null || _suiteTransactionSuite != _activeSuite) {
      _beginSuiteHistoryTransaction(_activeSuite);
    }
    _suiteSection = section;
  }

  /// 10-char / 10-second typing bulking.
  void _onTypingBulk(String description) {
    _typingCharCount++;
    if (_typingCharCount >= 10) {
      // Threshold reached — commit now
      _commitHistory(description);
      return;
    }
    // Start or reset the 10-second window timer
    _typingBulkTimer?.cancel();
    _typingBulkTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _typingCharCount > 0) {
        _commitHistory(description);
      }
    });
  }

  void _undo() {
    final noUndoAvailable = _historyIndex <= 0;
    final redoAvailable =
        _historyIndex >= 0 && _historyIndex < _history.length - 1;
    if (noUndoAvailable &&
        redoAvailable &&
        !_hasPendingHistoryContentChange()) {
      return;
    }
    _flushPendingHistoryForTraversal();
    if (_historyIndex > 0) {
      _isCommandExecuting = true;
      _isDirty = false;
      final sourceState = _history[_historyIndex];
      final targetState = _history[_historyIndex - 1];
      _setEditorState(() {
        _historyIndex--;
        _applyState(targetState);
      });
      unawaited(_syncBookmarksFromEditorSigns(notify: false, save: true));
      _restoreHistoryFocusAndScroll(
        targetState,
        previousState: sourceState,
        focusState: sourceState,
      );
      _forceRecentUpdate();
    }
  }

  void _redo() {
    _flushPendingHistoryForTraversal();
    if (_historyIndex < _history.length - 1) {
      _isCommandExecuting = true;
      _isDirty = false;
      final sourceState = _history[_historyIndex];
      final targetState = _history[_historyIndex + 1];
      _setEditorState(() {
        _historyIndex++;
        _applyState(targetState);
      });
      unawaited(_syncBookmarksFromEditorSigns(notify: false, save: true));
      _restoreHistoryFocusAndScroll(
        targetState,
        previousState: sourceState,
        focusState: targetState,
      );
      _forceRecentUpdate();
    }
  }

  void _jumpToHistory(int idx) {
    if (idx < 0 || idx >= _history.length || idx == _historyIndex) return;
    _isCommandExecuting = true;
    _isDirty = false;
    _setEditorState(() {
      _historyIndex = idx;
      _applyState(_history[idx]);
    });
    unawaited(_syncBookmarksFromEditorSigns(notify: false, save: true));
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _isCommandExecuting = false;
        _isDirty = false;
      }
    });
    _forceRecentUpdate();
  }

  /// Apply settings that modify providers — safe to call outside of build.
  void _applySettingsFromState(EditorState s) {
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setFontSize(s.fontSize);
    notifier.setFontFamily(s.fontFamily);
    notifier.setLineSpacing(s.lineSpacing);
    notifier.setLetterSpacing(s.letterSpacing);
    notifier.setWordSpacing(s.wordSpacing);
    notifier.setScriptBgColor(s.scriptBgColor);
    notifier.setCurrentWordColor(s.currentWordColor);
    notifier.setFutureWordColor(s.futureWordColor);
    notifier.setTextAlign(s.textAlign);
  }

  void _applySettingsFromScript(Script script) {
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setFontSize(script.fontSize);
    notifier.setFontFamily(script.fontFamily);
    notifier.setLineSpacing(script.lineSpacing);
    notifier.setLetterSpacing(script.letterSpacing);
    notifier.setWordSpacing(script.wordSpacing);
    notifier.setTextAlign(script.textAlign);
    notifier.setScriptBgColor(script.scriptBgColor);
    notifier.setCurrentWordColor(script.currentWordColor);
    notifier.setFutureWordColor(script.futureWordColor);
  }

  void _applyState(EditorState state) {
    _clearHistoryAppSelectionVisuals();
    _loadText(state.text);
    _applySettingsFromState(state);
  }

  void _clearHistoryAppSelectionVisuals() {
    _overlayKey.currentState?.clearSelection();
    _preservedSelection = null;
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    _isGlobalSelection = false;
    for (final c in _controllers) {
      c.externalSelection = null;
      c.externalVisibleSelection = null;
      c.isGlobalSelected = false;
      c.refresh();
    }
  }

  void _restoreHistoryFocusAndScroll(
    EditorState targetState, {
    EditorState? previousState,
    EditorState? focusState,
  }) {
    // Two-phase restore: focus immediately after controllers rebuild, then let
    // EditableText's internal makeVisible() settle before applying our scroll.
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted || _controllers.isEmpty) return;
      _isCommandExecuting = false;
      _isDirty = false;

      final fallbackBlock =
          _firstChangedBlockIndex(previousState?.text, targetState.text);
      final rawTarget = focusState?.focusBlockIndex ??
          targetState.focusBlockIndex ??
          fallbackBlock ??
          0;
      final targetIdx = rawTarget.clamp(0, _controllers.length - 1).toInt();
      final controller = _controllers[targetIdx];
      final base = (targetState.selectionBaseOffset ?? 0)
          .clamp(0, controller.text.length)
          .toInt();
      final extent = (targetState.appSelectionActive
              ? (targetState.selectionExtentOffset ??
                  targetState.selectionBaseOffset ??
                  base)
              : base)
          .clamp(0, controller.text.length)
          .toInt();

      _lastFocusedController = controller;
      _focusNodes[targetIdx].requestFocus();
      controller.selection = TextSelection(
        baseOffset: base,
        extentOffset: extent,
      );
      if (targetState.appSelectionActive &&
          targetState.appSelectionStartBlock != null &&
          targetState.appSelectionStartOffset != null &&
          targetState.appSelectionEndBlock != null &&
          targetState.appSelectionEndOffset != null) {
        _overlayKey.currentState?.setKeyboardSelection(
          anchorBlock: targetState.appSelectionStartBlock!,
          anchorOffset: targetState.appSelectionStartOffset!,
          focusBlock: targetState.appSelectionEndBlock!,
          focusOffset: targetState.appSelectionEndOffset!,
        );
      } else {
        _clearHistoryAppSelectionVisuals();
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!targetState.appSelectionActive) {
          _clearHistoryAppSelectionVisuals();
        }
        final restoreScrollOffset =
            focusState?.scrollOffset ?? targetState.scrollOffset;
        if (restoreScrollOffset != null && _editorScrollController.hasClients) {
          final max = _editorScrollController.position.maxScrollExtent;
          _editorScrollController.jumpTo(
            restoreScrollOffset.clamp(0.0, max).toDouble(),
          );
        }
        _scrollEditorBlockIntoView(targetIdx);
      });
    });
  }

  int? _firstChangedBlockIndex(String? previousText, String targetText) {
    if (previousText == null) return null;
    final previousBlocks = previousText.split('\n');
    final targetBlocks = targetText.split('\n');
    final maxLength = previousBlocks.length > targetBlocks.length
        ? previousBlocks.length
        : targetBlocks.length;
    for (var i = 0; i < maxLength; i++) {
      final previous = i < previousBlocks.length ? previousBlocks[i] : null;
      final target = i < targetBlocks.length ? targetBlocks[i] : null;
      if (previous != target) {
        return i.clamp(0, targetBlocks.length - 1).toInt();
      }
    }
    return null;
  }

  MarkupController? get _activeController {
    for (var i = 0; i < _focusNodes.length; i++) {
      if (_focusNodes[i].hasFocus) return _controllers[i];
    }
    return _lastFocusedController ??
        (_controllers.isNotEmpty ? _controllers.last : null);
  }

  void handleBgColorChange(int color) {
    ref.read(settingsProvider.notifier).setScriptBgColor(color);
    if (_activeSuite == EditorSuite.none) {
      _saveHistory(description: 'Change Background', debounce: true);
    } else {
      _recordSuiteHistoryChange('Background Color');
    }
    if (mounted) _setEditorState(() {});
  }

  Future<void> handleInvertColors() async {
    _restoreSelectionIfNeeded();
    final settings = ref.read(settingsProvider);
    if (_hasActiveTextSelection()) {
      _setEditorState(() => _isCommandExecuting = true);
      final inSuite = _activeSuite != EditorSuite.none;
      if (inSuite) _trackSuiteSection('Invert Colors');
      var changed = false;
      final wasGlobalSelection = _isGlobalSelection;
      final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
      final targets = <MarkupController>[];

      if (wasGlobalSelection) {
        _isGlobalSelection = false;
        for (final c in _controllers) {
          if (c.text.isEmpty) continue;
          c.externalSelection =
              TextSelection(baseOffset: 0, extentOffset: c.text.length);
          c.externalVisibleSelection = TextSelection(
            baseOffset: 0,
            extentOffset: MarkupDecorationParser.visibleText(c.text).length,
          );
          targets.add(c);
        }
      } else {
        targets.addAll(_styleTargets());
      }

      for (final c in targets) {
        if (c.text.isEmpty) continue;
        final selection = (c.externalSelection != null &&
                c.externalSelection!.isValid &&
                !c.externalSelection!.isCollapsed)
            ? c.externalSelection!
            : c.selection;
        if (!selection.isValid || selection.isCollapsed) continue;
        final nextValue = EditorInlineStyleOperation.applySelectionColorInvert(
          text: c.text,
          selection: selection,
          defaultTextColor: _rgbHex(settings.futureWordColor),
          scriptBackgroundColor: _rgbHex(settings.scriptBgColor),
        );
        if (nextValue.text == c.text) continue;
        c.value = nextValue;
        if (nextValue.selection.isValid && !nextValue.selection.isCollapsed) {
          c.externalSelection = nextValue.selection;
          c.externalVisibleSelection =
              MarkupDecorationParser.rawToVisibleSelection(
            c.text,
            nextValue.selection,
          );
        }
        c.refresh();
        changed = true;
      }

      if (wasGlobalSelection) {
        _isGlobalSelection = true;
        _resyncGlobalSelection();
      } else if (hasOverlay) {
        _overlayKey.currentState
            ?.syncOffsetsFromExternalSelection(_controllers);
      }

      if (changed) {
        if (inSuite) {
          _recordSuiteHistoryChange('Invert Colors');
        } else {
          _commitHistory('Invert Colors');
        }
      }
      _onSelectionChanged();
      _setEditorState(() => _isCommandExecuting = false);
      return;
    }

    final oldBackground = settings.scriptBgColor;
    final oldFutureText = settings.futureWordColor;
    final nextBackground = oldFutureText;
    final nextFutureText = oldBackground;
    var changedMarkup = false;
    _setEditorState(() => _isCommandExecuting = true);
    for (final c in _controllers) {
      if (c.text.isEmpty) continue;
      final nextValue =
          EditorInlineStyleOperation.applyWholeScriptHighlightColorInvert(
        text: c.text,
        defaultTextColor: _rgbHex(settings.futureWordColor),
        scriptBackgroundColor: _rgbHex(settings.scriptBgColor),
      );
      if (nextValue.text == c.text) continue;
      c.value = nextValue;
      c.refresh();
      changedMarkup = true;
    }
    final notifier = ref.read(settingsProvider.notifier);
    final scriptNotifier = ref.read(scriptProvider.notifier);
    await notifier.setScriptBgColor(nextBackground);
    await notifier.setFutureWordColor(nextFutureText);
    if (changedMarkup) {
      await notifier.setShowUpcomingWordColor(false);
    } else {
      await notifier.setShowUpcomingWordColor(true);
    }
    await scriptNotifier.updateStyleMetadata(
      scriptBgColor: nextBackground,
      futureWordColor: nextFutureText,
    );
    if (!mounted) return;
    if (_activeSuite == EditorSuite.none) {
      _commitHistory('Invert Colors');
    } else {
      _recordSuiteHistoryChange('Invert Colors');
    }
    _onSelectionChanged();
    _setEditorState(() => _isCommandExecuting = false);
    if (mounted) _setEditorState(() {});
  }

  String _rgbHex(int argb) =>
      (argb & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  /// Returns the list of controllers that should receive a style command,
  /// honoring an active overlay selection (refined or global) when present.
}
