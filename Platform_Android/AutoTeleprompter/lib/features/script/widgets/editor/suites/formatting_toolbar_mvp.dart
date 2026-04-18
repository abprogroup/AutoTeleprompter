import 'package:flutter/material.dart';
import '../components/editor_primitives.dart';
import '../../../models/editor_state.dart';
import 'text_suite_mvp.dart';
import 'layout_suite_mvp.dart';
import 'color_suite_mvp.dart';
import 'history_suite_mvp.dart';

// v3.9.5.59: Sovereign Formatting Toolbar (Orchestrator MVP)
class FormattingToolbarMVP extends StatelessWidget {
  final VoidCallback onBold, onUnderline, onItalic, onClear, onUndo, onRedo;
  final ValueChanged<int> onFontSize;
  final ValueChanged<String> onAlign, onDirection, onTextColor, onBgColor, onFontFamily;
  final ValueChanged<int> onBgColorChange;
  final Color lastTextColor, lastHighlightColor;
  final bool canUndo, canRedo;
  final List<EditorState> history; // v3.9.5.59: Typed History
  final int historyIndex;
  final ValueChanged<int> onHistorySelected;
  final EditorSuite activeSuite;
  final ValueChanged<EditorSuite> onSuiteToggle;
  final ValueChanged<String> onLayoutInteraction;

  const FormattingToolbarMVP({
    super.key,
    required this.onBold, required this.onUnderline, required this.onItalic,
    required this.onClear, required this.onFontSize, required this.onAlign,
    required this.onDirection, required this.onTextColor, required this.onBgColor,
    required this.onFontFamily, required this.onBgColorChange,
    required this.lastTextColor, required this.lastHighlightColor,
    required this.onUndo, required this.onRedo,
    required this.canUndo, required this.canRedo,
    required this.history, required this.historyIndex,
    required this.onHistorySelected, required this.activeSuite,
    required this.onSuiteToggle, required this.onLayoutInteraction
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: kEditorBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Scale buttons to fit available width
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HistorySuite(
                      onUndo: onUndo, onRedo: onRedo,
                      canUndo: canUndo, canRedo: canRedo,
                      history: history, historyIndex: historyIndex,
                      onHistorySelected: onHistorySelected
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Reset Paragraph Styles',
                      child: InkWell(
                        onTap: onClear,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.format_clear, color: Colors.redAccent, size: 20),
                              SizedBox(height: 2),
                              Text('CLEAR', style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FormatPopup(label: 'TEXT', icon: Icons.text_fields_rounded, active: activeSuite == EditorSuite.text, onTap: () => onSuiteToggle(EditorSuite.text)),
                    const SizedBox(width: 8),
                    FormatPopup(label: 'LAYOUT', icon: Icons.format_align_center_rounded, active: activeSuite == EditorSuite.layout, onTap: () => onSuiteToggle(EditorSuite.layout)),
                    const SizedBox(width: 8),
                    FormatPopup(label: 'COLOR', icon: Icons.palette_rounded, active: activeSuite == EditorSuite.color, onTap: () => onSuiteToggle(EditorSuite.color)),
                  ],
                ),
              );
            },
          ),
        ),
        if (activeSuite != EditorSuite.none)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: const BoxDecoration(color: Color(0xFF1E1E1E), border: Border(top: BorderSide(color: Colors.white10))),
            child: _buildSuite(),
          ),
      ],
    );
  }

  Widget _buildSuite() {
    switch (activeSuite) {
      case EditorSuite.text:
        return TextSuite(onBold: onBold, onItalic: onItalic, onUnderline: onUnderline, onFontSize: onFontSize, onFontFamily: onFontFamily);
      case EditorSuite.layout:
        return LayoutSuite(onAlign: onAlign, onDirection: onDirection, onInteraction: onLayoutInteraction);
      case EditorSuite.color:
        return ColorSuite(onTextColor: onTextColor, onBgColor: onBgColor, onBgColorChange: onBgColorChange, lastTextColor: lastTextColor, lastHighlightColor: lastHighlightColor);
      default:
        return const SizedBox.shrink();
    }
  }
}
