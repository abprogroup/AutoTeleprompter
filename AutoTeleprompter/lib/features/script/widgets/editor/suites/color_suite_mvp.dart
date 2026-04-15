import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/editor_primitives.dart';
import '../../../../../core/widgets/global_color_picker.dart';
import '../../../../settings/providers/settings_provider.dart';
import '../../../models/cursor_style.dart';

// v3.9.5.59: Sovereign Color MVP
class ColorSuite extends ConsumerWidget {
  final ValueChanged<String> onTextColor, onBgColor;
  final ValueChanged<int> onBgColorChange;
  final Color lastTextColor, lastHighlightColor;

  const ColorSuite({
    super.key,
    required this.onTextColor,
    required this.onBgColor,
    required this.onBgColorChange,
    required this.lastTextColor,
    required this.lastHighlightColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final style = ref.watch(cursorStyleProvider);
    
    final activeTextColor = style.textColor ?? lastTextColor;
    final activeHighlightColor = style.highlightColor ?? lastHighlightColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ColorPickerItem(
            label: 'TEXT',
            color: activeTextColor,
            onChanged: (c) => onTextColor('#' + c.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()),
            title: 'TEXT COLOR PICKER',
          ),
          _ColorPickerItem(
            label: 'HIGHLIGHT',
            color: activeHighlightColor,
            onChanged: (c) => onBgColor('#' + c.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()),
            title: 'HIGHLIGHT PICKER',
          ),
          _ColorPickerItem(
            label: 'BG',
            color: Color(settings.scriptBgColor),
            onChanged: onBgColorChange,
            title: 'BACKGROUND PICKER',
          ),
        ],
      ),
    );
  }
}

class _ColorPickerItem extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<int> onChanged;
  final String title;

  const _ColorPickerItem({required this.label, required this.color, required this.onChanged, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlobalColorButton(
          color: color.value,
          onColorChanged: onChanged,
          title: title,
          showNoneAsWhite: label == 'TEXT',
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
