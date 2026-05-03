part of 'teleprompter_screen.dart';

extension _TeleprompterBookmarksSearchParts on _TeleprompterScreenState {
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
        title: Row(
          children: const [
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
      // Continue: script is already scrolled to savedIndex (done before showing
      // the dialog). Nothing more to do — just stay.
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
    final textCtrl = TextEditingController(text: _lastSearchQuery);
    bool wholeWord = _searchWholeWord;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Search script',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Word or phrase to find',
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFFBF00))),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => Navigator.pop(
                    ctx, {'q': textCtrl.text, 'w': wholeWord}),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setDlg(() => wholeWord = !wholeWord),
                child: Row(
                  children: [
                    Icon(
                      wholeWord
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: wholeWord
                          ? const Color(0xFFFFBF00)
                          : Colors.white38,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Whole word only',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  ctx, {'q': textCtrl.text, 'w': wholeWord}),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black),
              child: const Text('Find'),
            ),
          ],
        ),
      ),
    );
    textCtrl.dispose();
    _searchDialogOpen = false;
    if (result == null) return;
    final trimmed = (result['q'] as String).trim();
    if (trimmed.isEmpty) return;
    setState(() => _searchWholeWord = result['w'] as bool);
    _lastSearchQuery = trimmed;
    _openSearchToolbar(trimmed);
  }

  // ── Compact search toolbar ────────────────────────────────────────────────

  void _openSearchToolbar(String query) {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No match for "$query"'),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    final needle = query.toLowerCase();
    final matches = <int>[];
    for (var i = 0; i < script.words.length; i++) {
      if (_wordMatchesQuery(script.words[i], needle)) matches.add(i);
    }
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No match for "$query"'),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    // Start at the match closest to current position.
    final current = ref.read(teleprompterProvider).confirmedWordIndex;
    int startIdx = 0;
    for (var i = 0; i < matches.length; i++) {
      if (matches[i] >= current) {
        startIdx = i;
        break;
      }
      startIdx = i;
    }
    setState(() {
      _searchMatches = matches;
      _searchMatchIndex = startIdx;
      _showSearchToolbar = true;
    });
    _jumpToWordIndex(matches[startIdx]);
    ref.read(teleprompterProvider.notifier).jumpToPosition(matches[startIdx]);
  }

  void _navigateSearchMatch(int delta) {
    if (_searchMatches.isEmpty) return;
    final next = (_searchMatchIndex + delta) % _searchMatches.length;
    setState(() => _searchMatchIndex = next);
    final wordIdx = _searchMatches[next];
    _jumpToWordIndex(wordIdx);
    ref.read(teleprompterProvider.notifier).jumpToPosition(wordIdx);
  }

  void _closeSearchToolbar() {
    setState(() {
      _showSearchToolbar = false;
      _searchMatches = const [];
      _searchMatchIndex = 0;
    });
  }

  Widget buildSearchToolbar() {
    if (!_showSearchToolbar || _searchMatches.isEmpty) return const SizedBox.shrink();
    final total = _searchMatches.length;
    final current = _searchMatchIndex + 1;
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(28),
          color: const Color(0xFF1A1A1A),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 8),
                Icon(Icons.search, color: Colors.white54, size: 16),
                const SizedBox(width: 6),
                Text(
                  '"$_lastSearchQuery"',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13),
                ),
                if (_searchWholeWord)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('W',
                        style: TextStyle(
                            color: Color(0xFFFFBF00),
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(width: 8),
                Text(
                  '$current / $total',
                  style: const TextStyle(
                      color: Color(0xFFFFBF00),
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.arrow_upward,
                      color: Colors.white70, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Previous result',
                  onPressed: () => _navigateSearchMatch(-1),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward,
                      color: Colors.white70, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Next result',
                  onPressed: () => _navigateSearchMatch(1),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white38, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Close search',
                  onPressed: _closeSearchToolbar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    if (_searchWholeWord) {
      // Whole-word: the word's visible text must equal the needle exactly.
      return text == needle;
    }
    // Partial (default): match if needle appears anywhere in the word.
    return text.contains(needle);
  }

  /// 60fps smooth scroll — glides toward _scrollTarget using lerp.
  /// Stops automatically when close enough.
}
