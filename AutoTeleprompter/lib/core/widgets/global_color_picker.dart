import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

void showGlobalColorPicker({
  required BuildContext context,
  required String title,
  required int currentColor,
  required Function(int) onColorSelected,
}) {
  int tempColor = currentColor;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorPicker(
              pickerColor: Color(tempColor),
              onColorChanged: (c) => tempColor = c.value,
              colorPickerWidth: 260,
              pickerAreaHeightPercent: 0.7,
              enableAlpha: false,
              displayThumbColor: true,
              paletteType: PaletteType.hsvWithHue,
              labelTypes: const [],
            ),
            const SizedBox(height: 16),
            const Text('Presets', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                0xFFFFFFFF, 0xFFE0E0E0, 0xFFBDBDBD, 0xFF9E9E9E,
                0xFFFFBF00, 0xFFFFCA28, 0xFFFFD54F, 0xFFFFE082,
                0xFF03A9F4, 0xFF29B6F6, 0xFF4FC3F7, 0xFF81D4FA,
                0xFFCDDC39, 0xFFD4E157, 0xFFDCE775, 0xFFE6EE9C,
                0xFF00BCD4, 0xFF26C6DA, 0xFF4DD0E1, 0xFF80DEEA,
              ].map((c) => GestureDetector(
                onTap: () {
                  onColorSelected(c);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: Color(c), 
                    shape: BoxShape.circle, 
                    border: Border.all(color: Colors.white38)
                  ),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx), 
          child: const Text('Cancel', style: TextStyle(color: Colors.white70))
        ),
        ElevatedButton(
          onPressed: () {
            onColorSelected(tempColor);
            Navigator.pop(ctx);
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          child: const Text('Apply', style: TextStyle(color: Colors.black)),
        ),
      ],
    ),
  );
}

class GlobalColorButton extends StatelessWidget {
  final int color;
  final ValueChanged<int> onColorChanged;
  final String title;

  const GlobalColorButton({
    super.key,
    required this.color,
    required this.onColorChanged,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showGlobalColorPicker(
        context: context,
        title: title,
        currentColor: color,
        onColorSelected: onColorChanged,
      ),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white54, width: 2),
        ),
      ),
    );
  }
}
