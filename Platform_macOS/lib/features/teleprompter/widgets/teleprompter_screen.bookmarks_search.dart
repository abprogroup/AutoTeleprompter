part of 'teleprompter_screen.dart';

extension _TeleprompterBookmarksSearchParts on _TeleprompterScreenState {
  bool get _hasPresenterBookmarkAccess {
    return ref.read(authProvider).hasPremiumAccess;
  }

  Future<bool> _ensurePresenterBookmarkAccess() async {
    if (_hasPresenterBookmarkAccess) return true;
    if (!mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Bookmarks are included with Pro.'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Connect',
          onPressed: () {
            messenger.hideCurrentSnackBar();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
        ),
      ),
    );
    return false;
  }

  /// Shows a compact banner asking whether to continue from the last reading
  /// position or restart from the beginning.  Appears on re-entry when the
  /// confirmedWordIndex is > 0 (i.e. the user left mid-script last time).
  Future<void> _showResumeDialog(int savedIndex) async {
    if (!mounted) return;
    final script = ref.read(scriptProvider);
    if (script == null) return;

    final wordCount = script.words.where((w) => !w.isNewline).length;
    final percent = wordCount > 0
        ? ((savedIndex / script.words.length) * 100).clamp(0, 100).round()
        : 0;

    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.history, color: Color(0xFFFFBF00), size: 20),
            SizedBox(width: 8),
            Text('Resume reading?',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Text(
          'You left this script at ~$percent%. Would you like to continue '
          'from where you left off, or restart from the beginning?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Restart',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFBF00),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Continue', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (choice == true) {
      _jumpToWordIndex(savedIndex, immediate: true);
    } else {
      // Restart: reset provider word-index and jump to the beginning.
      ref.read(teleprompterProvider.notifier).resetPosition();
      _jumpToWordIndex(0, immediate: true);
    }
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
    var normalized = <ScriptBookmark>[];
    for (final bookmark in loaded) {
      final anchoredTarget =
          ScriptBookmarkService.anchoredWordIndexFromEditorPosition(
        rawText: script.rawText,
        words: script.words,
        blockIndex: bookmark.blockIndex,
        offset: bookmark.offset,
      );
      final target = anchoredTarget ??
          ScriptBookmarkService.nearestBookmarkableWordIndex(
            script.words,
            bookmark.wordIndex,
          );
      if (target == null) {
        continue;
      }
      final normalizedBookmark = target == bookmark.wordIndex
          ? bookmark
          : ScriptBookmark(
              id: bookmark.id,
              label: _bookmarkLabelForWord(script, target),
              wordIndex: target,
              blockIndex: bookmark.blockIndex,
              offset: bookmark.offset,
              createdAt: bookmark.createdAt,
            );
      normalized = ScriptBookmarkService.upsert(normalized, normalizedBookmark);
    }
    if (!mounted || _bookmarkScopeKey != key) return;
    _setTeleprompterState(() {
      _bookmarks = normalized;
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

  Future<void> _addPresenterBookmark() async {
    if (!await _ensurePresenterBookmarkAccess()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadBookmarksForScript(script, force: true);
    if (!mounted) return;
    final currentIndex = ref.read(teleprompterProvider).confirmedWordIndex;
    final index = ScriptBookmarkService.nearestBookmarkableWordIndex(
      script.words,
      currentIndex,
    );
    if (index == null) return;
    final bookmark = ScriptBookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: _bookmarkLabelForWord(script, index),
      wordIndex: index,
      blockIndex: -1,
      offset: 0,
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
    if (!await _ensurePresenterBookmarkAccess()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    final sttState = ref.read(teleprompterProvider);
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

    final current = sttState.confirmedWordIndex;
    int bookmarkListIndex;
    if (direction >= 0) {
      bookmarkListIndex = _bookmarks.indexWhere((b) => b.wordIndex > current);
      if (bookmarkListIndex == -1) bookmarkListIndex = 0;
    } else {
      bookmarkListIndex =
          _bookmarks.lastIndexWhere((b) => b.wordIndex < current);
      if (bookmarkListIndex == -1) bookmarkListIndex = _bookmarks.length - 1;
    }
    final bookmark = _bookmarks[bookmarkListIndex];
    final target = ScriptBookmarkService.nearestBookmarkableWordIndex(
      script.words,
      bookmark.wordIndex,
    );
    if (target == null) return;
    _jumpToWordIndex(target, immediate: true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark: ${bookmark.label}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _tapPresenterBookmarkMarker(int wordIndex) async {
    if (!await _ensurePresenterBookmarkAccess()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadBookmarksForScript(script, force: true);
    if (!mounted) return;

    final safeWordIndex = ScriptBookmarkService.nearestBookmarkableWordIndex(
      script.words,
      wordIndex,
    );
    if (safeWordIndex == null) return;
    ScriptBookmark? bookmark;
    for (final candidate in _bookmarks) {
      if (candidate.wordIndex == safeWordIndex) {
        bookmark = candidate;
        break;
      }
    }

    _jumpToWordIndex(safeWordIndex, immediate: true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bookmark == null
              ? 'Bookmark position selected'
              : 'Bookmark: ${bookmark.label}',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _deletePresenterBookmark(int wordIndex) async {
    if (!await _ensurePresenterBookmarkAccess()) return;
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
    if (!await _ensurePresenterBookmarkAccess()) return;
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
    final currentRaw = ref.read(teleprompterProvider).confirmedWordIndex;
    final current = ScriptBookmarkService.nearestBookmarkableWordIndex(
      script.words,
      currentRaw,
    );
    if (current == null) return;
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
