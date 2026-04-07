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
                // None Color
                0x00000000,
                // Grey & Monochrome
                0xFFFFFFFF, 0xFFBDBDBD, 0xFF757575, 0xFF000000, 
                // Warm Rainbow
                0xFFF44336, 0xFFFF5722, 0xFFFF9800, 0xFFFFEB3B, 
                // Nature & Cool
                0xFFCDDC39, 0xFF4CAF50, 0xFF009688, 0xFF00BCD4, 
                // Deep & Royal
                0xFF2196F3, 0xFF3F51B5, 0xFF9C27B0, 0xFFE91E63,
                // Mint Green (Vibrant)
                // 0xFFB2FF59,
                //Lavender (Soft)
                0xFFE1BEE7,
                //Gold (Amber)
                0xFFFFD600,
                //Sky Blue (Vivid)
                0xFF00E5FF,
                //Coffee (Earthy)
                0xFF795548,
              ].map((c) {
                final isSelected = c == tempColor;
                return GestureDetector(
                  onTap: () {
                    onColorSelected(c);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Color(c), 
                      shape: BoxShape.circle, 
                      border: Border.all(
                        color: isSelected ? Colors.amber : Colors.white38,
                        width: isSelected ? 3 : 1,
                      ),
                      boxShadow: isSelected ? [BoxShadow(color: Colors.amber.withOpacity(0.5), blurRadius: 8)] : null,
                    ),
                    child: c == 0 ? const Center(child: Icon(Icons.block, size: 16, color: Colors.redAccent)) : (isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
                  ),
                );
              }).toList(),
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

  final bool showNoneAsWhite;

  const GlobalColorButton({
    super.key,
    required this.color,
    required this.onColorChanged,
    required this.title,
    this.showNoneAsWhite = false,
  });

  @override
  Widget build(BuildContext context) {
    final isNone = color == 0 || color == 0x00000000;
    
    return GestureDetector(
      onTap: () => showGlobalColorPicker(
        context: context,
        title: title,
        currentColor: color == 0 ? 0xFFFFFFFF : color, // Default to white if none
        onColorSelected: onColorChanged,
      ),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
        color: isNone ? (showNoneAsWhite ? Colors.white : Colors.white10) : Color(color),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white54, width: 2),
        ),
        child: (isNone && !showNoneAsWhite) ? const Center(
          child: Icon(Icons.block, color: Colors.redAccent, size: 20),
        ) : null,
      ),
    );
  }
}
