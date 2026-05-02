part of 'script_editor_screen.dart';

extension _ScriptEditorSearchParts on _ScriptEditorScreenState {
  Future<void> _showEditorSearchDialog() async {
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
    if (query == null) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _lastSearchQuery = trimmed;
    _findVisibleTextInEditor(trimmed);
  }

  void _findVisibleTextInEditor(String query) {
    if (_controllers.isEmpty) return;
    final needle = query.toLowerCase();
    final activeIndex = _activeController != null
        ? _controllers.indexOf(_activeController!)
        : 0;
    final startBlock = activeIndex < 0 ? 0 : activeIndex;
    final activeSelection = _controllers[startBlock].selection;
    final startRawOffset = activeSelection.isValid
        ? activeSelection.end.clamp(0, _controllers[startBlock].text.length)
        : 0;

    ({int block, int visibleOffset})? match;
    for (var i = startBlock; i < _controllers.length; i++) {
      final rawText = _controllers[i].text;
      final fromRaw = i == startBlock ? startRawOffset : 0;
      final fromVisible = MarkupController.rawToVisualOffset(rawText, fromRaw);
      final index = _visibleSearchIndex(rawText, needle, fromVisible);
      if (index >= 0) {
        match = (block: i, visibleOffset: index);
        break;
      }
    }

    if (match == null) {
      for (var i = 0; i <= startBlock && i < _controllers.length; i++) {
        final rawText = _controllers[i].text;
        final endRaw = i == startBlock ? startRawOffset : rawText.length;
        final endVisible = MarkupController.rawToVisualOffset(rawText, endRaw);
        final index = _visibleSearchIndex(
          rawText,
          needle,
          0,
          endVisibleExclusive: endVisible,
        );
        if (index >= 0) {
          match = (block: i, visibleOffset: index);
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

    _overlayKey.currentState?.clearSelection();
    _isGlobalSelection = false;
    for (final controller in _controllers) {
      controller.isGlobalSelected = false;
      controller.externalSelection = null;
      controller.refresh();
    }

    final controller = _controllers[match.block];
    final rawStart = MarkupController.visualToRawOffset(
        controller.text, match.visibleOffset);
    final rawEnd = MarkupController.visualToRawOffset(
      controller.text,
      match.visibleOffset + query.length,
    ).clamp(rawStart, controller.text.length);
    final selection = TextSelection(baseOffset: rawStart, extentOffset: rawEnd);

    controller.selection = selection;
    controller.externalSelection = selection;
    _lastFocusedController = controller;
    _focusNodes[match.block].requestFocus();
    controller.refresh();
    setState(() {});
    _scrollEditorBlockIntoView(match.block, alignment: 0.25);
  }

  int _visibleSearchIndex(
    String rawText,
    String needle,
    int startVisible, {
    int? endVisibleExclusive,
  }) {
    final visible = StylingService.stripTags(rawText).toLowerCase();
    final start = startVisible.clamp(0, visible.length).toInt();
    final end =
        (endVisibleExclusive ?? visible.length).clamp(start, visible.length);
    return visible.substring(0, end).indexOf(needle, start);
  }
}
