part of 'script_editor_screen.dart';

const String _bookmarkSign = '\u00BB';
const String _legacyBookmarkSign = '\u00C2\u00BB';

extension _ScriptEditorBookmarkParts on _ScriptEditorScreenState {
  // Load / save.

  Future<void> _loadBookmarksForCurrentScript({bool force = false}) async {
    final key =
        ScriptBookmarkService.scopeKey(_currentSessionId, _currentTitle);
    if (!force &&
        _bookmarkScopeKey == key &&
        (_bookmarksLoaded || _bookmarkLoadingKey == key)) {
      return;
    }
    _bookmarkScopeKey = key;
    _bookmarkLoadingKey = key;
    _bookmarksLoaded = false;
    final loaded = await ScriptBookmarkService.load(key);
    if (!mounted || _bookmarkScopeKey != key) return;
    _setEditorState(() {
      _bookmarks = loaded;
      _bookmarksLoaded = true;
      _bookmarkLoadingKey = null;
    });
  }

  Future<void> _saveBookmarks() async {
    final key = _bookmarkScopeKey ??
        ScriptBookmarkService.scopeKey(_currentSessionId, _currentTitle);
    _bookmarkScopeKey = key;
    _bookmarksLoaded = true;
    await ScriptBookmarkService.save(key, _bookmarks);
  }

  // Sign helpers.

  String _normalizeBookmarkSigns(String text) =>
      text.replaceAll(_legacyBookmarkSign, _bookmarkSign);

  String _stripBookmarkSigns(String text) =>
      _normalizeBookmarkSigns(text).replaceAll(_bookmarkSign, '');

  void _normalizeBookmarkSignsInControllers() {
    final wasCommandExecuting = _isCommandExecuting;
    _isCommandExecuting = true;
    try {
      for (final controller in _controllers) {
        final normalized = _normalizeBookmarkSigns(controller.text);
        if (normalized == controller.text) continue;
        final selection = controller.selection;
        final base = selection.baseOffset.clamp(0, normalized.length).toInt();
        final extent =
            selection.extentOffset.clamp(0, normalized.length).toInt();
        controller.value = TextEditingValue(
          text: normalized,
          selection: TextSelection(baseOffset: base, extentOffset: extent),
        );
      }
    } finally {
      _isCommandExecuting = wasCommandExecuting;
    }
  }

  String _getRefinedFullTextWithoutBookmarkSigns() {
    return _controllers.map((c) => _stripBookmarkSigns(c.text)).join('\n');
  }

  String _getRefinedFullTextWithExportBookmarkSigns() {
    _normalizeBookmarkSignsInControllers();
    final originalTexts = _controllers.map((c) => c.text).toList();
    final exportLines = originalTexts.map(_stripBookmarkSigns).toList();
    final insertions = <({int block, int offset})>[];
    final seen = <String>{};

    void addInsertion(int block, int cleanOffset) {
      if (block < 0 || block >= exportLines.length) return;
      final offset = cleanOffset.clamp(0, exportLines[block].length).toInt();
      final key = '$block:$offset';
      if (!seen.add(key)) return;
      insertions.add((block: block, offset: offset));
    }

    for (var block = 0; block < originalTexts.length; block++) {
      final text = originalTexts[block];
      var rawOffset = text.indexOf(_bookmarkSign);
      while (rawOffset >= 0) {
        addInsertion(
          block,
          _cleanBookmarkExportOffset(
            originalText: text,
            rawOffset: rawOffset,
            cleanLength: exportLines[block].length,
          ),
        );
        rawOffset = text.indexOf(_bookmarkSign, rawOffset + 1);
      }
    }

    for (final bookmark in _bookmarks) {
      final position = _editorPositionForBookmark(bookmark);
      if (position.block < 0 || position.block >= originalTexts.length) {
        continue;
      }
      addInsertion(
        position.block,
        _cleanBookmarkExportOffset(
          originalText: originalTexts[position.block],
          rawOffset: position.offset,
          cleanLength: exportLines[position.block].length,
        ),
      );
    }

    insertions.sort((a, b) {
      final blockCompare = b.block.compareTo(a.block);
      if (blockCompare != 0) return blockCompare;
      return b.offset.compareTo(a.offset);
    });
    for (final insertion in insertions) {
      final line = exportLines[insertion.block];
      exportLines[insertion.block] = line.substring(0, insertion.offset) +
          _bookmarkSign +
          line.substring(insertion.offset);
    }
    return exportLines.join('\n');
  }

  int _cleanBookmarkExportOffset({
    required String originalText,
    required int rawOffset,
    required int cleanLength,
  }) {
    final safeRaw = rawOffset.clamp(0, originalText.length).toInt();
    final cleanText = _stripBookmarkSigns(originalText);
    final signsBefore = RegExp(RegExp.escape(_bookmarkSign))
        .allMatches(originalText.substring(0, safeRaw))
        .length;
    final cleanRaw = (safeRaw - signsBefore).clamp(0, cleanLength).toInt();
    final visibleOffset =
        MarkupDecorationParser.rawToVisibleOffset(cleanText, cleanRaw);
    return MarkupDecorationParser.visibleToRawOffset(
      cleanText,
      visibleOffset,
    ).clamp(0, cleanLength).toInt();
  }

  // Sync text signs to metadata.

  Future<void> _syncBookmarksFromEditorSigns({
    bool notify = true,
    bool save = true,
  }) async {
    _normalizeBookmarkSignsInControllers();
    final rebuilt = <ScriptBookmark>[];
    final now = DateTime.now();
    for (var block = 0; block < _controllers.length; block++) {
      final text = _controllers[block].text;
      var offset = text.indexOf(_bookmarkSign);
      while (offset >= 0) {
        rebuilt.add(ScriptBookmark(
          id: 'editor-$block-$offset',
          label: _bookmarkLabelForEditorPosition(block, offset),
          wordIndex: _wordIndexForEditorPosition(block, offset),
          blockIndex: block,
          offset: offset,
          createdAt: now,
        ));
        offset = text.indexOf(_bookmarkSign, offset + _bookmarkSign.length);
      }
    }
    if (notify) {
      _setEditorState(() => _bookmarks = rebuilt);
    } else {
      _bookmarks = rebuilt;
    }
    _bookmarksLoaded = true;
    if (save) await _saveBookmarks();
  }

  // Reconcile metadata to text signs for old metadata-only bookmark scripts.

  Future<void> _reconcileEditorBookmarkSignsFromMetadata({
    bool recordHistory = true,
  }) async {
    await _loadBookmarksForCurrentScript(force: true);
    if (_controllers.isEmpty) return;
    _normalizeBookmarkSignsInControllers();
    final authoritativeBookmarks = List<ScriptBookmark>.of(_bookmarks);
    final originalTexts = _controllers.map((c) => c.text).toList();
    var changed = false;
    _isCommandExecuting = true;

    for (final controller in _controllers) {
      if (!controller.text.contains(_bookmarkSign)) continue;
      final selection = controller.selection;
      final newText = _stripBookmarkSigns(controller.text);
      controller.value = TextEditingValue(
        text: newText,
        selection: _selectionAfterBookmarkSignRemoval(
          selection: selection,
          oldText: controller.text,
          newTextLength: newText.length,
        ),
      );
      changed = true;
    }

    final ordered = [...authoritativeBookmarks]..sort((a, b) {
        final aPos = _editorPositionForBookmark(a);
        final bPos = _editorPositionForBookmark(b);
        final blockCompare = bPos.block.compareTo(aPos.block);
        if (blockCompare != 0) return blockCompare;
        final aOffset = _cleanBookmarkOffsetFromOriginalText(
          bookmark: a,
          position: aPos,
          originalTexts: originalTexts,
        );
        final bOffset = _cleanBookmarkOffsetFromOriginalText(
          bookmark: b,
          position: bPos,
          originalTexts: originalTexts,
        );
        return bOffset.compareTo(aOffset);
      });
    for (final bookmark in ordered) {
      final position = _editorPositionForBookmark(bookmark);
      if (position.block < 0 || position.block >= _controllers.length) {
        continue;
      }
      final controller = _controllers[position.block];
      final offset = _cleanBookmarkOffsetFromOriginalText(
        bookmark: bookmark,
        position: position,
        originalTexts: originalTexts,
      );
      controller.value = TextEditingValue(
        text: controller.text.substring(0, offset) +
            _bookmarkSign +
            controller.text.substring(offset),
        selection: TextSelection.collapsed(offset: offset + 1),
      );
      changed = true;
    }
    _isCommandExecuting = false;
    if (changed) {
      await _syncBookmarksFromEditorSigns(notify: true, save: true);
      if (recordHistory) {
        _saveHistory(description: 'Sync Bookmarks');
      }
    }
  }

  TextSelection _selectionAfterBookmarkSignRemoval({
    required TextSelection selection,
    required String oldText,
    required int newTextLength,
  }) {
    if (!selection.isValid) {
      return TextSelection.collapsed(
        offset: newTextLength.clamp(0, newTextLength).toInt(),
      );
    }
    int adjust(int offset) {
      final safe = offset.clamp(0, oldText.length).toInt();
      final removedBefore = RegExp(RegExp.escape(_bookmarkSign))
          .allMatches(oldText.substring(0, safe))
          .length;
      return (safe - removedBefore).clamp(0, newTextLength).toInt();
    }

    return TextSelection(
      baseOffset: adjust(selection.baseOffset),
      extentOffset: adjust(selection.extentOffset),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  int _cleanBookmarkOffsetFromOriginalText({
    required ScriptBookmark bookmark,
    required ({int block, int offset}) position,
    required List<String> originalTexts,
  }) {
    if (position.block < 0 || position.block >= _controllers.length) return 0;
    final cleanLength = _controllers[position.block].text.length;
    if (bookmark.id.startsWith('editor-') &&
        position.block < originalTexts.length) {
      final original = originalTexts[position.block];
      final rawOffset = position.offset.clamp(0, original.length).toInt();
      final signsBefore = RegExp(RegExp.escape(_bookmarkSign))
          .allMatches(original.substring(0, rawOffset))
          .length;
      return (rawOffset - signsBefore).clamp(0, cleanLength).toInt();
    }
    return position.offset.clamp(0, cleanLength).toInt();
  }
}
