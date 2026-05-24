part of 'teleprompter_screen.dart';

extension _TeleprompterPresenterSearchParts on _TeleprompterScreenState {
  // Presenter search

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
      if (mounted) {
        _setTeleprompterState(() {
          _presenterSearchToolbarVisible = false;
          _presenterSearchMatches = const [];
          _presenterSearchMatchIndex = -1;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No match for "$query"'),
          backgroundColor: Colors.black.withValues(alpha: 0.9),
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
    if (mounted) {
      _setTeleprompterState(() {
        _presenterSearchToolbarVisible = true;
        _presenterSearchMatches = matches;
        _presenterSearchMatchIndex = initialIndex;
      });
    }
    _jumpToPresenterSearchMatchAt(initialIndex);
  }

  void _jumpPresenterSearchResult(int delta) {
    if (_presenterSearchMatches.isEmpty) return;
    final count = _presenterSearchMatches.length;
    final next = (_presenterSearchMatchIndex + delta) % count;
    final normalized = next < 0 ? next + count : next;
    if (mounted) {
      _setTeleprompterState(() {
        _presenterSearchMatchIndex = normalized;
        _presenterSearchToolbarVisible = true;
      });
    }
    _jumpToPresenterSearchMatchAt(normalized);
  }

  void _jumpToPresenterSearchMatchAt(int matchIndex) {
    final script = ref.read(scriptProvider);
    if (script == null ||
        _presenterSearchMatches.isEmpty ||
        matchIndex < 0 ||
        matchIndex >= _presenterSearchMatches.length) {
      return;
    }
    final wordIndex = _presenterSearchMatches[matchIndex]
        .wordIndex
        .clamp(0, script.words.length - 1)
        .toInt();
    _jumpToWordIndex(wordIndex,
        immediate: true); // instant jump, not smooth scroll
    ref.read(teleprompterProvider.notifier).jumpToPosition(wordIndex);
  }

  void _closePresenterSearchToolbar() {
    if (mounted) {
      _setTeleprompterState(() {
        _presenterSearchToolbarVisible = false;
        _presenterSearchMatches = const [];
        _presenterSearchMatchIndex = -1;
      });
    }
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
          color: Colors.black.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x66FFBF00), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
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
    return RegExp(r'[A-Za-z0-9\u0590-\u05FF]').hasMatch(value);
  }
}

// Presenter search data types

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
      if (charIndex >= span.start && charIndex < span.end) {
        return span.wordIndex;
      }
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
