part of 'teleprompter_screen.dart';

extension _TeleprompterBookmarksSearchParts on _TeleprompterScreenState {
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
    setState(() {
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

  Future<void> _addPresenterBookmark() async {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadBookmarksForScript(script, force: true);
    final index = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, script.words.length - 1)
        .toInt();
    final bookmark = ScriptBookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: _bookmarkLabelForWord(script, index),
      wordIndex: index,
      blockIndex: -1,
      offset: 0,
      createdAt: DateTime.now(),
    );
    setState(() {
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
    int target;
    if (direction >= 0) {
      target = _bookmarks.indexWhere((b) => b.wordIndex > current);
      if (target == -1) target = 0;
    } else {
      target = _bookmarks.lastIndexWhere((b) => b.wordIndex < current);
      if (target == -1) target = _bookmarks.length - 1;
    }
    final bookmark = _bookmarks[target];
    _jumpToWordIndex(
      bookmark.wordIndex.clamp(0, script.words.length - 1).toInt(),
      immediate: true,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark: ${bookmark.label}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _deletePresenterBookmark(int wordIndex) async {
    final script = ref.read(scriptProvider);
    if (script == null) return;
    final before = _bookmarks.length;
    final next = _bookmarks
        .where((bookmark) => bookmark.wordIndex != wordIndex)
        .toList();
    final deleted = before - next.length;
    if (deleted <= 0) return;
    setState(() => _bookmarks = next);
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

  Future<void> _showSearchDialog() async {
    if (_searchDialogOpen) return;
    _searchDialogOpen = true;
    final controller = TextEditingController(text: _lastSearchQuery);
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title:
            const Text('Search script', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Word to find',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFFBF00))),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFBF00),
                foregroundColor: Colors.black),
            child: const Text('Find'),
          ),
        ],
      ),
    );
    controller.dispose();
    _searchDialogOpen = false;
    if (query == null) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _lastSearchQuery = trimmed;
    _jumpToSearchMatch(trimmed);
  }

  void _jumpToSearchMatch(String query) {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    final needle = query.toLowerCase();
    final words = script.words;
    final current = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, words.length - 1);

    int? match;
    for (var i = current + 1; i < words.length; i++) {
      if (_wordMatchesQuery(words[i], needle)) {
        match = i;
        break;
      }
    }
    if (match == null) {
      for (var i = 0; i <= current && i < words.length; i++) {
        if (_wordMatchesQuery(words[i], needle)) {
          match = i;
          break;
        }
      }
    }

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No match for "$query"'),
          backgroundColor: Colors.black.withOpacity(0.9),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    _jumpToWordIndex(match);
  }

  bool _wordMatchesQuery(ScriptWord word, String needle) {
    if (word.isNewline) return false;
    final text = word.raw
        .replaceAll(_tagStripRe, '')
        .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '')
        .toLowerCase();
    return text.contains(needle);
  }

  /// 60fps smooth scroll — glides toward _scrollTarget using lerp.
  /// Stops automatically when close enough.
}
