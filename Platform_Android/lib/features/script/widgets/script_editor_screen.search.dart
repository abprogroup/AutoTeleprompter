part of 'script_editor_screen.dart';

extension _ScriptEditorSearchParts on _ScriptEditorScreenState {
  Widget _buildEditorSearchToolbar() {
    if (!_editorSearchToolbarVisible || _lastSearchQuery.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasMatches = _editorSearchMatches.isNotEmpty;
    final label = hasMatches
        ? '${_editorSearchMatchIndex + 1}/${_editorSearchMatches.length}'
        : '0/0';
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
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
              _EditorSearchToolbarButton(
                icon: Icons.keyboard_arrow_left,
                tooltip: 'Previous result',
                onPressed:
                    hasMatches ? () => _jumpEditorSearchResult(-1) : null,
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
              _EditorSearchToolbarButton(
                icon: Icons.keyboard_arrow_right,
                tooltip: 'Next result',
                onPressed: hasMatches ? () => _jumpEditorSearchResult(1) : null,
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
              Tooltip(
                message: 'Match whole word',
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _toggleEditorWholeWordSearch,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _searchWholeWord
                          ? const Color(0xFFFFBF00)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _searchWholeWord
                            ? const Color(0xFFFFBF00)
                            : Colors.white24,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Word',
                      style: TextStyle(
                        color: _searchWholeWord ? Colors.black : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _EditorSearchToolbarButton(
                icon: Icons.search,
                tooltip: 'Search new text',
                onPressed: _showEditorSearchDialog,
              ),
              _EditorSearchToolbarButton(
                icon: Icons.close,
                tooltip: 'Close search toolbar',
                onPressed: _closeEditorSearchToolbar,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditorSearchDialog() async {
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
                onSubmitted: (value) => Navigator.pop(ctx, {
                  'query': value,
                  'wholeWord': wholeWord,
                }),
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
                'query': controller.text,
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
    controller.dispose();
    _searchDialogOpen = false;
    if (result == null) return;
    final trimmed = (result['query'] as String? ?? '').trim();
    if (trimmed.isEmpty) return;
    _lastSearchQuery = trimmed;
    _searchWholeWord = result['wholeWord'] as bool? ?? false;
    _setEditorSearchQuery(trimmed);
  }

  void _setEditorSearchQuery(String query) {
    if (_controllers.isEmpty) return;
    final matches = <_EditorSearchMatch>[];
    final needle = query.toLowerCase();
    for (var block = 0; block < _controllers.length; block++) {
      final visible =
          StylingService.stripTags(_controllers[block].text).toLowerCase();
      matches.addAll(_visibleSearchMatches(
        block: block,
        visible: visible,
        needle: needle,
      ));
    }

    if (matches.isEmpty) {
      setState(() {
        _editorSearchToolbarVisible = false;
        _editorSearchMatches = const [];
        _editorSearchMatchIndex = -1;
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

    final activeIndex = _activeController == null
        ? 0
        : _controllers.indexOf(_activeController!);
    final startBlock = activeIndex < 0 ? 0 : activeIndex;
    final activeSelection = _controllers[startBlock].selection;
    final startRawOffset = activeSelection.isValid
        ? activeSelection.end.clamp(0, _controllers[startBlock].text.length)
        : 0;
    final startVisible = MarkupController.rawToVisualOffset(
      _controllers[startBlock].text,
      startRawOffset,
    );
    final initialIndex = matches.indexWhere((match) =>
        match.blockIndex > startBlock ||
        (match.blockIndex == startBlock && match.visibleStart >= startVisible));
    setState(() {
      _editorSearchToolbarVisible = true;
      _editorSearchMatches = matches;
      _editorSearchMatchIndex = initialIndex >= 0 ? initialIndex : 0;
    });
    _jumpToEditorSearchMatchAt(_editorSearchMatchIndex);
  }

  void _toggleEditorWholeWordSearch() {
    if (_lastSearchQuery.isEmpty) return;
    setState(() {
      _searchWholeWord = !_searchWholeWord;
    });
    _setEditorSearchQuery(_lastSearchQuery);
  }

  List<_EditorSearchMatch> _visibleSearchMatches({
    required int block,
    required String visible,
    required String needle,
  }) {
    final matches = <_EditorSearchMatch>[];
    if (needle.isEmpty || visible.isEmpty) return matches;
    var from = 0;
    while (from < visible.length) {
      final index = visible.indexOf(needle, from);
      if (index < 0) break;
      final end = index + needle.length;
      if (!_searchWholeWord || _isWholeWordMatch(visible, index, end)) {
        matches.add(_EditorSearchMatch(
          blockIndex: block,
          visibleStart: index,
          visibleEnd: end,
        ));
      }
      from = end > index ? end : index + 1;
    }
    return matches;
  }

  bool _isWholeWordMatch(String text, int start, int end) {
    final before = start <= 0 ? '' : text[start - 1];
    final after = end >= text.length ? '' : text[end];
    return !_isSearchWordChar(before) && !_isSearchWordChar(after);
  }

  bool _isSearchWordChar(String value) {
    if (value.isEmpty) return false;
    return RegExp(r'[A-Za-z0-9֐-׿]').hasMatch(value);
  }

  void _jumpEditorSearchResult(int delta) {
    if (_editorSearchMatches.isEmpty) return;
    final count = _editorSearchMatches.length;
    final next = (_editorSearchMatchIndex + delta) % count;
    final normalized = next < 0 ? next + count : next;
    setState(() {
      _editorSearchMatchIndex = normalized;
      _editorSearchToolbarVisible = true;
    });
    _jumpToEditorSearchMatchAt(normalized, requestKeyboard: false);
  }

  void _jumpToEditorSearchMatchAt(
    int matchIndex, {
    bool requestKeyboard = false,
  }) {
    if (matchIndex < 0 || matchIndex >= _editorSearchMatches.length) return;
    final match = _editorSearchMatches[matchIndex];
    if (match.blockIndex < 0 || match.blockIndex >= _controllers.length) {
      return;
    }

    _overlayKey.currentState?.clearSelection();
    _isGlobalSelection = false;
    for (final controller in _controllers) {
      controller.isGlobalSelected = false;
      controller.externalSelection = null;
      controller.refresh();
    }

    final controller = _controllers[match.blockIndex];
    final rawStart =
        MarkupController.visualToRawOffset(controller.text, match.visibleStart);
    final rawEnd = MarkupController.visualToRawOffset(
      controller.text,
      match.visibleEnd,
    ).clamp(rawStart, controller.text.length);
    final selection = TextSelection(baseOffset: rawStart, extentOffset: rawEnd);

    controller.selection = selection;
    controller.externalSelection = selection;
    _lastFocusedController = controller;
    if (requestKeyboard) {
      _focusNodes[match.blockIndex].requestFocus();
    } else {
      _focusNodes[match.blockIndex].unfocus();
    }
    controller.refresh();
    setState(() {});
    _scrollEditorBlockIntoView(match.blockIndex, alignment: 0.25);
  }

  void _closeEditorSearchToolbar() {
    setState(() {
      _editorSearchToolbarVisible = false;
      _editorSearchMatches = const [];
      _editorSearchMatchIndex = -1;
    });
  }
}

class _EditorSearchMatch {
  final int blockIndex;
  final int visibleStart;
  final int visibleEnd;

  const _EditorSearchMatch({
    required this.blockIndex,
    required this.visibleStart,
    required this.visibleEnd,
  });
}

class _EditorSearchToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _EditorSearchToolbarButton({
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
