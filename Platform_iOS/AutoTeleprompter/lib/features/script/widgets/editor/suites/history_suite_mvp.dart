import 'package:flutter/material.dart';
import '../components/editor_primitives.dart';
import '../../../models/editor_state.dart';

// v3.9.5.59: Sovereign History MVP
class HistorySuite extends StatelessWidget {
  final VoidCallback onUndo, onRedo;
  final bool canUndo, canRedo;
  final List<EditorState> history;
  final int historyIndex;
  final ValueChanged<int> onHistorySelected;

  const HistorySuite({
    super.key,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
    required this.history,
    required this.historyIndex,
    required this.onHistorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolBtn(label: '⎌', tooltip: 'Undo', onTap: onUndo, color: canUndo ? Colors.white : Colors.white10),
        const SizedBox(width: 8),
        ToolBtn(label: '↻', tooltip: 'Redo', onTap: onRedo, color: canRedo ? Colors.white : Colors.white10),
        const SizedBox(width: 2),
        _HistoryMenu(history: history, historyIndex: historyIndex, onHistorySelected: onHistorySelected),
      ],
    );
  }
}

class _HistoryMenu extends StatelessWidget {
  final List<EditorState> history;
  final int historyIndex;
  final ValueChanged<int> onHistorySelected;
  const _HistoryMenu({required this.history, required this.historyIndex, required this.onHistorySelected});
  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    icon: Icon(Icons.history, size: 20, color: history.isEmpty ? Colors.white10 : Colors.white70),
    color: kEditorSurface,
    onSelected: onHistorySelected,
    itemBuilder: (_) => history.asMap().entries.toList().reversed.map((e) => PopupMenuItem(value: e.key, child: Text('${e.value.description} (${e.value.timestamp.hour}:${e.value.timestamp.minute.toString().padLeft(2,"0")})', style: TextStyle(color: e.key == historyIndex ? kEditorAmber : Colors.white70, fontSize: 13)))).toList(),
  );
}
