import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/editor_primitives.dart';
import '../../../models/cursor_style.dart';
import '../../../services/editor_font_service.dart';

// v3.9.5.60: Sovereign Text Styling MVP — Column layout, synced dropdowns
class TextSuite extends ConsumerWidget {
  final VoidCallback onBold, onItalic, onUnderline;
  final ValueChanged<double> onFontSize;
  final ValueChanged<String> onFontFamily;

  static const _fontSizes = <double>[
    14,
    18,
    24,
    28,
    32,
    40,
    48,
    56,
    64,
    72,
    80,
    96,
    120,
  ];
  const TextSuite({
    super.key,
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onFontSize,
    required this.onFontFamily,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(cursorStyleProvider);
    final safeFontSize = style.fontSize.clamp(1, 300).toDouble();
    final fontSizeItems = {..._fontSizes, safeFontSize}.toList()..sort();
    final safeFontFamily = EditorFontService.cleanFamily(style.fontFamily);
    final fontFamilies = {
      ...EditorFontService.families,
      safeFontFamily,
    }.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Row 1: Style toggles ─────────────────────────────────────────
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToolBtn(
                label: 'B',
                tooltip: 'Bold',
                onTap: onBold,
                bold: true,
                active: style.isBold),
            ToolBtn(
                label: 'I',
                tooltip: 'Italic',
                onTap: onItalic,
                italic: true,
                active: style.isItalic),
            ToolBtn(
                label: 'U',
                tooltip: 'Underline',
                onTap: onUnderline,
                underline: true,
                active: style.isUnderline),
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
                  icon: const Icon(Icons.font_download_outlined,
                      color: Colors.white54, size: 14),
                  style: const TextStyle(
                      color: kEditorAmber,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                  onChanged: (v) {
                    if (v != null) onFontFamily(v);
                  },
                  items: fontFamilies
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Font Size
            _EditableFontSizeField(
              value: safeFontSize,
              suggestions: fontSizeItems,
              onChanged: onFontSize,
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
        decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8)),
        child: child,
      );
}

class _EditableFontSizeField extends StatefulWidget {
  final double value;
  final List<double> suggestions;
  final ValueChanged<double> onChanged;

  const _EditableFontSizeField({
    required this.value,
    required this.suggestions,
    required this.onChanged,
  });

  @override
  State<_EditableFontSizeField> createState() => _EditableFontSizeFieldState();
}

class _EditableFontSizeFieldState extends State<_EditableFontSizeField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _EditableFontSizeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _applyTypedValue();
  }

  void _applyTypedValue() {
    final raw = _controller.text.trim().replaceAll('px', '');
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      _controller.text = _format(widget.value);
      return;
    }
    widget.onChanged(parsed);
    _controller.text = _format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        style: const TextStyle(
          color: kEditorAmber,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          suffixText: 'px',
          suffixStyle: const TextStyle(color: Colors.white54, fontSize: 11),
          suffixIcon: PopupMenuButton<double>(
            tooltip: 'Font size suggestions',
            color: kEditorSurface,
            icon: const Icon(
              Icons.arrow_drop_down_rounded,
              color: Colors.white54,
              size: 18,
            ),
            onSelected: (size) {
              _controller.text = _format(size);
              widget.onChanged(size);
            },
            itemBuilder: (context) => [
              for (final size in widget.suggestions)
                PopupMenuItem<double>(
                  value: size,
                  child: Text(
                    '${_format(size)}px',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        onSubmitted: (_) => _applyTypedValue(),
      ),
    );
  }

  static String _format(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';
}
