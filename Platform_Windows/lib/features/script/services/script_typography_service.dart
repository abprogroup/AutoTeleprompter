import 'dart:math' as math;

import '../models/script.dart';
import '../models/script_word.dart';

/// Single source of truth for proportional typography calculations across
/// Editor, Presenter, and Content Creator.
///
/// Metadata stores the unscaled base [fontSize] and spacing deltas. Inline
/// `[size=...]` tags remain intact on mixed-size documents and scale
/// proportionally with base size changes so headings stay larger than body
/// text without destroying imported formatting or breaking exports.
class ScriptTypographyService {
  const ScriptTypographyService._();

  static const double minBaseFontSize = 1.0;
  static const double maxBaseFontSize = 120.0;
  static const double minInlineFontSize = 1.0;
  static const double maxInlineFontSize = 300.0;
  static const double presenterScaleFactor = 2.0;

  static final RegExp inlineSizeOpenRegex = RegExp(
    r'\[size=(\d+(?:\.\d+)?)\]',
  );

  /// Resolves the effective unscaled base font size for a script.
  ///
  /// - Uniform inline `[size=...]` scripts report that uniform size.
  /// - Mixed inline `[size=...]` scripts report their dominant (mode) inline
  ///   size when no untagged words exist, or [Script.fontSize] otherwise.
  /// - Plain scripts report [Script.fontSize] (or [fallback] if null).
  static double effectiveBaseFontSize(Script? script, double fallback) {
    if (script == null) return fallback;
    final uniform = uniformInlineFontSize(script.words);
    if (uniform != null) return uniform;
    final dominant = dominantInlineFontSize(script.words);
    if (dominant != null && !hasUnsizedWords(script.words)) {
      return dominant;
    }
    return script.fontSize;
  }

  /// Returns the single inline font size if every non-newline word has the
  /// exact same explicit [ScriptWord.fontSize]; otherwise returns null.
  static double? uniformInlineFontSize(List<ScriptWord> words) {
    double? size;
    for (final word in words) {
      if (word.isNewline) continue;
      final wordSize = word.fontSize;
      if (wordSize == null) return null;
      if (size == null) {
        size = wordSize;
      } else if ((size - wordSize).abs() > 0.001) {
        return null;
      }
    }
    return size;
  }

  /// Returns true when at least one non-newline word has no inline font size.
  static bool hasUnsizedWords(List<ScriptWord> words) {
    for (final word in words) {
      if (word.isNewline) continue;
      if (word.fontSize == null) return true;
    }
    return false;
  }

  /// Returns the most common inline [ScriptWord.fontSize] across non-newline
  /// words, breaking ties in favor of the smaller (body) size.
  static double? dominantInlineFontSize(List<ScriptWord> words) {
    final counts = <double, int>{};
    for (final word in words) {
      if (word.isNewline || word.fontSize == null) continue;
      final bucket = (word.fontSize! * 10).round() / 10.0;
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    double? bestSize;
    var bestCount = -1;
    counts.forEach((size, count) {
      if (count > bestCount ||
          (count == bestCount && (bestSize == null || size < bestSize!))) {
        bestSize = size;
        bestCount = count;
      }
    });
    return bestSize;
  }

  /// Proportionally scales all inline `[size=...]` tags inside [rawText]
  /// when the base font size changes from [fromBaseSize] to [toBaseSize].
  ///
  /// Plain text without `[size=...]` tags is returned unchanged.
  static String scaleInlineFontSizes(
    String rawText, {
    required double fromBaseSize,
    required double toBaseSize,
  }) {
    if (!inlineSizeOpenRegex.hasMatch(rawText)) return rawText;
    final safeFrom = fromBaseSize <= 0 ? toBaseSize : fromBaseSize;
    if (safeFrom <= 0 || (toBaseSize - safeFrom).abs() < 0.001) {
      return rawText;
    }
    final ratio = toBaseSize / safeFrom;
    return rawText.replaceAllMapped(inlineSizeOpenRegex, (match) {
      final parsed = double.tryParse(match.group(1)!);
      if (parsed == null || parsed <= 0) return match.group(0)!;
      final scaled =
          (parsed * ratio).clamp(minInlineFontSize, maxInlineFontSize);
      return '[size=${formatSize(scaled.toDouble())}]';
    });
  }

  /// Scales inline `[size=...]` tags for an explicit A-/A+ [delta] step.
  ///
  /// When [fromBaseSize] has already hit [minBaseFontSize] (or [maxBaseFontSize])
  /// so [toBaseSize] == [fromBaseSize], remaining larger (or smaller) inline
  /// text continues stepping smoothly instead of freezing A-/A+.
  static String scaleInlineFontSizesByDelta(
    String rawText, {
    required double fromBaseSize,
    required double toBaseSize,
    required double delta,
  }) {
    if (!inlineSizeOpenRegex.hasMatch(rawText) || delta.abs() < 0.001) {
      return rawText;
    }
    if ((toBaseSize - fromBaseSize).abs() >= 0.001) {
      return scaleInlineFontSizes(
        rawText,
        fromBaseSize: fromBaseSize,
        toBaseSize: toBaseSize,
      );
    }
    final sizes = <double>[];
    for (final match in inlineSizeOpenRegex.allMatches(rawText)) {
      final parsed = double.tryParse(match.group(1)!);
      if (parsed != null && parsed > 0) sizes.add(parsed);
    }
    if (sizes.isEmpty) return rawText;

    if (delta < 0) {
      final maxSize = sizes.reduce(math.max);
      if (maxSize <= minInlineFontSize + 0.001) return rawText;
      final targetMax =
          (maxSize + delta).clamp(minInlineFontSize, maxInlineFontSize);
      final ratio = targetMax / maxSize;
      return rawText.replaceAllMapped(inlineSizeOpenRegex, (match) {
        final parsed = double.tryParse(match.group(1)!);
        if (parsed == null || parsed <= 0) return match.group(0)!;
        if (parsed <= minInlineFontSize + 0.001) {
          return '[size=${formatSize(minInlineFontSize)}]';
        }
        final scaled = math
            .min(parsed * ratio, parsed - 0.1)
            .clamp(minInlineFontSize, maxInlineFontSize)
            .toDouble();
        return '[size=${formatSize(scaled)}]';
      });
    }

    final minSize = sizes.reduce(math.min);
    if (minSize >= maxInlineFontSize - 0.001) return rawText;
    final targetMin =
        (minSize + delta).clamp(minInlineFontSize, maxInlineFontSize);
    final ratio = targetMin / minSize;
    return rawText.replaceAllMapped(inlineSizeOpenRegex, (match) {
      final parsed = double.tryParse(match.group(1)!);
      if (parsed == null || parsed <= 0) return match.group(0)!;
      if (parsed >= maxInlineFontSize - 0.001) {
        return '[size=${formatSize(maxInlineFontSize)}]';
      }
      final scaled = math
          .max(parsed * ratio, parsed + 0.1)
          .clamp(minInlineFontSize, maxInlineFontSize)
          .toDouble();
      return '[size=${formatSize(scaled)}]';
    });
  }

  /// Formats a font size cleanly without trailing `.0` noise.
  static String formatSize(double size) {
    final rounded = (size * 10).round() / 10.0;
    if ((rounded - rounded.roundToDouble()).abs() < 0.001) {
      return rounded.round().toString();
    }
    return rounded.toStringAsFixed(1);
  }

  /// Returns `null` when [spacing] is zero so Flutter/SkParagraph uses native
  /// font kerning and RTL shaping instead of the manual tracking code path.
  static double? effectiveSpacing(double spacing, {double scale = 1.0}) {
    if (spacing.abs() < 0.001) return null;
    return spacing * scale;
  }

  /// Natural proportional space width ratio matching Arial/Inter medium/bold
  /// display typography in Presenter & Content Creator modes.
  static const double presenterSpaceWidthRatio = 0.28;

  /// Presenter inter-word Wrap spacing scaled proportionally to
  /// [presentationFontSize] plus the scaled [wordSpacing] metadata delta.
  static double presenterWordGap(
    double presentationFontSize,
    double wordSpacing,
  ) {
    final defaultSpace = presentationFontSize * presenterSpaceWidthRatio;
    final delta = wordSpacing * presenterScaleFactor;
    return (defaultSpace + delta).clamp(0.0, 120.0).toDouble();
  }

  /// Resolves the rendered presentation font size for a single paragraph so
  /// large inline headings/paragraphs get proportional word spacing instead of
  /// inheriting a small base body font size.
  static double paragraphPresentationFontSize(
    List<ScriptWord> paragraph,
    double fallbackPresentationFontSize,
  ) {
    final counts = <double, int>{};
    for (final word in paragraph) {
      if (word.isNewline) continue;
      final rendered = word.fontSize != null
          ? word.fontSize! * presenterScaleFactor
          : fallbackPresentationFontSize;
      final bucket = (rendered * 10).round() / 10.0;
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    if (counts.isEmpty) return fallbackPresentationFontSize;
    double? bestSize;
    var bestCount = -1;
    counts.forEach((size, count) {
      if (count > bestCount ||
          (count == bestCount && (bestSize == null || size > bestSize!))) {
        bestSize = size;
        bestCount = count;
      }
    });
    return bestSize ?? fallbackPresentationFontSize;
  }

  /// Resolves the rendered font size for a blank-line spacer (`\n\n`) from the
  /// nearest surrounding text paragraph so vertical row gaps match the
  /// surrounding text instead of shrinking to a small base font size.
  static double blankLinePresentationFontSize(
    List<List<ScriptWord>> paragraphs,
    int blankIndex,
    double fallbackPresentationFontSize,
  ) {
    bool isTextParagraph(List<ScriptWord> para) =>
        para.isNotEmpty && !(para.length == 1 && para[0].isNewline);
    for (var i = blankIndex - 1; i >= 0; i--) {
      if (isTextParagraph(paragraphs[i])) {
        return paragraphPresentationFontSize(
          paragraphs[i],
          fallbackPresentationFontSize,
        );
      }
    }
    for (var i = blankIndex + 1; i < paragraphs.length; i++) {
      if (isTextParagraph(paragraphs[i])) {
        return paragraphPresentationFontSize(
          paragraphs[i],
          fallbackPresentationFontSize,
        );
      }
    }
    return fallbackPresentationFontSize;
  }

  /// Returns the maximum inter-word gap across all paragraphs so continuous
  /// highlight/underline decoration painters bridge large-heading spaces cleanly.
  static double maxScriptWordGap(
    List<List<ScriptWord>> paragraphs,
    double fallbackPresentationFontSize,
    double wordSpacing,
  ) {
    var maxGap = presenterWordGap(fallbackPresentationFontSize, wordSpacing);
    for (final para in paragraphs) {
      if (para.length == 1 && para[0].isNewline) continue;
      final paraSize = paragraphPresentationFontSize(
        para,
        fallbackPresentationFontSize,
      );
      final gap = presenterWordGap(paraSize, wordSpacing);
      if (gap > maxGap) maxGap = gap;
    }
    return maxGap;
  }
}
