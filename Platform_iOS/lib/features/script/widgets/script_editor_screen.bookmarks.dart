part of 'script_editor_screen.dart';

extension _ScriptEditorBookmarkParts on _ScriptEditorScreenState {
  static const String _bookmarkSign = '\u00BB';

  bool _editorBookmarksAllowed() {
    if (ref.read(authProvider).hasPremiumAccess) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bookmarks are included with Pro')),
      );
    }
    return false;
  }

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

  String _stripBookmarkSigns(String text) => text.replaceAll(_bookmarkSign, '');

  String _getRefinedFullTextWithoutBookmarkSigns() {
    return _controllers.map((c) => _stripBookmarkSigns(c.text)).join('\n');
  }

  Future<void> _syncBookmarksFromEditorSigns({
    bool notify = true,
    bool save = true,
  }) async {
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

  Future<void> _reconcileEditorBookmarkSignsFromMetadata() async {
    await _loadBookmarksForCurrentScript(force: true);
    if (_controllers.isEmpty) return;
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
      _saveHistory(description: 'Sync Bookmarks');
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

  int _currentEditorBlockIndex() {
    final active = _activeController;
    final index = active == null ? -1 : _controllers.indexOf(active);
    return index >= 0 ? index : 0;
  }

  int _currentEditorOffset(int block) {
    if (block < 0 || block >= _controllers.length) return 0;
    final selection = _controllers[block].selection;
    return selection.isValid
        ? selection.baseOffset.clamp(0, _controllers[block].text.length)
        : 0;
  }

  int _wordIndexForEditorPosition(int block, int offset) {
    final allTokens = WordAligner.tokenize(
      _getRefinedFullTextWithoutBookmarkSigns(),
    );
    if (allTokens.isEmpty) return 0;
    final estimated = _tokenCursorForEditorPosition(block, offset);
    return _snapToReadableWordIndex(allTokens, estimated);
  }

  int _tokenCursorForEditorPosition(int block, int offset) {
    var cursor = 0;
    final lastBlock = _controllers.length - 1;
    for (var i = 0; i < block && i < _controllers.length; i++) {
      cursor += _tokenLengthForEditorBlock(i, includeSoftBreak: i < lastBlock);
    }
    if (block < 0 || block >= _controllers.length) return cursor;
    final text = _controllers[block].text;
    if (text.trim().isEmpty) return cursor;
    final safeOffset = offset.clamp(0, text.length).toInt();
    final localWord = _localWordIndexForRawOffset(text, safeOffset);
    return cursor + localWord;
  }

  int _tokenLengthForEditorBlock(int block, {required bool includeSoftBreak}) {
    if (block < 0 || block >= _controllers.length) return 0;
    final text = _stripBookmarkSigns(_controllers[block].text);
    if (text.trim().isEmpty) return 1;
    final wordCount = RegExp(r'\S+').allMatches(text).length;
    return wordCount + (includeSoftBreak ? 1 : 0);
  }

  int _localWordIndexForRawOffset(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length).toInt();
    final signsBefore = RegExp(RegExp.escape(_bookmarkSign))
        .allMatches(text.substring(0, safeOffset))
        .length;
    final cleanText = _stripBookmarkSigns(text);
    final cleanOffset =
        (safeOffset - signsBefore).clamp(0, cleanText.length).toInt();
    final matches = RegExp(r'\S+').allMatches(cleanText).toList();
    if (matches.isEmpty) return 0;
    for (var i = 0; i < matches.length; i++) {
      if (cleanOffset <= matches[i].start) return i;
      if (cleanOffset > matches[i].start && cleanOffset < matches[i].end) {
        return i;
      }
    }
    return matches.length;
  }

  int _snapToReadableWordIndex(List<ScriptWord> words, int estimated) {
    if (words.isEmpty) return 0;
    final start = estimated.clamp(0, words.length - 1).toInt();
    for (var i = start; i < words.length; i++) {
      if (!words[i].isNewline && words[i].normalized.isNotEmpty) return i;
    }
    for (var i = start; i >= 0; i--) {
      if (!words[i].isNewline && words[i].normalized.isNotEmpty) return i;
    }
    return start;
  }

  String _bookmarkLabelForEditorPosition(int block, int offset) {
    if (block < 0 || block >= _controllers.length) return 'Bookmark';
    final text = StylingService.stripTags(
      _stripBookmarkSigns(_controllers[block].text),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return 'Block ${block + 1}';
    return text.length <= 44 ? text : '${text.substring(0, 44)}...';
  }

  Future<void> _addEditorBookmark() async {
    if (!_editorBookmarksAllowed()) return;
    if (_controllers.isEmpty) return;
    await _loadBookmarksForCurrentScript(force: true);
    final block = _currentEditorBlockIndex();
    final offset = _currentEditorOffset(block);
    if (block < 0 || block >= _controllers.length) return;
    final controller = _controllers[block];
    final safeOffset = offset.clamp(0, controller.text.length).toInt();
    final alreadyAtOffset = safeOffset < controller.text.length &&
        controller.text[safeOffset] == _bookmarkSign;
    final alreadyBeforeOffset =
        safeOffset > 0 && controller.text[safeOffset - 1] == _bookmarkSign;
    if (!alreadyAtOffset && !alreadyBeforeOffset) {
      _isCommandExecuting = true;
      controller.value = TextEditingValue(
        text: controller.text.substring(0, safeOffset) +
            _bookmarkSign +
            controller.text.substring(safeOffset),
        selection: TextSelection.collapsed(offset: safeOffset + 1),
      );
      _isCommandExecuting = false;
      _lastFocusedController = controller;
      _saveHistory(description: 'Add Bookmark');
    }
    await _syncBookmarksFromEditorSigns(notify: true, save: true);
    final label = _bookmarkLabelForEditorPosition(block, safeOffset);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark saved: $label'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _jumpEditorBookmark(int direction) async {
    if (!_editorBookmarksAllowed()) return;
    await _loadBookmarksForCurrentScript(force: true);
    await _syncBookmarksFromEditorSigns(notify: true, save: true);
    if (_bookmarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bookmarks saved for this script yet'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final block = _currentEditorBlockIndex();
    final offset = _currentEditorOffset(block);
    final currentWord = _wordIndexForEditorPosition(block, offset);
    int target;
    if (direction >= 0) {
      target = _bookmarks.indexWhere((b) => b.wordIndex > currentWord);
      if (target == -1) target = 0;
    } else {
      target = _bookmarks.lastIndexWhere((b) => b.wordIndex < currentWord);
      if (target == -1) target = _bookmarks.length - 1;
    }
    _goToEditorBookmark(target);
  }

  ({int block, int offset}) _editorPositionForBookmark(
      ScriptBookmark bookmark) {
    if (bookmark.blockIndex >= 0 && bookmark.blockIndex < _controllers.length) {
      final bookmarkedBlock = _controllers[bookmark.blockIndex];
      if (bookmarkedBlock.text.trim().isEmpty) {
        return _editorPositionForWordIndex(bookmark.wordIndex);
      }
      return (
        block: bookmark.blockIndex,
        offset: bookmark.offset.clamp(
          0,
          _controllers[bookmark.blockIndex].text.length,
        )
      );
    }

    return _editorPositionForWordIndex(bookmark.wordIndex);
  }

  ({int block, int offset}) _editorPositionForWordIndex(int wordIndex) {
    var cursor = 0;
    final lastBlock = _controllers.length - 1;
    for (var block = 0; block < _controllers.length; block++) {
      final text = _controllers[block].text;
      final wordMatches = RegExp(r'\S+')
          .allMatches(text)
          .where((m) => _stripBookmarkSigns(m.group(0) ?? '').trim().isNotEmpty)
          .toList();
      if (wordMatches.isNotEmpty &&
          wordIndex >= cursor &&
          wordIndex < cursor + wordMatches.length) {
        final localToken =
            (wordIndex - cursor).clamp(0, wordMatches.length - 1).toInt();
        return (
          block: block,
          offset: wordMatches[localToken].start,
        );
      }
      cursor += _tokenLengthForEditorBlock(
        block,
        includeSoftBreak: block < lastBlock,
      );
    }
    final last = _controllers.isEmpty ? -1 : _controllers.length - 1;
    return (
      block: last,
      offset: last >= 0 && last < _controllers.length
          ? _controllers[last].text.length
          : 0
    );
  }

  void _goToEditorBookmark(int bookmarkIndex) {
    if (bookmarkIndex < 0 || bookmarkIndex >= _bookmarks.length) return;
    final bookmark = _bookmarks[bookmarkIndex];
    final position = _editorPositionForBookmark(bookmark);
    if (position.block < 0 || position.block >= _controllers.length) return;
    final controller = _controllers[position.block];
    final selection = TextSelection.collapsed(offset: position.offset);
    _clearRecognizedBlockRange('bookmark-jump');
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      c.externalSelection = null;
      c.isGlobalSelected = false;
    }
    controller.selection = selection;
    _lastFocusedController = controller;
    _setEditorState(() {
      _isGlobalSelection = false;
    });
    _focusNodes[position.block].requestFocus();
    _scrollEditorBlockIntoView(position.block, alignment: 0.28);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark: ${bookmark.label}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  bool _hasBookmarkInEditorBlock(int block) {
    return false;
  }

  List<_EditorBookmarkAnchor> _bookmarkAnchorsForEditorBlock(int block) {
    return const [];
  }

  Future<void> _deleteEditorBookmarkAtCurrentPosition() async {
    if (!_editorBookmarksAllowed()) return;
    await _loadBookmarksForCurrentScript(force: true);
    await _syncBookmarksFromEditorSigns(notify: true, save: true);
    if (_bookmarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bookmarks saved for this script yet'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final block = _currentEditorBlockIndex();
    final offset = _currentEditorOffset(block);
    final blockBookmarks = _bookmarks.where((bookmark) {
      final position = _editorPositionForBookmark(bookmark);
      return position.block == block;
    }).toList();
    if (blockBookmarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bookmark in the current editor block'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    blockBookmarks.sort((a, b) {
      final aPosition = _editorPositionForBookmark(a);
      final bPosition = _editorPositionForBookmark(b);
      return (aPosition.offset - offset)
          .abs()
          .compareTo((bPosition.offset - offset).abs());
    });
    await _deleteEditorBookmarkIds({blockBookmarks.first.id});
  }

  Future<void> _deleteEditorBookmarksForBlock(int block) async {
    if (!_editorBookmarksAllowed()) return;
    final ids = _bookmarks
        .where(
            (bookmark) => _editorPositionForBookmark(bookmark).block == block)
        .map((bookmark) => bookmark.id)
        .toSet();
    await _deleteEditorBookmarkIds(ids);
  }

  Future<void> _deleteEditorBookmarkById(String id) async {
    if (!_editorBookmarksAllowed()) return;
    await _deleteEditorBookmarkIds({id});
  }

  Future<void> _deleteEditorBookmarkIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final targets =
        _bookmarks.where((bookmark) => ids.contains(bookmark.id)).toList();
    final deleted = targets.length;
    if (deleted <= 0) return;
    _isCommandExecuting = true;
    final ordered = [...targets]..sort((a, b) {
        final aPos = _editorPositionForBookmark(a);
        final bPos = _editorPositionForBookmark(b);
        final blockCompare = bPos.block.compareTo(aPos.block);
        if (blockCompare != 0) return blockCompare;
        return bPos.offset.compareTo(aPos.offset);
      });
    for (final bookmark in ordered) {
      final position = _editorPositionForBookmark(bookmark);
      if (position.block < 0 || position.block >= _controllers.length) {
        continue;
      }
      final controller = _controllers[position.block];
      final offset = position.offset.clamp(0, controller.text.length).toInt();
      var deleteOffset = -1;
      if (offset < controller.text.length &&
          controller.text[offset] == _bookmarkSign) {
        deleteOffset = offset;
      } else if (offset > 0 && controller.text[offset - 1] == _bookmarkSign) {
        deleteOffset = offset - 1;
      }
      if (deleteOffset < 0) continue;
      controller.value = TextEditingValue(
        text: controller.text.substring(0, deleteOffset) +
            controller.text.substring(deleteOffset + _bookmarkSign.length),
        selection: TextSelection.collapsed(offset: deleteOffset),
      );
    }
    _isCommandExecuting = false;
    await _syncBookmarksFromEditorSigns(notify: true, save: true);
    _saveHistory(description: 'Delete Bookmark');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            deleted == 1 ? 'Bookmark deleted' : '$deleted bookmarks deleted'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _scrollEditorBlockIntoView(int block, {double alignment = 0.25}) {
    if (block < 0 || block >= _blockKeys.length) return;
    void ensure({Duration duration = const Duration(milliseconds: 260)}) {
      final ctx = _blockKeys[block].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: alignment,
      );
    }

    final ctx = _blockKeys[block].currentContext;
    if (ctx != null) {
      ensure();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => ensure());
  }
}

class _EditorBookmarkAnchor {
  final String id;
  final int offset;

  const _EditorBookmarkAnchor({
    required this.id,
    required this.offset,
  });
}
