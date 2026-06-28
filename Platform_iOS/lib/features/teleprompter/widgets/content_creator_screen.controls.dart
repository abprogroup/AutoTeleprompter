part of 'content_creator_screen.dart';

final RegExp _creatorTagStripRe = RegExp(
    r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg|font|align)(?:=[^\]]+)?\]|\*\*');

extension _ContentCreatorControls on _ContentCreatorScreenState {
  // ---------------------------------------------------------------------------
  // Bottom control bars: a fixed lower row (most-needed, present-mode style)
  // and a draggable (horizontally scrollable) upper row holding the overflow.
  // ---------------------------------------------------------------------------

  Widget _buildCreatorControls(
    AppSettings settings,
    dynamic tState,
    bool audioOnly,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // UPPER: draggable overflow row.
        _buildCreatorOverflowBar(settings, tState, audioOnly),
        if (_creatorSearchToolbarVisible) ...[
          const SizedBox(height: 8),
          _buildCreatorSearchToolbar(),
        ],
        const SizedBox(height: 14),
        // Red record trigger.
        GestureDetector(
          key: _creatorRecordKey,
          onTap: _recordStartInFlight ? null : _toggleRecording,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording
                    ? Colors.red
                    : _recordStartInFlight
                        ? const Color(0xFFFFBF00)
                        : Colors.red.withValues(alpha: 0.5),
              ),
              child: Icon(
                _isRecording
                    ? Icons.stop
                    : _recordStartInFlight
                        ? Icons.hourglass_top_rounded
                        : (audioOnly ? Icons.mic : Icons.videocam),
                color: _recordStartInFlight ? Colors.black : Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // LOWER: fixed, most-needed controls.
        _buildCreatorFixedBar(settings, tState),
      ],
    );
  }

  Widget _buildCreatorFixedBar(AppSettings settings, dynamic tState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _creatorBarIcon(Icons.close, 'Back to editor', _exitContentCreator),
          if (!settings.contentCreatorRecordingControlsSpeech)
            _creatorBarIcon(
              tState.isListening || tState.isStarting
                  ? Icons.mic
                  : Icons.mic_none_outlined,
              tState.isListening || tState.isStarting
                  ? 'Stop speech'
                  : 'Start speech',
              _toggleSpeechSession,
              key: _creatorSpeechKey,
              color: tState.isListening || tState.isStarting
                  ? const Color(0xFFFFBF00)
                  : Colors.white70,
            ),
          _creatorBarIcon(Icons.tune, 'Prompter & camera settings',
              _showCreatorSettings,
              key: _creatorSettingsKey),
          _creatorBarIcon(Icons.replay, 'Restart script', _resetCreatorPosition),
        ],
      ),
    );
  }

  Widget _buildCreatorOverflowBar(
    AppSettings settings,
    dynamic tState,
    bool audioOnly,
  ) {
    final hasBookmarkAccess = ref.watch(authProvider).hasPremiumAccess;
    final bookmarkColor =
        hasBookmarkAccess ? Colors.white70 : Colors.white24;
    const lockTip = 'Bookmarks are included with Pro';

    final buttons = <Widget>[
      if (!audioOnly && _availableCameras.length > 1)
        _creatorBarIcon(
          Icons.flip_camera_ios_outlined,
          'Switch front/back camera',
          (_isRecording || _recordStartInFlight) ? null : _flipCreatorCamera,
        ),
      if (!audioOnly)
        _creatorBarIcon(
          Icons.photo_camera_outlined,
          'Camera source',
          (_isRecording || _recordStartInFlight) ? null : _showCreatorSettings,
        ),
      _creatorBarText('A', 'Smaller font', () => _applyCreatorFontDelta(-2)),
      _creatorBarText('A', 'Larger font', () => _applyCreatorFontDelta(2),
          large: true),
      _creatorBarIcon(
        hasBookmarkAccess ? Icons.skip_previous_rounded : Icons.lock_outline,
        hasBookmarkAccess ? 'Previous bookmark' : lockTip,
        () => _jumpCreatorBookmark(-1),
        color: bookmarkColor,
      ),
      _creatorBarIcon(
        hasBookmarkAccess ? Icons.bookmark_add_outlined : Icons.lock_outline,
        hasBookmarkAccess ? 'Add bookmark' : lockTip,
        _addCreatorBookmark,
        color: bookmarkColor,
      ),
      _creatorBarIcon(
        hasBookmarkAccess ? Icons.bookmark_remove_outlined : Icons.lock_outline,
        hasBookmarkAccess ? 'Remove bookmark' : lockTip,
        _isRecording ? null : _deleteCreatorBookmarkAtCurrentPosition,
        color: bookmarkColor,
      ),
      _creatorBarIcon(
        hasBookmarkAccess ? Icons.skip_next_rounded : Icons.lock_outline,
        hasBookmarkAccess ? 'Next bookmark' : lockTip,
        () => _jumpCreatorBookmark(1),
        color: bookmarkColor,
      ),
      _creatorBarIcon(Icons.search, 'Search script', _showCreatorSearchDialog),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _overflowBarController,
        physics: const BouncingScrollPhysics(),
        child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
      ),
    );
  }

  Widget _creatorBarIcon(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    Key? key,
    Color color = Colors.white70,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, color: onPressed == null ? Colors.white24 : color),
    );
  }

  Widget _creatorBarText(String text, String tooltip, VoidCallback onPressed,
      {bool large = false}) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Text(
        text,
        style: TextStyle(
          color: Colors.white70,
          fontSize: large ? 22 : 15,
          fontWeight: large ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Camera + font
  // ---------------------------------------------------------------------------

  Future<void> _flipCreatorCamera() async {
    if (_availableCameras.length < 2) return;
    final current = _selectedCameraIndex < 0 ? 0 : _selectedCameraIndex;
    final currentDir = _availableCameras[current].lensDirection;
    final wantFront = currentDir != CameraLensDirection.front;
    final nextIndex = _availableCameras.indexWhere(
      (c) => c.lensDirection ==
          (wantFront
              ? CameraLensDirection.front
              : CameraLensDirection.back),
    );
    if (nextIndex < 0 || nextIndex == current) return;
    _selectedCameraIndex = nextIndex;
    await _initializeCamera();
  }

  void _applyCreatorFontDelta(double delta) {
    final settings = ref.read(settingsProvider);
    final clamped = (settings.fontSize + delta).clamp(14.0, 120.0).toDouble();
    if (clamped == settings.fontSize) return;
    unawaited(ref.read(settingsProvider.notifier).setFontSize(clamped));
  }

  // ---------------------------------------------------------------------------
  // Position jump shared by bookmarks + search
  // ---------------------------------------------------------------------------

  void _jumpCreatorToWordIndex(int index, Script script) {
    final clamped = index.clamp(0, script.words.length - 1).toInt();
    _teleprompterNotifier.jumpToPosition(clamped, script: script);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = clamped < _wordKeys.length
          ? _wordKeys[clamped].currentContext
          : null;
      if (ctx == null) return;
      final lead =
          ref.read(settingsProvider).scrollLead.clamp(0.0, 1.0).toDouble();
      Scrollable.ensureVisible(
        ctx,
        alignment: lead,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Bookmarks (Pro) — same model/scope as present mode.
  // ---------------------------------------------------------------------------

  bool _creatorBookmarksAllowed() {
    if (ref.read(authProvider).hasPremiumAccess) return true;
    _showSnack('Bookmarks are included with Pro');
    return false;
  }

  Future<void> _loadCreatorBookmarks(Script script, {bool force = false}) async {
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
    _setContentCreatorState(() {
      _bookmarks = loaded;
      _bookmarksLoaded = true;
      _bookmarkLoadingKey = null;
    });
  }

  Future<void> _saveCreatorBookmarks(Script script) async {
    final key = ScriptBookmarkService.scopeKey(script.sessionId, script.title);
    _bookmarkScopeKey = key;
    _bookmarksLoaded = true;
    await ScriptBookmarkService.save(key, _bookmarks);
  }

  String _bookmarkLabelForCreatorWord(Script script, int wordIndex) {
    final buffer = StringBuffer();
    for (var i = wordIndex; i < script.words.length && i < wordIndex + 8; i++) {
      final word = script.words[i];
      if (word.isNewline) continue;
      final text = word.raw
          .replaceAll(_creatorTagStripRe, '')
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

  ({int block, int offset}) _editorPositionForCreatorWord(
    Script script,
    int wordIndex,
  ) {
    final words = script.words;
    final rawText = script.rawText;
    if (rawText.isEmpty || words.isEmpty) return (block: 0, offset: 0);
    final target = _snapCreatorBookmarkIndex(script, wordIndex);
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
      cursor += _creatorBlockTokenLength(
        text,
        includeSoftBreak: block < blocks.length - 1,
      );
    }
    return (block: 0, offset: 0);
  }

  int _creatorBlockTokenLength(String text, {required bool includeSoftBreak}) {
    if (text.trim().isEmpty) return 1;
    final wordCount = RegExp(r'\S+').allMatches(text).length;
    return wordCount + (includeSoftBreak ? 1 : 0);
  }

  int _snapCreatorBookmarkIndex(Script script, int index) {
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

  Future<void> _addCreatorBookmark() async {
    if (!_creatorBookmarksAllowed()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadCreatorBookmarks(script, force: true);
    final index = _snapCreatorBookmarkIndex(
      script,
      ref
          .read(teleprompterProvider)
          .confirmedWordIndex
          .clamp(0, script.words.length - 1)
          .toInt(),
    );
    final editorPosition = _editorPositionForCreatorWord(script, index);
    final bookmark = ScriptBookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: _bookmarkLabelForCreatorWord(script, index),
      wordIndex: index,
      blockIndex: editorPosition.block,
      offset: editorPosition.offset,
      createdAt: DateTime.now(),
    );
    _setContentCreatorState(() {
      _bookmarks = ScriptBookmarkService.upsert(_bookmarks, bookmark);
    });
    await _saveCreatorBookmarks(script);
    _showSnack('Bookmark saved: ${bookmark.label}');
  }

  Future<void> _jumpCreatorBookmark(int direction) async {
    if (!_creatorBookmarksAllowed()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadCreatorBookmarks(script, force: true);
    if (!mounted) return;
    if (_bookmarks.isEmpty) {
      _showSnack('No bookmarks saved for this script yet');
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
    _jumpCreatorToWordIndex(bookmark.wordIndex, script);
    _showSnack('Bookmark: ${bookmark.label}');
  }

  Future<void> _deleteCreatorBookmarkAtCurrentPosition() async {
    if (!_creatorBookmarksAllowed()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadCreatorBookmarks(script, force: true);
    if (!mounted) return;
    if (_bookmarks.isEmpty) {
      _showSnack('No bookmarks saved for this script yet');
      return;
    }
    final current = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, script.words.length - 1)
        .toInt();
    final next =
        _bookmarks.where((b) => b.wordIndex != current).toList(growable: false);
    if (next.length == _bookmarks.length) {
      _showSnack('No bookmark at the current position');
      return;
    }
    _setContentCreatorState(() => _bookmarks = next);
    await _saveCreatorBookmarks(script);
    _showSnack('Bookmark deleted');
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<void> _showCreatorSearchDialog() async {
    if (_searchDialogOpen) return;
    _searchDialogOpen = true;
    final controller = TextEditingController(text: _lastSearchQuery);
    bool wholeWord = _searchWholeWord;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title:
              const Text('Search script', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
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
                onSubmitted: (value) =>
                    Navigator.pop(ctx, {'query': value, 'wholeWord': wholeWord}),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: wholeWord,
                onChanged: (value) =>
                    setDialogState(() => wholeWord = value ?? false),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: const Color(0xFFFFBF00),
                checkColor: Colors.black,
                contentPadding: EdgeInsets.zero,
                title: const Text('Match whole word',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  ctx, {'query': controller.text, 'wholeWord': wholeWord}),
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
    controller.dispose();
    _searchDialogOpen = false;
    if (result == null) return;
    final trimmed = (result['query'] as String? ?? '').trim();
    if (trimmed.isEmpty) return;
    _lastSearchQuery = trimmed;
    _searchWholeWord = result['wholeWord'] as bool? ?? false;
    _setCreatorSearchQuery(trimmed);
  }

  void _setCreatorSearchQuery(String query) {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    final search = _buildCreatorSearchText(script);
    if (search.visibleText.isEmpty) return;

    final needle = query.toLowerCase();
    final matches = <_CreatorSearchMatch>[];
    var from = 0;
    while (from < search.visibleText.length) {
      final match = search.visibleText.indexOf(needle, from);
      if (match < 0) break;
      final end = match + needle.length;
      if (!_searchWholeWord ||
          _isCreatorWholeWordMatch(search.visibleText, match, end)) {
        final wordIndex = search.wordIndexForChar(match);
        if (wordIndex != null) {
          matches.add(_CreatorSearchMatch(
            wordIndex: wordIndex.clamp(0, script.words.length - 1).toInt(),
          ));
        }
      }
      from = end > match ? end : match + 1;
    }

    if (matches.isEmpty) {
      _setContentCreatorState(() {
        _creatorSearchToolbarVisible = false;
        _creatorSearchMatches = const [];
        _creatorSearchMatchIndex = -1;
      });
      _showSnack('No match for "$query"');
      return;
    }

    final current = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, script.words.length - 1)
        .toInt();
    final nextIndex = matches.indexWhere((m) => m.wordIndex > current);
    final initialIndex = nextIndex >= 0 ? nextIndex : 0;
    _setContentCreatorState(() {
      _creatorSearchToolbarVisible = true;
      _creatorSearchMatches = matches;
      _creatorSearchMatchIndex = initialIndex;
    });
    _jumpToCreatorSearchMatchAt(initialIndex);
  }

  void _jumpCreatorSearchResult(int delta) {
    if (_creatorSearchMatches.isEmpty) return;
    final count = _creatorSearchMatches.length;
    final next = (_creatorSearchMatchIndex + delta) % count;
    final normalized = next < 0 ? next + count : next;
    _setContentCreatorState(() {
      _creatorSearchMatchIndex = normalized;
      _creatorSearchToolbarVisible = true;
    });
    _jumpToCreatorSearchMatchAt(normalized);
  }

  void _jumpToCreatorSearchMatchAt(int matchIndex) {
    final script = ref.read(scriptProvider);
    if (script == null ||
        _creatorSearchMatches.isEmpty ||
        matchIndex < 0 ||
        matchIndex >= _creatorSearchMatches.length) {
      return;
    }
    _jumpCreatorToWordIndex(
        _creatorSearchMatches[matchIndex].wordIndex, script);
  }

  void _closeCreatorSearchToolbar() {
    _setContentCreatorState(() {
      _creatorSearchToolbarVisible = false;
      _creatorSearchMatches = const [];
      _creatorSearchMatchIndex = -1;
    });
  }

  Widget _buildCreatorSearchToolbar() {
    final hasMatches = _creatorSearchMatches.isNotEmpty;
    final label = hasMatches
        ? '${_creatorSearchMatchIndex + 1}/${_creatorSearchMatches.length}'
        : '0/0';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x66FFBF00), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _creatorBarIcon(Icons.keyboard_arrow_left, 'Previous result',
                hasMatches ? () => _jumpCreatorSearchResult(-1) : null),
            SizedBox(
              width: 72,
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
            _creatorBarIcon(Icons.keyboard_arrow_right, 'Next result',
                hasMatches ? () => _jumpCreatorSearchResult(1) : null),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _lastSearchQuery,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            _creatorBarIcon(
                Icons.search, 'Search new text', _showCreatorSearchDialog),
            _creatorBarIcon(
                Icons.close, 'Close search', _closeCreatorSearchToolbar),
          ],
        ),
      ),
    );
  }

  _CreatorSearchText _buildCreatorSearchText(Script script) {
    final buffer = StringBuffer();
    final spans = <_CreatorSearchSpan>[];
    for (final word in script.words) {
      if (word.isNewline) continue;
      final display = word.raw
          .replaceAll(_creatorTagStripRe, '')
          .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '')
          .trim();
      if (display.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write(' ');
      final start = buffer.length;
      buffer.write(display.toLowerCase());
      spans.add(_CreatorSearchSpan(
        wordIndex: word.index,
        start: start,
        end: buffer.length,
      ));
    }
    return _CreatorSearchText(buffer.toString(), spans);
  }

  bool _isCreatorWholeWordMatch(String text, int start, int end) {
    final before = start <= 0 ? '' : text[start - 1];
    final after = end >= text.length ? '' : text[end];
    return !_isCreatorSearchWordChar(before) &&
        !_isCreatorSearchWordChar(after);
  }

  bool _isCreatorSearchWordChar(String value) {
    if (value.isEmpty) return false;
    return RegExp(r'[A-Za-z0-9֐-׿]').hasMatch(value);
  }
}

class _CreatorSearchMatch {
  final int wordIndex;
  const _CreatorSearchMatch({required this.wordIndex});
}

class _CreatorSearchSpan {
  final int wordIndex;
  final int start;
  final int end;
  const _CreatorSearchSpan({
    required this.wordIndex,
    required this.start,
    required this.end,
  });
}

class _CreatorSearchText {
  final String visibleText;
  final List<_CreatorSearchSpan> spans;
  const _CreatorSearchText(this.visibleText, this.spans);

  int? wordIndexForChar(int charIndex) {
    for (final span in spans) {
      if (charIndex >= span.start && charIndex < span.end) return span.wordIndex;
      if (charIndex < span.start) return span.wordIndex;
    }
    return spans.isEmpty ? null : spans.last.wordIndex;
  }
}
