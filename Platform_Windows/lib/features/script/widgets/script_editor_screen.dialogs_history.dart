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

  /// Clear style at cursor: find the word at cursor, then strip all tags from
  /// just that word — surgically splitting any enclosing styled regions so the
  /// rest of the text keeps its styling.
  void _clearStyleAtCursor(MarkupController c, int cursor) {
    final text = c.text;
    final tagPattern = RegExp(
        r'\[\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*');

    // Step 1: Find the word boundaries at cursor (skipping over tag characters)
    // Walk left to find word start, walk right to find word end,
    // jumping over any tag sequences encountered.
    int wordStart = cursor;
    int wordEnd = cursor;

    // Walk left
    while (wordStart > 0) {
      final prev = wordStart - 1;
      // Check if we're at the end of a tag — skip over it
      bool skippedTag = false;
      for (final m in tagPattern.allMatches(text)) {
        if (m.end == wordStart) {
          wordStart = m.start;
          skippedTag = true;
          break;
        }
      }
      if (skippedTag) continue;
      // Check if previous char is a space/newline
      final ch = text[prev];
      if (ch == ' ' || ch == '\n' || ch == '\t') break;
      wordStart = prev;
    }

    // Walk right
    while (wordEnd < text.length) {
      // Check if we're at the start of a tag — skip over it
      bool skippedTag = false;
      for (final m in tagPattern.allMatches(text)) {
        if (m.start == wordEnd) {
          wordEnd = m.end;
          skippedTag = true;
          break;
        }
      }
      if (skippedTag) continue;
      final ch = text[wordEnd];
      if (ch == ' ' || ch == '\n' || ch == '\t') break;
      wordEnd++;
    }

    if (wordStart >= wordEnd) return;

    // Step 2: Strip tags inside the word range
    final before = text.substring(0, wordStart);
    final wordContent = text.substring(wordStart, wordEnd);
    final after = text.substring(wordEnd);
    final cleanWord = wordContent.replaceAll(tagPattern, '');

    // Step 3: Rebuild text with clean word
    String result = before + cleanWord + after;
    int newCursor = (cursor - (wordEnd - wordStart - cleanWord.length))
        .clamp(0, result.length);
    // Adjust cursor: it was relative to old text, account for removed tags before cursor
    final tagsBeforeCursor = tagPattern.allMatches(wordContent.substring(
        0, (cursor - wordStart).clamp(0, wordContent.length)));
    int removedBefore = 0;
    for (final m in tagsBeforeCursor) {
      removedBefore += m.end - m.start;
    }
    newCursor = (cursor - removedBefore).clamp(0, result.length);

    // Step 4: Split any enclosing tags that wrap over the word boundaries
    // so surrounding text keeps its style.
    final wordStartInResult = wordStart;
    final wordEndInResult = wordStart + cleanWord.length;
    result = _splitAllEnclosingStyles(
        result, wordStartInResult, wordEndInResult, tagPattern);

    // Reclamp cursor
    newCursor = newCursor.clamp(0, result.length);

    c.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  /// Split ALL enclosing style tag pairs around a range, so the range loses
  /// styling but surrounding text keeps it.
  String _splitAllEnclosingStyles(
      String text, int start, int end, RegExp tagPattern) {
    final families = <String, List<String>>{
      'bold': ['**', '**'],
      'underline': ['[u]', '[/u]'],
      'italic': ['[i]', '[/i]'],
    };
    final paramFamilies = ['color', 'bg', 'size', 'font', 'align'];

    String current = text;
    int curStart = start;
    int curEnd = end;

    for (final entry in families.entries) {
      final result = _splitEnclosingStyle(
          current, curStart, curEnd, entry.value[0], entry.value[1]);
      if (result != null) {
        current = result[0] as String;
        curStart = result[1] as int;
        curEnd = result[2] as int;
      }
    }
    for (final family in paramFamilies) {
      final openPattern = RegExp(r'\[' + family + r'=[^\]]+\]');
      final close = '[/$family]';
      for (final m in openPattern.allMatches(current)) {
        if (m.start <= curStart) {
          final closeIdx = current.indexOf(close, m.end);
          if (closeIdx != -1 && closeIdx >= curEnd) {
            final result = _splitEnclosingStyle(current, curStart, curEnd,
                current.substring(m.start, m.end), close);
            if (result != null) {
              current = result[0] as String;
              curStart = result[1] as int;
              curEnd = result[2] as int;
            }
            break;
          }
        }
      }
    }
    return current;
  }

  /// Find enclosing open/close pair around a midpoint. Returns [openStart, openEnd, closeStart, closeEnd] or null.
  List<int>? _findEnclosingPair(
      String text, int cursor, String open, String close) {
    if (open == '**' && close == '**') {
      final matches = RegExp(r'\*\*').allMatches(text).toList();
      for (int i = 0; i < matches.length - 1; i += 2) {
        final oStart = matches[i].start;
        final oEnd = matches[i].end;
        if (i + 1 < matches.length) {
          final cStart = matches[i + 1].start;
          final cEnd = matches[i + 1].end;
          if (oEnd <= cursor && cStart >= cursor) {
            return [oStart, oEnd, cStart, cEnd];
          }
        }
      }
      return null;
    }
    int searchFrom = cursor;
    while (searchFrom >= 0) {
      final idx = text.lastIndexOf(open, searchFrom);
      if (idx == -1) return null;
      final closeIdx = text.indexOf(close, idx + open.length);
      if (closeIdx != -1 && closeIdx >= cursor) {
        return [idx, idx + open.length, closeIdx, closeIdx + close.length];
      }
      searchFrom = idx - 1;
    }
    return null;
  }

  /// Split an enclosing style around a range: keep style on before/after, remove from range.
  List<Object>? _splitEnclosingStyle(
      String text, int selStart, int selEnd, String open, String close) {
    final pair =
        _findEnclosingPair(text, (selStart + selEnd) ~/ 2, open, close);
    if (pair == null) return null;
    final oStart = pair[0], oEnd = pair[1], cStart = pair[2], cEnd = pair[3];

    // Don't split if range covers the full styled content
    if (selStart <= oEnd && selEnd >= cStart) return null;

    final before = text.substring(oEnd, selStart);
    final selected = text.substring(selStart, selEnd);
    final after = text.substring(selEnd, cStart);

    final buf = StringBuffer();
    buf.write(text.substring(0, oStart));
    if (before.isNotEmpty) {
      buf.write(open);
      buf.write(before);
      buf.write(close);
    }
    final newSelStart = buf.length;
    buf.write(selected);
    final newSelEnd = buf.length;
    if (after.isNotEmpty) {
      buf.write(open);
      buf.write(after);
      buf.write(close);
    }
    buf.write(text.substring(cEnd));
    return [buf.toString(), newSelStart, newSelEnd];
  }

  /// Commit a history snapshot immediately (no debounce).
  void _commitHistory(String description) {
    if (_isCleaning) return;
    _historyTimer?.cancel();
    _typingBulkTimer?.cancel();
    _suiteAutoSaveTimer?.cancel();
    _typingCharCount = 0;

    final currentText = _getRefinedFullText();
    // Skip duplicate: don't commit if text + settings match the current head
    if (_historyIndex >= 0 && _historyIndex < _history.length) {
      final head = _history[_historyIndex];
      final settings = ref.read(settingsProvider);
      if (head.text == currentText &&
          head.fontSize == settings.fontSize &&
          head.fontFamily == settings.fontFamily &&
          head.lineSpacing == settings.lineSpacing &&
          head.letterSpacing == settings.letterSpacing &&
          head.wordSpacing == settings.wordSpacing) {
        return; // No change — skip
      }
    }

    final settings = ref.read(settingsProvider);
    final focusIndex = _focusedBlockIndexForHistory();
    final focusSelection =
        focusIndex == null ? null : _controllers[focusIndex].selection;
    final state = EditorState(
      text: currentText,
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
      scrollOffset: _editorScrollController.hasClients
          ? _editorScrollController.offset
          : null,
    );
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

  int? _focusedBlockIndexForHistory() {
    final active = _lastFocusedController ?? _activeController;
    if (active == null) return _controllers.isEmpty ? null : 0;
    final index = _controllers.indexOf(active);
    if (index >= 0) return index;
    return _controllers.isEmpty ? null : 0;
  }

  void _flushPendingTypingHistoryForTraversal() {
    if (_isCleaning) return;
    final hasPendingTyping =
        _typingCharCount > 0 || (_typingBulkTimer?.isActive ?? false);
    if (!hasPendingTyping) return;
    _commitHistory('Edit Text');
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

  /// Track suite section changes. If the function section changes within the
  /// same suite session, commit the previous section's edits first.
  void _trackSuiteSection(String section) {
    if (_activeSuite == EditorSuite.none) return;
    if (_suiteSection != null && _suiteSection != section && _isSuiteDirty) {
      // Section changed — commit previous section
      _commitHistory(_suiteSection!);
      _isSuiteDirty = false;
    }
    _suiteSection = section;
    _startSuiteAutoSave();
  }

  /// 3-second auto-checkpoint while a suite is open.
  /// Resets on every interaction. If 3s passes with no new interaction
  /// and the suite is dirty, commits a checkpoint.
  void _startSuiteAutoSave() {
    _suiteAutoSaveTimer?.cancel();
    _suiteAutoSaveTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _activeSuite != EditorSuite.none && _isSuiteDirty) {
        _commitHistory(_suiteSection ?? '${_activeSuite.name} Auto-Save');
        _isSuiteDirty = false;
      }
    });
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
    _flushPendingTypingHistoryForTraversal();
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
    _flushPendingTypingHistoryForTraversal();
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
    _loadText(state.text);
    _applySettingsFromState(state);
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
      final base = (focusState?.selectionBaseOffset ??
              targetState.selectionBaseOffset ??
              0)
          .clamp(0, controller.text.length)
          .toInt();
      final extent = (focusState?.selectionExtentOffset ??
              focusState?.selectionBaseOffset ??
              targetState.selectionExtentOffset ??
              targetState.selectionBaseOffset ??
              base)
          .clamp(0, controller.text.length)
          .toInt();

      _lastFocusedController = controller;
      _focusNodes[targetIdx].requestFocus();
      controller.selection = TextSelection(
        baseOffset: base,
        extentOffset: extent,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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
    _isSuiteDirty =
        true; // Always treat as session change if color picker is involved
    ref.read(settingsProvider.notifier).setScriptBgColor(color);
    if (_activeSuite == EditorSuite.none) {
      _saveHistory(description: 'Change Background', debounce: true);
    }
    if (mounted) _setEditorState(() {});
  }

  /// Returns the list of controllers that should receive a style command,
  /// honoring an active overlay selection (refined or global) when present.
}
