part of 'content_creator_screen.dart';

class _ContentSearchMatch {
  final int wordIndex;
  final int charStart;
  final int charEnd;

  const _ContentSearchMatch({
    required this.wordIndex,
    required this.charStart,
    required this.charEnd,
  });
}

class _ContentSearchSpan {
  final int wordIndex;
  final int start;
  final int end;

  const _ContentSearchSpan({
    required this.wordIndex,
    required this.start,
    required this.end,
  });
}

class _ContentSearchText {
  final String visibleText;
  final List<_ContentSearchSpan> spans;

  const _ContentSearchText(this.visibleText, this.spans);

  int? wordIndexForChar(int charIndex) {
    for (final span in spans) {
      if (charIndex >= span.start && charIndex < span.end) {
        return span.wordIndex;
      }
      if (charIndex < span.start) return span.wordIndex;
    }
    return spans.isEmpty ? null : spans.last.wordIndex;
  }
}

extension _ContentCreatorPresenterTools on _ContentCreatorScreenState {
  List<List<ScriptWord>> _paragraphsForScript(Script script) {
    final paragraphs = <List<ScriptWord>>[];
    var currentParagraph = <ScriptWord>[];
    for (final word in script.words) {
      if (word.isNewline) {
        if (currentParagraph.isNotEmpty) {
          paragraphs.add(currentParagraph);
          currentParagraph = [];
        }
        paragraphs.add([word]);
      } else {
        currentParagraph.add(word);
      }
    }
    if (currentParagraph.isNotEmpty) paragraphs.add(currentParagraph);
    return paragraphs;
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
    _updateContentCreatorState(() {
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
          .replaceAll(_contentCreatorTagStripRe, '')
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

  Future<void> _addContentBookmark() async {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadBookmarksForScript(script, force: true);
    final index = ScriptBookmarkService.nearestBookmarkableWordIndex(
      script.words,
      _activeContentIndex(),
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
    _updateContentCreatorState(() {
      _bookmarks = ScriptBookmarkService.upsert(_bookmarks, bookmark);
    });
    await _saveBookmarksForScript(script);
    _showSnack('Bookmark saved: ${bookmark.label}');
  }

  Future<void> _deleteContentBookmarkAtCurrentPosition() async {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadBookmarksForScript(script, force: true);
    final index = ScriptBookmarkService.nearestBookmarkableWordIndex(
      script.words,
      _activeContentIndex(),
    );
    if (index == null) return;
    final next = _bookmarks.where((b) => b.wordIndex != index).toList();
    if (next.length == _bookmarks.length) {
      _showSnack('No bookmark at this position.');
      return;
    }
    _updateContentCreatorState(() => _bookmarks = next);
    await _saveBookmarksForScript(script);
    _showSnack('Bookmark deleted.');
  }

  Future<void> _jumpContentBookmark(int direction) async {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadBookmarksForScript(script, force: true);
    if (_bookmarks.isEmpty) {
      _showSnack('No bookmarks saved for this script yet.');
      return;
    }
    final current = _activeContentIndex();
    int index;
    if (direction >= 0) {
      index = _bookmarks.indexWhere((b) => b.wordIndex > current);
      if (index == -1) index = 0;
    } else {
      index = _bookmarks.lastIndexWhere((b) => b.wordIndex < current);
      if (index == -1) index = _bookmarks.length - 1;
    }
    final bookmark = _bookmarks[index];
    final target = ScriptBookmarkService.nearestBookmarkableWordIndex(
      script.words,
      bookmark.wordIndex,
    );
    if (target == null) return;
    _jumpToContentWordIndex(target, immediate: true);
    _showSnack('Bookmark: ${bookmark.label}');
  }

  int _activeContentIndex() {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return 0;
    final raw = _isRecording
        ? _activeWordIndex
        : ref.read(teleprompterProvider).confirmedWordIndex;
    return raw.clamp(0, script.words.length - 1).toInt();
  }

  void _resetContentPosition() {
    _stopAutoScroll();
    ref.read(teleprompterProvider.notifier).resetPosition();
    _updateContentCreatorState(() => _activeWordIndex = 0);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToContentWordIndex(int index, {bool immediate = false}) {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    final target = index.clamp(0, script.words.length - 1).toInt();
    _stopAutoScroll();
    _updateContentCreatorState(() => _activeWordIndex = target);
    ref.read(teleprompterProvider.notifier).jumpToPosition(
          target,
          script: script,
        );
    _scrollToContentWordIndex(target, immediate: immediate);
  }

  void _scrollToContentWordIndex(int index, {bool immediate = false}) {
    if (index < 0 || index >= _wordKeys.length) return;
    final ctx = _wordKeys[index].currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !_scrollController.hasClients) return;
    final settings = ref.read(settingsProvider);
    final screenH = MediaQuery.of(context).size.height;
    final targetY = screenH * settings.scrollLead;
    final wordPos =
        box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
    final target = (_scrollController.offset + wordPos.dy - targetY)
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();
    if (immediate) {
      _scrollController.jumpTo(target);
    } else {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _applyContentFontDelta(double delta) {
    final settings = ref.read(settingsProvider);
    final size = (settings.fontSize + delta).clamp(14.0, 120.0).toDouble();
    unawaited(ref.read(settingsProvider.notifier).setFontSize(size));
    unawaited(
      ref.read(scriptProvider.notifier).updateStyleMetadata(fontSize: size),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToContentWordIndex(_activeContentIndex(), immediate: true);
      }
    });
  }

  Future<void> _showContentSearchDialog() async {
    if (_searchDialogOpen) return;
    _searchDialogOpen = true;
    final textCtrl = TextEditingController(text: _lastSearchQuery);
    var wholeWord = _searchWholeWord;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Search script',
            style: TextStyle(color: Colors.white),
          ),
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
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFFFBF00)),
                  ),
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
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {
                'query': textCtrl.text,
                'wholeWord': wholeWord,
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFBF00),
                foregroundColor: Colors.black,
              ),
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
    _setContentSearchQuery(trimmed);
  }

  void _setContentSearchQuery(String query) {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    final search = _buildContentSearchText(script);
    final needle = query.toLowerCase();
    final matches = <_ContentSearchMatch>[];
    var from = 0;
    while (from < search.visibleText.length) {
      final match = search.visibleText.indexOf(needle, from);
      if (match < 0) break;
      final end = match + needle.length;
      if (!_searchWholeWord ||
          _isContentWholeWordMatch(search.visibleText, match, end)) {
        final wordIndex = search.wordIndexForChar(match);
        if (wordIndex != null) {
          matches.add(_ContentSearchMatch(
            wordIndex: wordIndex,
            charStart: match,
            charEnd: end,
          ));
        }
      }
      from = end > match ? end : match + 1;
    }
    if (matches.isEmpty) {
      _updateContentCreatorState(() {
        _contentSearchToolbarVisible = false;
        _contentSearchMatches = const [];
        _contentSearchMatchIndex = -1;
      });
      _showSnack('No match for "$query".');
      return;
    }
    final current = _activeContentIndex();
    final next = matches.indexWhere((m) => m.wordIndex > current);
    final initial = next >= 0 ? next : 0;
    _updateContentCreatorState(() {
      _contentSearchToolbarVisible = true;
      _contentSearchMatches = matches;
      _contentSearchMatchIndex = initial;
    });
    _jumpToContentSearchMatchAt(initial);
  }

  void _jumpContentSearchResult(int delta) {
    if (_contentSearchMatches.isEmpty) return;
    final count = _contentSearchMatches.length;
    final next = (_contentSearchMatchIndex + delta) % count;
    final normalized = next < 0 ? next + count : next;
    _updateContentCreatorState(() {
      _contentSearchMatchIndex = normalized;
      _contentSearchToolbarVisible = true;
    });
    _jumpToContentSearchMatchAt(normalized);
  }

  void _jumpToContentSearchMatchAt(int index) {
    if (index < 0 || index >= _contentSearchMatches.length) return;
    _jumpToContentWordIndex(_contentSearchMatches[index].wordIndex,
        immediate: true);
  }

  void _closeContentSearchToolbar() {
    _updateContentCreatorState(() {
      _contentSearchToolbarVisible = false;
      _contentSearchMatches = const [];
      _contentSearchMatchIndex = -1;
    });
  }

  _ContentSearchText _buildContentSearchText(Script script) {
    final buffer = StringBuffer();
    final spans = <_ContentSearchSpan>[];
    for (final word in script.words) {
      if (word.isNewline) continue;
      final display = word.raw
          .replaceAll(_contentCreatorTagStripRe, '')
          .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '')
          .trim();
      if (display.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write(' ');
      final start = buffer.length;
      buffer.write(display.toLowerCase());
      spans.add(_ContentSearchSpan(
        wordIndex: word.index,
        start: start,
        end: buffer.length,
      ));
    }
    return _ContentSearchText(buffer.toString(), spans);
  }

  bool _isContentWholeWordMatch(String text, int start, int end) {
    final before = start <= 0 ? '' : text[start - 1];
    final after = end >= text.length ? '' : text[end];
    return !_isContentSearchWordChar(before) &&
        !_isContentSearchWordChar(after);
  }

  bool _isContentSearchWordChar(String value) {
    if (value.isEmpty) return false;
    return RegExp(r'[A-Za-z0-9\u0590-\u05FF]').hasMatch(value);
  }

  Widget _buildContentControlBar(AppSettings settings) {
    final isReady = _cameraController?.value.isInitialized == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.94),
            Colors.black.withValues(alpha: 0.68),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _barIcon(
              Icons.arrow_back, 'Back to editor', () => Navigator.pop(context)),
          _barIcon(Icons.skip_previous, 'Previous bookmark',
              () => _jumpContentBookmark(-1)),
          _barText('A', 'Smaller font', () => _applyContentFontDelta(-4)),
          _recordButton(isReady),
          _barText('A', 'Larger font', () => _applyContentFontDelta(4),
              large: true),
          _barIcon(
              Icons.bookmark_add_outlined, 'Add bookmark', _addContentBookmark),
          _barIcon(Icons.bookmark_remove_outlined, 'Remove bookmark',
              _deleteContentBookmarkAtCurrentPosition),
          _barIcon(
              Icons.photo_camera, 'Camera source', _showContentCreatorSettings),
          _barIcon(Icons.tune, 'Prompter settings', _showPrompterSettings),
          _barIcon(
              Icons.skip_next, 'Next bookmark', () => _jumpContentBookmark(1)),
          _barIcon(Icons.replay, 'Restart script', _resetContentPosition),
          _barIcon(Icons.search, 'Search script', _showContentSearchDialog),
        ],
      ),
    );
  }

  Widget _recordButton(bool isReady) {
    return GestureDetector(
      onTap: _toggleRecording,
      child: Tooltip(
        message: _isRecording ? 'Stop recording' : 'Start recording',
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRecording
                  ? Colors.red
                  : (isReady ? Colors.red : Colors.red.withValues(alpha: 0.45)),
            ),
            child: Icon(
              _isRecording ? Icons.stop : Icons.videocam,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  Widget _barIcon(IconData icon, String tooltip, VoidCallback? onPressed) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon,
          color: onPressed == null ? Colors.white24 : Colors.white70),
    );
  }

  Widget _barText(String text, String tooltip, VoidCallback onPressed,
      {bool large = false}) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Text(
        text,
        style: TextStyle(
          color: Colors.white70,
          fontSize: large ? 22 : 16,
          fontWeight: large ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildContentSearchToolbar() {
    if (!_contentSearchToolbarVisible || _lastSearchQuery.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasMatches = _contentSearchMatches.isNotEmpty;
    final label = hasMatches
        ? '${_contentSearchMatchIndex + 1}/${_contentSearchMatches.length}'
        : '0/0';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x66FFBF00), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              _barIcon(Icons.keyboard_arrow_left, 'Previous result',
                  hasMatches ? () => _jumpContentSearchResult(-1) : null),
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
              _barIcon(Icons.keyboard_arrow_right, 'Next result',
                  hasMatches ? () => _jumpContentSearchResult(1) : null),
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
              _barIcon(
                  Icons.search, 'Search new text', _showContentSearchDialog),
              _barIcon(Icons.close, 'Close search toolbar',
                  _closeContentSearchToolbar),
            ],
          ),
        ),
      ),
    );
  }
}
