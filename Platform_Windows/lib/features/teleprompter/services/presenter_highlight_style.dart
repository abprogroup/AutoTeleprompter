import 'package:flutter/material.dart';

/// One owner for imported highlight paint; reading-cursor paint stays separate.
class PresenterHighlightStyle {
  const PresenterHighlightStyle._();

  static Color? wordBackground({
    required Color? imported,
    required Color? tracking,
    required bool isPast,
    required bool customPainterEnabled,
  }) {
    if (tracking != null) return tracking;
    if (customPainterEnabled) return null;
    return isPast ? imported?.withValues(alpha: imported.a * 0.15) : imported;
  }

  /// Keep chosen text colors unless an imported highlight makes them illegible.
  /// Past-word opacity is retained: contrast correction must not undo fading.
  static Color readableText({
    required Color text,
    required Color? imported,
    required Color? tracking,
    required Color scriptBackground,
    required bool isPast,
  }) {
    if (imported == null) return text;
    final band =
        isPast ? imported.withValues(alpha: imported.a * 0.15) : imported;
    var background = Color.alphaBlend(band, scriptBackground);
    if (tracking != null) background = Color.alphaBlend(tracking, background);
    final opaqueText = text.withValues(alpha: 1);
    if (_contrast(opaqueText, background) >= 4.5) return text;
    final replacement =
        _contrast(Colors.black, background) >=
                _contrast(Colors.white, background)
            ? Colors.black
            : Colors.white;
    return replacement.withValues(alpha: text.a);
  }

  static double _contrast(Color a, Color b) {
    final first = a.computeLuminance();
    final second = b.computeLuminance();
    return first >= second
        ? (first + 0.05) / (second + 0.05)
        : (second + 0.05) / (first + 0.05);
  }
}
