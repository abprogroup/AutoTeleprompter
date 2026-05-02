part of 'teleprompter_screen.dart';

extension _TeleprompterSearchParts on _TeleprompterScreenState {
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
    _jumpToPresenterSearchMatch(trimmed);
  }

  void _jumpToPresenterSearchMatch(String query) {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    final search = _buildPresenterSearchText(script);
    if (search.visibleText.isEmpty) return;

    final needle = query.toLowerCase();
    final current = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, script.words.length - 1)
        .toInt();
    final startChar = search.charStartAfterWord(current);

    var match = search.visibleText.indexOf(needle, startChar);
    if (match < 0) {
      match = search.visibleText.indexOf(needle);
    }
    if (match < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No match for "$query"'),
          backgroundColor: Colors.black.withOpacity(0.9),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final wordIndex = search.wordIndexForChar(match);
    if (wordIndex == null) return;
    _jumpPresenterToWordIndex(
      wordIndex.clamp(0, script.words.length - 1).toInt(),
      script,
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
