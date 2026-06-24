part of 'teleprompter_screen.dart';

extension _TeleprompterBookmarkParts on _TeleprompterScreenState {
  bool _presenterBookmarksAllowed() {
    if (ref.read(authProvider).hasPremiumAccess) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bookmarks are included with Pro')),
      );
    }
    return false;
  }

  Future<void> _loadBookmarksForScript(Script script,
      {bool force = false}) async {
    final key = ScriptBookmarkService.scopeKey(script.sessionId, script.title);
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
    _setTeleprompterState(() {
      _bookmarks = loaded;
      _bookmarksLoaded = true;
      _bookmarkLoadingKey = null;
    });
  }

  Future<void> _saveBookmarksForScript(Script script) async {
    final key = ScriptBookmarkService.scopeKey(script.sessionId, script.title);
    _bookmarkScopeKey = key;
    _bookmarksLoaded = true;
    await ScriptBookmarkService.save(key, _bookmarks);
  }

  String _bookmarkLabelForWord(Script script, int wordIndex) {
    final buffer = StringBuffer();
    for (var i = wordIndex; i < script.words.length && i < wordIndex + 8; i++) {
      final word = script.words[i];
      if (word.isNewline) continue;
      final text = word.raw
          .replaceAll(_tagStripRe, '')
          .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '')
          .trim();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(text);
    }
    final label = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (label.isEmpty) return 'Position ${wordIndex + 1}';
    return label.length <= 44 ? label : '${label.substring(0, 44)}...';
  }

  ({int block, int offset}) _editorPositionForPresenterWord(
    Script script,
    int wordIndex,
  ) {
    final words = script.words;
    final rawText = script.rawText;
    if (rawText.isEmpty || words.isEmpty) {
      return (block: 0, offset: 0);
    }
    final target = _snapPresenterBookmarkIndex(script, wordIndex);
    final blocks = rawText.split('\n');
    var cursor = 0;
    for (var block = 0; block < blocks.length; block++) {
      final text = blocks[block];
      final matches = RegExp(r'\S+').allMatches(text).toList();
      if (matches.isNotEmpty &&
          target >= cursor &&
          target < cursor + matches.length) {
        final local = (target - cursor).clamp(0, matches.length - 1).toInt();
        return (block: block, offset: matches[local].start);
      }
      cursor += _presenterBlockTokenLength(
        text,
        includeSoftBreak: block < blocks.length - 1,
      );
    }
    return (block: 0, offset: 0);
  }

  int _presenterBlockTokenLength(
    String text, {
    required bool includeSoftBreak,
  }) {
    if (text.trim().isEmpty) return 1;
    final wordCount = RegExp(r'\S+').allMatches(text).length;
    return wordCount + (includeSoftBreak ? 1 : 0);
  }

  int _snapPresenterBookmarkIndex(Script script, int index) {
    if (script.words.isEmpty) return 0;
    final start = index.clamp(0, script.words.length - 1).toInt();
    for (var i = start; i < script.words.length; i++) {
      final word = script.words[i];
      if (!word.isNewline && word.normalized.isNotEmpty) return i;
    }
    for (var i = start; i >= 0; i--) {
      final word = script.words[i];
      if (!word.isNewline && word.normalized.isNotEmpty) return i;
    }
    return start;
  }

  Future<void> _addPresenterBookmark() async {
    if (!_presenterBookmarksAllowed()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadBookmarksForScript(script, force: true);
    final index = _snapPresenterBookmarkIndex(
      script,
      ref
          .read(teleprompterProvider)
          .confirmedWordIndex
          .clamp(0, script.words.length - 1)
          .toInt(),
    );
    final editorPosition = _editorPositionForPresenterWord(script, index);
    final bookmark = ScriptBookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: _bookmarkLabelForWord(script, index),
      wordIndex: index,
      blockIndex: editorPosition.block,
      offset: editorPosition.offset,
      createdAt: DateTime.now(),
    );
    _setTeleprompterState(() {
      _bookmarks = ScriptBookmarkService.upsert(_bookmarks, bookmark);
    });
    await _saveBookmarksForScript(script);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark saved: ${bookmark.label}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _jumpPresenterBookmark(int direction) async {
    if (!_presenterBookmarksAllowed()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadBookmarksForScript(script, force: true);
    if (!mounted) return;
    if (_bookmarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bookmarks saved for this script yet'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final current = ref.read(teleprompterProvider).confirmedWordIndex;
    int target;
    if (direction >= 0) {
      target = _bookmarks.indexWhere((b) => b.wordIndex > current);
      if (target == -1) target = 0;
    } else {
      target = _bookmarks.lastIndexWhere((b) => b.wordIndex < current);
      if (target == -1) target = _bookmarks.length - 1;
    }
    final bookmark = _bookmarks[target];
    _jumpPresenterToWordIndex(
      bookmark.wordIndex.clamp(0, script.words.length - 1).toInt(),
      script,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark: ${bookmark.label}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _jumpPresenterToWordIndex(int index, Script script) {
    _smoothScrollTimer?.cancel();
    _smoothScrollActive = false;
    _setTeleprompterState(() => _manualWordIndex = index);
    ref
        .read(teleprompterProvider.notifier)
        .jumpToPosition(index, script: script);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _jumpScrollToWordIndex(index);
    });
  }

  void _jumpScrollToWordIndex(int index) {
    if (index < 0 || index >= _wordKeys.length) return;
    if (!_scrollController.hasClients) return;

    final box = _boxForWordIndex(index);
    if (box == null) return;

    final settings = ref.read(settingsProvider);
    final screenH = MediaQuery.of(context).size.height;
    final targetY = screenH * settings.scrollLead;
    final wordPos =
        box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
    final rowProgress = _visualRowProgress(index, box);
    final lineAdvance =
        (box.size.height * settings.lineSpacing).clamp(0.0, screenH * 0.22);
    final target = _scrollController.offset +
        wordPos.dy -
        targetY +
        rowProgress * lineAdvance;

    _scrollController.jumpTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  Future<void> _deletePresenterBookmark(int wordIndex) async {
    if (!_presenterBookmarksAllowed()) return;
    final script = ref.read(scriptProvider);
    if (script == null) return;
    final before = _bookmarks.length;
    final next = _bookmarks
        .where((bookmark) => bookmark.wordIndex != wordIndex)
        .toList();
    final deleted = before - next.length;
    if (deleted <= 0) return;
    _setTeleprompterState(() => _bookmarks = next);
    await _saveBookmarksForScript(script);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            deleted == 1 ? 'Bookmark deleted' : '$deleted bookmarks deleted'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deletePresenterBookmarkAtCurrentPosition() async {
    if (!_presenterBookmarksAllowed()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadBookmarksForScript(script, force: true);
    if (!mounted) return;
    if (_bookmarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bookmarks saved for this script yet'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final current = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, script.words.length - 1)
        .toInt();
    if (!_bookmarks.any((bookmark) => bookmark.wordIndex == current)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bookmark at the current presenter position'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await _deletePresenterBookmark(current);
  }
}
