import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/editor_primitives.dart';
import '../../../models/cursor_style.dart';
import '../../../../settings/providers/settings_provider.dart';

// v3.9.5.60: Sovereign Layout MVP
// — Alignment via icons (format_align_*), RTL/LTR deferred
// — Column layout: each group stacked vertically, no overflow
class LayoutSuite extends ConsumerWidget {
  final ValueChanged<String> onAlign, onDirection;
  final ValueChanged<String> onInteraction;

  const LayoutSuite({
    super.key,
    required this.onAlign,
    required this.onDirection,
    required this.onInteraction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final style = ref.watch(cursorStyleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Row 1: Alignment Icons (centered) ────────────────────────────
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AlignBtn(
                icon: Icons.format_align_left_rounded,
                tooltip: 'Align Left',
                active: style.textAlign == 'left',
                onTap: () { onAlign('left'); onInteraction('Alignment'); },
              ),
              const SizedBox(width: 8),
              _AlignBtn(
                icon: Icons.format_align_center_rounded,
                tooltip: 'Align Center',
                active: style.textAlign == 'center',
                onTap: () { onAlign('center'); onInteraction('Alignment'); },
              ),
              const SizedBox(width: 8),
              _AlignBtn(
                icon: Icons.format_align_right_rounded,
                tooltip: 'Align Right',
                active: style.textAlign == 'right',
                onTap: () { onAlign('right'); onInteraction('Alignment'); },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // ── Row 2: Line spacing ─────────────────────────────────────────
        // Slider displays a delta from the 1.2× default. 0 = default.
        SliderRow(
          label: 'Line Spacing',
          value: (settings.lineSpacing - 1.2).clamp(-1.0, 1.0),
          min: -1.0,
          max: 1.0,
          onChanged: (v) { notifier.setLineSpacing(1.2 + v); onInteraction('Line Spacing'); },
        ),
        // ── Row 3: Letter spacing ───────────────────────────────────────
        SliderRow(
          label: 'Letter Spacing',
          value: settings.letterSpacing.clamp(-2.0, 5.0),
          min: -2.0,
          max: 5.0,
          onChanged: (v) { notifier.setLetterSpacing(v); onInteraction('Letter Spacing'); },
        ),
        // ── Row 4: Word spacing ─────────────────────────────────────────
        SliderRow(
          label: 'Word Spacing',
          value: settings.wordSpacing.toDouble().clamp(-5.0, 20.0),
          min: -5,
          max: 20,
          onChanged: (v) { notifier.setWordSpacing(v); onInteraction('Word Spacing'); },
        ),
      ],
    );
  }
}

/// A compact icon-button for alignment actions — larger, proportional icons.
class _AlignBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _AlignBtn({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFFFBF00);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? Colors.white12 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active
                ? Border.all(color: amber.withOpacity(0.4), width: 1)
                : Border.all(color: Colors.white10, width: 1),
          ),
          child: Icon(icon, size: 24, color: active ? amber : Colors.white70),
        ),
      ),
    );
  }
}
