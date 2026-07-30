import 'package:flutter/material.dart';

// v3.9.5.59: Atomic Design Tokens
const kEditorAmber = Color(0xFFFFBF00);
const kEditorBg = Color(0xFF141414);
const kEditorSurface = Color(0xFF1E1E1E);

// v3.9.5.59: Extracted Editor Suite Enum
enum EditorSuite { none, text, layout, color, bookmarks }

class ToolBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback onTap;
  final bool enabled;
  final bool active, bold, italic, underline;
  final Color? color;
  const ToolBtn(
      {super.key,
      required this.label,
      this.icon,
      this.tooltip,
      required this.onTap,
      this.enabled = true,
      this.active = false,
      this.bold = false,
      this.italic = false,
      this.underline = false,
      this.color});
  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? (color ?? (active ? kEditorAmber : Colors.white70))
        : Colors.white24;
    final btn = Container(
      constraints: const BoxConstraints(minWidth: 38, minHeight: 34),
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? 12 : 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
          color: active ? Colors.white12 : Colors.transparent,
          borderRadius: BorderRadius.circular(8)),
      child: Center(
        child: icon == null
            ? Text(label,
                style: TextStyle(
                    color: foreground,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                    decoration: underline
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    fontSize: 16))
            : Icon(icon, color: foreground, size: 22),
      ),
    );
    final tappable = InkWell(onTap: enabled ? onTap : null, child: btn);
    return tooltip != null
        ? Tooltip(message: tooltip!, child: tappable)
        : tappable;
  }
}

class FormatPopup extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? tooltip;
  final bool active;
  final VoidCallback onTap;
  const FormatPopup(
      {super.key,
      required this.label,
      required this.icon,
      this.tooltip,
      required this.active,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: active ? Colors.white12 : Colors.transparent,
            borderRadius: BorderRadius.circular(8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? kEditorAmber : Colors.white70, size: 20),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: active ? kEditorAmber : Colors.white70,
                    fontSize: 8,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final String? displayValue;
  final ValueChanged<double> onChanged;
  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.displayValue,
  });
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(displayValue ?? value.toStringAsFixed(1),
              style: const TextStyle(
                  color: kEditorAmber,
                  fontSize: 13,
                  fontWeight: FontWeight.bold))
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
              value: value,
              min: min,
              max: max,
              activeColor: kEditorAmber,
              inactiveColor: Colors.white10,
              onChanged: onChanged),
        )
      ]);
}
