part of 'content_creator_screen.dart';

extension _ContentCreatorSearch on _ContentCreatorScreenState {
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
          title: const Text('Search script',
              style: TextStyle(color: Colors.white)),
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
                onSubmitted: (value) => Navigator.pop(
                    ctx, {'query': value, 'wholeWord': wholeWord}),
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
      _showContentSnack('No match for "$query"');
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
      if (charIndex >= span.start && charIndex < span.end)
        return span.wordIndex;
      if (charIndex < span.start) return span.wordIndex;
    }
    return spans.isEmpty ? null : spans.last.wordIndex;
  }
}
