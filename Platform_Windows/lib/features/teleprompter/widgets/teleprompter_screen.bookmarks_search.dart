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

  Future<void> _tapPresenterBookmarkMarker(int wordIndex) async {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadBookmarksForScript(script, force: true);
    if (!mounted) return;

    final safeWordIndex = wordIndex.clamp(0, script.words.length - 1).toInt();
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

  // ── Presenter search ─────────────────────────────────────────────────────

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
                onSubmitted: (value) => Navigator.pop(ctx, {
                  'query': value,
                  'wholeWord': wholeWord,
                }),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: wholeWord,
                onChanged: (value) => setDlg(() => wholeWord = value ?? false),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: const Color(0xFFFFBF00),
                checkColor: Colors.black,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Match whole word',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {
                'query': textCtrl.text,
                'wholeWord': wholeWord,
              }),
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
    final trimmed = (result['query'] as String? ?? '').trim();
    if (trimmed.isEmpty) return;
    _lastSearchQuery = trimmed;
    _searchWholeWord = result['wholeWord'] as bool? ?? false;
    _setPresenterSearchQuery(trimmed);
  }

  void _setPresenterSearchQuery(String query) {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    final search = _buildPresenterSearchText(script);
    if (search.visibleText.isEmpty) return;

    final needle = query.toLowerCase();
    final matches = <_PresenterSearchMatch>[];
    var from = 0;
    while (from < search.visibleText.length) {
      final match = search.visibleText.indexOf(needle, from);
      if (match < 0) break;
      final end = match + needle.length;
      if (!_searchWholeWord ||
          _isPresenterWholeWordMatch(search.visibleText, match, end)) {
        final wordIndex = search.wordIndexForChar(match);
        if (wordIndex != null) {
          matches.add(_PresenterSearchMatch(
            wordIndex: wordIndex.clamp(0, script.words.length - 1).toInt(),
            charStart: match,
            charEnd: end,
          ));
        }
      }
      from = end > match ? end : match + 1;
    }

    if (matches.isEmpty) {
      if (mounted)
        setState(() {
          _presenterSearchToolbarVisible = false;
          _presenterSearchMatches = const [];
          _presenterSearchMatchIndex = -1;
        });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No match for "$query"'),
          backgroundColor: Colors.black.withOpacity(0.9),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final current = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, script.words.length - 1)
        .toInt();
    final nextIndex = matches.indexWhere((m) => m.wordIndex > current);
    final initialIndex = nextIndex >= 0 ? nextIndex : 0;
    if (mounted)
      setState(() {
        _presenterSearchToolbarVisible = true;
        _presenterSearchMatches = matches;
        _presenterSearchMatchIndex = initialIndex;
      });
    _jumpToPresenterSearchMatchAt(initialIndex);
  }

  void _jumpPresenterSearchResult(int delta) {
    if (_presenterSearchMatches.isEmpty) return;
    final count = _presenterSearchMatches.length;
    final next = (_presenterSearchMatchIndex + delta) % count;
    final normalized = next < 0 ? next + count : next;
    if (mounted)
      setState(() {
        _presenterSearchMatchIndex = normalized;
        _presenterSearchToolbarVisible = true;
      });
    _jumpToPresenterSearchMatchAt(normalized);
  }

  void _jumpToPresenterSearchMatchAt(int matchIndex) {
    final script = ref.read(scriptProvider);
    if (script == null ||
        _presenterSearchMatches.isEmpty ||
        matchIndex < 0 ||
        matchIndex >= _presenterSearchMatches.length) return;
    final wordIndex = _presenterSearchMatches[matchIndex]
        .wordIndex
        .clamp(0, script.words.length - 1)
        .toInt();
    _jumpToWordIndex(wordIndex,
        immediate: true); // instant jump, not smooth scroll
    ref.read(teleprompterProvider.notifier).jumpToPosition(wordIndex);
  }

  void _closePresenterSearchToolbar() {
    if (mounted)
      setState(() {
        _presenterSearchToolbarVisible = false;
        _presenterSearchMatches = const [];
        _presenterSearchMatchIndex = -1;
      });
  }

  Widget _buildPresenterSearchToolbar() {
    if (!_presenterSearchToolbarVisible || _lastSearchQuery.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasMatches = _presenterSearchMatches.isNotEmpty;
    final label = hasMatches
        ? '${_presenterSearchMatchIndex + 1}/${_presenterSearchMatches.length}'
        : '0/0';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x66FFBF00), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              _SearchToolbarButton(
                icon: Icons.keyboard_arrow_left,
                tooltip: 'Previous result',
                onPressed:
                    hasMatches ? () => _jumpPresenterSearchResult(-1) : null,
              ),
              SizedBox(
                width: 86,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _SearchToolbarButton(
                icon: Icons.keyboard_arrow_right,
                tooltip: 'Next result',
                onPressed:
                    hasMatches ? () => _jumpPresenterSearchResult(1) : null,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _lastSearchQuery,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 6),
              _SearchToolbarButton(
                icon: Icons.search,
                tooltip: 'Search new text',
                onPressed: _showSearchDialog,
              ),
              _SearchToolbarButton(
                icon: Icons.close,
                tooltip: 'Close search toolbar',
                onPressed: _closePresenterSearchToolbar,
              ),
            ],
          ),
        ),
      ),
    );
  }

  _PresenterSearchText _buildPresenterSearchText(Script script) {
    final buffer = StringBuffer();
    final spans = <_PresenterSearchSpan>[];
    for (final word in script.words) {
      if (word.isNewline) continue;
      final display = word.raw
          .replaceAll(_tagStripRe, '')
          .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '')
          .trim();
      if (display.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write(' ');
      final start = buffer.length;
      buffer.write(display.toLowerCase());
      spans.add(_PresenterSearchSpan(
        wordIndex: word.index,
        start: start,
        end: buffer.length,
      ));
    }
    return _PresenterSearchText(buffer.toString(), spans);
  }

  bool _isPresenterWholeWordMatch(String text, int start, int end) {
    final before = start <= 0 ? '' : text[start - 1];
    final after = end >= text.length ? '' : text[end];
    return !_isPresenterSearchWordChar(before) &&
        !_isPresenterSearchWordChar(after);
  }

  bool _isPresenterSearchWordChar(String value) {
    if (value.isEmpty) return false;
    return RegExp(r'[A-Za-z0-9֐-׿]').hasMatch(value);
  }

  /// 60fps smooth scroll — glides toward _scrollTarget using lerp.
  /// Stops automatically when close enough.
}

// ── Presenter search data types ───────────────────────────────────────────

class _PresenterSearchMatch {
  final int wordIndex;
  final int charStart;
  final int charEnd;

  const _PresenterSearchMatch({
    required this.wordIndex,
    required this.charStart,
    required this.charEnd,
  });
}

class _PresenterSearchSpan {
  final int wordIndex;
  final int start;
  final int end;

  const _PresenterSearchSpan({
    required this.wordIndex,
    required this.start,
    required this.end,
  });
}

class _PresenterSearchText {
  final String visibleText;
  final List<_PresenterSearchSpan> spans;

  const _PresenterSearchText(this.visibleText, this.spans);

  int charStartAfterWord(int wordIndex) {
    for (final span in spans) {
      if (span.wordIndex > wordIndex) return span.start;
    }
    return visibleText.length;
  }

  int? wordIndexForChar(int charIndex) {
    for (final span in spans) {
      if (charIndex >= span.start && charIndex < span.end)
        return span.wordIndex;
      if (charIndex < span.start) return span.wordIndex;
    }
    return spans.isEmpty ? null : spans.last.wordIndex;
  }
}

class _SearchToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _SearchToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        icon,
        color: onPressed == null ? Colors.white24 : Colors.white70,
      ),
    );
  }
}
