import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/editor_primitives.dart';
import '../../../models/cursor_style.dart';

// v3.9.5.60: Sovereign Text Styling MVP — Column layout, synced dropdowns
class TextSuite extends ConsumerWidget {
  final VoidCallback onBold, onItalic, onUnderline;
  final ValueChanged<int> onFontSize;
  final ValueChanged<String> onFontFamily;

  static const _fontSizes = [14, 18, 24, 28, 32, 40, 48, 56, 64, 72, 80, 96, 120];
  static const _fontFamilies = ['Inter', 'Roboto', 'Outfit', 'Montserrat', 'Playfair Display', 'Merriweather', 'Lora', 'Courier Prime'];

  const TextSuite({
    super.key,
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onFontSize,
    required this.onFontFamily,
  });

  /// Snap to nearest valid dropdown value
  static int _snapFontSize(int detected) {
    if (_fontSizes.contains(detected)) return detected;
    int closest = _fontSizes.first;
    int minDiff = (detected - closest).abs();
    for (final s in _fontSizes) {
      final diff = (detected - s).abs();
      if (diff < minDiff) { minDiff = diff; closest = s; }
    }
    return closest;
  }

  static String _snapFontFamily(String detected) {
    if (_fontFamilies.contains(detected)) return detected;
    return 'Inter';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(cursorStyleProvider);
    final safeFontSize = _snapFontSize(style.fontSize);
    final safeFontFamily = _snapFontFamily(style.fontFamily);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Row 1: Style toggles ─────────────────────────────────────────
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToolBtn(label: 'B', tooltip: 'Bold',      onTap: onBold,      bold: true,      active: style.isBold),
            ToolBtn(label: 'I', tooltip: 'Italic',    onTap: onItalic,    italic: true,    active: style.isItalic),
            ToolBtn(label: 'U', tooltip: 'Underline', onTap: onUnderline, underline: true, active: style.isUnderline),
          ],
        ),
        const SizedBox(height: 6),
        // ── Row 2: Font & Size (Unified Row) ─────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Font Family
            _DropdownContainer(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: safeFontFamily,
                  dropdownColor: kEditorSurface,
                  icon: const Icon(Icons.font_download_outlined, color: Colors.white54, size: 14),
                  style: const TextStyle(color: kEditorAmber, fontWeight: FontWeight.bold, fontSize: 12),
                  onChanged: (v) { if (v != null) onFontFamily(v); },
                  items: _fontFamilies
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Font Size
            _DropdownContainer(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: safeFontSize,
                  dropdownColor: kEditorSurface,
                  icon: const Icon(Icons.format_size_rounded, color: Colors.white54, size: 14),
                  style: const TextStyle(color: kEditorAmber, fontWeight: FontWeight.bold, fontSize: 12),
                  onChanged: (v) { if (v != null) onFontSize(v); },
                  items: _fontSizes
                      .map((s) => DropdownMenuItem(value: s, child: Text('${s}px')))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DropdownContainer extends StatelessWidget {
  final Widget child;
  const _DropdownContainer({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
    child: child,
  );
}
