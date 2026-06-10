part of 'script_editor_screen.dart';

extension _ScriptEditorTextReplacementParts on _ScriptEditorScreenState {
  bool _replaceAppSelectionWithText({
    required MarkupController editedController,
    required String previousText,
    required String currentText,
  }) {
    final replacement =
        EditorSelectionReplacement.replacementDelta(previousText, currentText);
    if (replacement == null || replacement.contains('\n')) return false;

    final ranges = _activeAppSelectionRangesForEnter();
    if (ranges.length <= 1) return false;

    final editedIndex = _controllers.indexOf(editedController);
    if (editedIndex == -1 ||
        !ranges.any((range) => range.blockIndex == editedIndex)) {
      return false;
    }

    final originalBlocks = <String>[
      for (var i = 0; i < _controllers.length; i++)
        i == editedIndex ? previousText : _controllers[i].text,
    ];
    final result = EditorMultiBlockReplacement.format(
      blocks: originalBlocks,
      ranges: [
        for (final range in ranges)
          EditorReplacementRange(
            blockIndex: range.blockIndex,
            selection: range.selection,
          ),
      ],
      replacement: replacement,
    );
    if (result == null) return false;

    final first = ranges.first;
    final last = ranges.last;
    final targetController = _controllers[first.blockIndex];
    final targetFocus = _focusNodes[first.blockIndex];

    _isCommandExecuting = true;
    try {
      _setEditorState(() {
        targetController.value = TextEditingValue(
          text: result.firstBlockText,
          selection: TextSelection.collapsed(offset: result.caretOffset),
        );
        for (var i = last.blockIndex; i > first.blockIndex; i--) {
          _controllers.removeAt(i).dispose();
          _focusNodes.removeAt(i).dispose();
          _blockKeys.removeAt(i);
        }
      });
      _clearAppSelectionAfterTextInput(targetController);
      _lastFocusedController = targetController;
      targetController.selection =
          TextSelection.collapsed(offset: result.caretOffset);
    } finally {
      _isCommandExecuting = false;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastFocusedController = targetController;
      targetFocus.requestFocus();
      targetController.selection =
          TextSelection.collapsed(offset: result.caretOffset);
    });
    return true;
  }
}

@visibleForTesting
class EditorReplacementRange {
  final int blockIndex;
  final TextSelection selection;

  const EditorReplacementRange({
    required this.blockIndex,
    required this.selection,
  });
}

@visibleForTesting
class EditorMultiBlockReplacementResult {
  final String firstBlockText;
  final int caretOffset;

  const EditorMultiBlockReplacementResult({
    required this.firstBlockText,
    required this.caretOffset,
  });
}

@visibleForTesting
class EditorMultiBlockReplacement {
  static EditorMultiBlockReplacementResult? format({
    required List<String> blocks,
    required List<EditorReplacementRange> ranges,
    required String replacement,
  }) {
    if (replacement.contains('\n') || ranges.length <= 1) return null;
    final sorted = [...ranges]
      ..sort((a, b) {
        final blockCompare = a.blockIndex.compareTo(b.blockIndex);
        if (blockCompare != 0) return blockCompare;
        return a.selection.start.compareTo(b.selection.start);
      });
    final first = sorted.first;
    final last = sorted.last;
    if (first.blockIndex < 0 ||
        last.blockIndex >= blocks.length ||
        first.blockIndex > last.blockIndex) {
      return null;
    }

    final firstText = blocks[first.blockIndex];
    final lastText = blocks[last.blockIndex];
    final firstStart =
        first.selection.start.clamp(0, firstText.length).toInt();
    final lastEnd = last.selection.end.clamp(0, lastText.length).toInt();
    final before = firstText.substring(0, firstStart);
    final after = firstStart == 0
        ? MarkupController.suffixWithOpenTagContext(lastText, lastEnd)
        : lastText.substring(lastEnd);
    return EditorMultiBlockReplacementResult(
      firstBlockText: before + replacement + after,
      caretOffset: before.length + replacement.length,
    );
  }
}
