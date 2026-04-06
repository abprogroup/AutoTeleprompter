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
                0xFF000000, 0xFF121212, 0xFF1A1A1A, 0xFF2A2A2A,
                0xFF0B1320, 0xFF1A0F14, 0xFF0F1A14, 0xFF140F1A,
                0xFF1B1B0F, 0xFF0F1B1B, 0xFF1C1311, 0xFF303030,
                0xFFFFEB3B, 0xFFF44336, 0xFF4CAF50, 0xFF2196F3, // Base vibrant colors
                0xFFFF9800, 0xFF9C27B0, 0xFF00BCD4, 0xFFE91E63,
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
