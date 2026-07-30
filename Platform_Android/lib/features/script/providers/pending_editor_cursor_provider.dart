import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A one-shot request to place the editor caret at a specific block/offset.
///
/// Set by present/creator modes when the user chooses "Edit at current
/// position"; the editor consumes it once it becomes visible and then clears
/// it.
class EditorCursorTarget {
  final int block;
  final int offset;

  const EditorCursorTarget(this.block, this.offset);
}

final pendingEditorCursorProvider =
    StateProvider<EditorCursorTarget?>((ref) => null);
