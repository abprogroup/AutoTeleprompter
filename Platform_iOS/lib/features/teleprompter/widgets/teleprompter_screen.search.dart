part of 'teleprompter_screen.dart';

extension _TeleprompterSearchParts on _TeleprompterScreenState {
  bool _handlePresentationKey(KeyEvent event) {
    if (event is! KeyDownEvent || _searchDialogOpen || !mounted) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final isSearchShortcut = event.logicalKey == LogicalKeyboardKey.keyF &&
        keyboard.isShiftPressed &&
        (keyboard.isControlPressed || keyboard.isMetaPressed);
    if (!isSearchShortcut) return false;
    Future.microtask(_showPresenterSearchDialog);
    return true;
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
                onPressed: _showPresenterSearchDialog,
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

  Future<void> _showPresenterSearchDialog() async {
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
            hintText: 'Word or phrase to find',
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
            ),
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
      final wordIndex = search.wordIndexForChar(match);
      if (wordIndex != null) {
        matches.add(_PresenterSearchMatch(
          wordIndex: wordIndex.clamp(0, script.words.length - 1).toInt(),
          charStart: match,
          charEnd: match + needle.length,
        ));
      }
      from = match + needle.length;
    }

    if (matches.isEmpty) {
      _updatePresenterSearchState(() {
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
    _updatePresenterSearchState(() {
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
    _updatePresenterSearchState(() {
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
        matchIndex >= _presenterSearchMatches.length) {
      return;
    }
    final wordIndex = _presenterSearchMatches[matchIndex].wordIndex;
    _jumpPresenterToWordIndex(
      wordIndex.clamp(0, script.words.length - 1).toInt(),
      script,
    );
  }

  void _closePresenterSearchToolbar() {
    _updatePresenterSearchState(() {
      _presenterSearchToolbarVisible = false;
      _presenterSearchMatches = const [];
      _presenterSearchMatchIndex = -1;
    });
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
}

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
