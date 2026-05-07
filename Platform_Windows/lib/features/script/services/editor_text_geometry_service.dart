import 'package:flutter/material.dart';

import '../../../core/extensions/string_extensions.dart';
import 'markup_decoration_service.dart';

class EditorTextGeometryService {
  static String visibleText(String rawText) =>
      MarkupDecorationParser.visibleText(rawText);

  static bool hasVisibleContent(String rawText) =>
      visibleText(rawText).trim().isNotEmpty;

  static bool resolveTextRtl(String rawText) => visibleText(rawText).isHebrew;

  static bool resolveBlockRtl(List<String> rawBlocks, int index) {
    if (index < 0 || index >= rawBlocks.length) return false;
    final current = rawBlocks[index];
    if (hasVisibleContent(current)) return resolveTextRtl(current);

    for (var i = index - 1; i >= 0; i--) {
      if (hasVisibleContent(rawBlocks[i])) return resolveTextRtl(rawBlocks[i]);
    }
    for (var i = index + 1; i < rawBlocks.length; i++) {
      if (hasVisibleContent(rawBlocks[i])) return resolveTextRtl(rawBlocks[i]);
    }
    return false;
  }

  static TextAlign resolveTextAlign(String rawText, {required bool isRtl}) {
    if (RegExp(r'\[(?:align=)?center\]').hasMatch(rawText)) {
      return TextAlign.center;
    }
    if (RegExp(r'\[(?:align=)?right\]').hasMatch(rawText)) {
      return TextAlign.right;
    }
    if (RegExp(r'\[(?:align=)?left\]').hasMatch(rawText)) {
      return TextAlign.left;
    }
    return isRtl ? TextAlign.right : TextAlign.left;
  }

  static double maxFontSize(String rawText, double defaultSize) {
    var maxSize = defaultSize;
    for (final match
        in RegExp(r'\[size=(\d+(?:\.\d+)?)\]').allMatches(rawText)) {
      final size = double.tryParse(match.group(1)!) ?? defaultSize;
      if (size > maxSize) maxSize = size;
    }
    return maxSize;
  }
}
