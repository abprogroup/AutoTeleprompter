part of 'script_editor_screen.dart';

extension _ScriptEditorBookmarkParts on _ScriptEditorScreenState {
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
    setState(() {
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
    final textBefore = StringBuffer();
    for (var i = 0; i < block && i < _controllers.length; i++) {
      if (textBefore.isNotEmpty) textBefore.write('\n');
      textBefore.write(_controllers[i].text);
    }
    if (block >= 0 && block < _controllers.length) {
      if (textBefore.isNotEmpty) textBefore.write('\n');
      textBefore.write(
        _controllers[block]
            .text
            .substring(0, offset.clamp(0, _controllers[block].text.length)),
      );
    }
    final beforeTokens = WordAligner.tokenize(textBefore.toString());
    final allTokens = WordAligner.tokenize(_getRefinedFullText());
    final maxIndex = allTokens.isEmpty ? 0 : allTokens.length - 1;
    return beforeTokens.length.clamp(0, maxIndex).toInt();
  }

  String _bookmarkLabelForEditorPosition(int block, int offset) {
    if (block < 0 || block >= _controllers.length) return 'Bookmark';
    final text = StylingService.stripTags(_controllers[block].text)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return 'Block ${block + 1}';
    return text.length <= 44 ? text : '${text.substring(0, 44)}...';
  }

  Future<void> _addEditorBookmark() async {
    if (_controllers.isEmpty) return;
    await _loadBookmarksForCurrentScript(force: true);
    final block = _currentEditorBlockIndex();
    final offset = _currentEditorOffset(block);
    final bookmark = ScriptBookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: _bookmarkLabelForEditorPosition(block, offset),
      wordIndex: _wordIndexForEditorPosition(block, offset),
      blockIndex: block,
      offset: offset,
      createdAt: DateTime.now(),
    );
    setState(() {
      _bookmarks = ScriptBookmarkService.upsert(_bookmarks, bookmark);
    });
    await _saveBookmarks();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark saved: ${bookmark.label}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _jumpEditorBookmark(int direction) async {
    await _loadBookmarksForCurrentScript(force: true);
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
      return (
        block: bookmark.blockIndex,
        offset: bookmark.offset.clamp(
          0,
          _controllers[bookmark.blockIndex].text.length,
        )
      );
    }

    var runningTokens = 0;
    for (var block = 0; block < _controllers.length; block++) {
      final blockTokens = WordAligner.tokenize(_controllers[block].text);
      if (bookmark.wordIndex < runningTokens + blockTokens.length) {
        final localToken = (bookmark.wordIndex - runningTokens)
            .clamp(0, blockTokens.isEmpty ? 0 : blockTokens.length - 1)
            .toInt();
        return (
          block: block,
          offset: _rawOffsetForTokenIndex(_controllers[block].text, localToken)
        );
      }
      runningTokens += blockTokens.length + 1;
    }
    final last = _controllers.isEmpty ? -1 : _controllers.length - 1;
    return (
      block: last,
      offset: last >= 0 && last < _controllers.length
          ? _controllers[last].text.length
          : 0
    );
  }

  int _rawOffsetForTokenIndex(String text, int tokenIndex) {
    final matches = RegExp(r'\S+').allMatches(text).toList();
    if (matches.isEmpty) return 0;
    final target = tokenIndex.clamp(0, matches.length - 1).toInt();
    return matches[target].start;
  }

  void _goToEditorBookmark(int bookmarkIndex) {
    if (bookmarkIndex < 0 || bookmarkIndex >= _bookmarks.length) return;
    final bookmark = _bookmarks[bookmarkIndex];
    final position = _editorPositionForBookmark(bookmark);
    if (position.block < 0 || position.block >= _controllers.length) return;
    final controller = _controllers[position.block];
    final selection = TextSelection.collapsed(offset: position.offset);
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      c.externalSelection = null;
      c.isGlobalSelected = false;
    }
    controller.selection = selection;
    _lastFocusedController = controller;
    setState(() {
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
    return _bookmarks.any((bookmark) {
      final position = _editorPositionForBookmark(bookmark);
      return position.block == block;
    });
  }

  Future<void> _deleteEditorBookmarkAtCurrentPosition() async {
    await _loadBookmarksForCurrentScript(force: true);
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
    final ids = _bookmarks
        .where(
            (bookmark) => _editorPositionForBookmark(bookmark).block == block)
        .map((bookmark) => bookmark.id)
        .toSet();
    await _deleteEditorBookmarkIds(ids);
  }

  Future<void> _deleteEditorBookmarkIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final before = _bookmarks.length;
    final next =
        _bookmarks.where((bookmark) => !ids.contains(bookmark.id)).toList();
    final deleted = before - next.length;
    if (deleted <= 0) return;
    setState(() => _bookmarks = next);
    await _saveBookmarks();
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
