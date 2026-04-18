import 'package:flutter/material.dart';
import './markup_controller.dart';

// v3.9.5.60: Hardened Geometric Styling Logic
// — Proper nested-style toggle: uses regex search instead of boundary-only matching
mixin StylingLogicMixin<T extends StatefulWidget> on State<T> {
  // These must be provided by the state that uses this mixin
  List<MarkupController> get controllers;
  MarkupController? get activeController;
  bool get isGlobalSelection;
  set isGlobalSelection(bool value);
  bool get isCleaning;
  set isCleaning(bool value);
  void saveHistory({required String description, bool debounce = true});

  void wrapSelection(String open, String close, {String? prefix, MarkupController? controllerOverride, bool skipHistory = false}) {
    // v3.9.5.1: Global Broadcast Mode (Wholesale Replace)
    if (isGlobalSelection) {
      isCleaning = true;
      try {
        for (final c in controllers) {
          if (c.text.isEmpty) continue;
          // Exact 3.9.5.1 logic: Strip all tags and wrap the whole block
          c.text = '$open${c.text.replaceAll(RegExp(r"\[.*?\]|\*\*"), "")}$close';
        }
        // v3.9.5.1: Save history AFTER operation so snapshot captures the update
        saveHistory(description: 'Global Format: $open', debounce: false);
      } finally {
        isCleaning = false;
      }
      return;
    }

    final controller = controllerOverride ?? activeController;

    if (controller == null) return;
    final text = controller.text;
    final selection = (controller.externalSelection != null && controller.externalSelection!.isValid)
        ? controller.externalSelection!
        : controller.selection;
    if (selection == null || !selection.isValid) return;

    final start = selection.start;
    final end = selection.end;

    // Check if cursor/selection is INSIDE this style (detect mode)
    final isActive = _isStyleActiveAt(text, start, end, open, close);

    if (isActive) {
      // ── TOGGLE OFF: Find the enclosing open/close pair and remove them ──
      final result = _removeEnclosingStyle(text, start, end, open, close);
      if (result != null) {
        controller.value = TextEditingValue(
          text: result.text,
          selection: TextSelection(
            baseOffset: result.newStart,
            extentOffset: result.newEnd,
          ),
        );
      }
    } else {
      // ── TOGGLE ON: Wrap selection with tags ────────────────────────────
      if (selection.isCollapsed) {
        final left = text.substring(0, start);
        final right = text.substring(start);
        controller.value = TextEditingValue(
          text: left + open + close + right,
          selection: TextSelection.collapsed(offset: start + open.length),
        );
      } else {
        final before = text.substring(0, start);
        final selected = text.substring(start, end);
        final after = text.substring(end);
        controller.value = TextEditingValue(
          text: before + open + selected + close + after,
          selection: TextSelection(
            baseOffset: start + open.length,
            extentOffset: end + open.length,
          ),
        );
      }
    }
    if (!skipHistory) saveHistory(description: 'Toggle Style: $open');
  }

  /// Specialized logic for parameterized inline styles (like `[size=40]`, `[font=Inter]`).
  /// Replaces existing enclosing tags of the same family instead of nesting them.
  void applyInlineProperty(String family, String open, String close, {MarkupController? controllerOverride, bool skipHistory = false}) {
    // v3.9.5.1: Global Broadcast Mode (Wholesale Replace)
    if (isGlobalSelection) {
      isCleaning = true;
      try {
        for (final c in controllers) {
          if (c.text.isEmpty) continue;
          // Exact 3.9.5.1 logic: Strip all tags and wrap the whole block
          c.text = '$open${c.text.replaceAll(RegExp(r"\[.*?\]|\*\*"), "")}$close';
        }
        // v3.9.5.1: Save history AFTER operation
        saveHistory(description: 'Global Property: $family', debounce: false);
      } finally {
        isCleaning = false;
      }
      return;
    }

    final controller = controllerOverride ?? activeController;

    if (controller == null) return;
    final text = controller.text;
    final selection = (controller.externalSelection != null && controller.externalSelection!.isValid)
        ? controller.externalSelection!
        : controller.selection;
    if (selection == null || !selection.isValid) return;

    final start = selection.start;
    final end = selection.end;

    // Find enclosing open tag of this family
    int openIdx = -1;
    String? foundOpen;
    for (int i = start; i >= 0; i--) {
      final idx = text.lastIndexOf('[$family=', i);
      if (idx == -1) break;
      final closeBracket = text.indexOf(']', idx);
      if (closeBracket != -1) {
        final exactOpen = text.substring(idx, closeBracket + 1);
        final matchClose = text.indexOf(close, closeBracket);
        if (matchClose != -1 && matchClose >= end) {
          openIdx = idx;
          foundOpen = exactOpen;
          break;
        }
      }
      i = idx - 1;
      if (i < 0) break;
    }

    if (openIdx != -1 && foundOpen != null && selection.isCollapsed) {
      // Replace the enclosing tag, retaining the content
      final closeIdx = text.indexOf(close, openIdx + foundOpen.length);
      final content = text.substring(openIdx + foundOpen.length, closeIdx);
      final before = text.substring(0, openIdx);
      final after = text.substring(closeIdx + close.length);
      
      controller.value = TextEditingValue(
        text: before + open + content + close + after,
        selection: TextSelection.collapsed(
          offset: start - foundOpen.length + open.length,
        ),
      );
      saveHistory(description: 'Apply $family');
      return;
    }

    // Range selection or no enclosing tag
    String newText = text;
    int newStart = start;
    int newEnd = end;

    if (openIdx != -1 && foundOpen != null) {
      final closeIdx = text.indexOf(close, openIdx + foundOpen.length);
      newText = text.substring(0, openIdx) +
          text.substring(openIdx + foundOpen.length, closeIdx) +
          text.substring(closeIdx + close.length);
      newStart = (start - foundOpen.length).clamp(0, newText.length);
      newEnd = (end - foundOpen.length).clamp(0, newText.length);
    }

    // Strip internal matching tags inside the selection
    final selected = newText.substring(newStart, newEnd);
    final cleanSelected = selected.replaceAll(RegExp(r'\[' + family + r'=[^\]]+\]|\[\/' + family + r'\]'), '');
    newEnd -= (selected.length - cleanSelected.length);

    final finalBefore = newText.substring(0, newStart);
    final finalAfter = newText.substring(newStart + selected.length);

    if (selection.isCollapsed) {
      controller.value = TextEditingValue(
        text: finalBefore + open + close + finalAfter,
        selection: TextSelection.collapsed(offset: newStart + open.length),
      );
    } else {
      controller.value = TextEditingValue(
        text: finalBefore + open + cleanSelected + close + finalAfter,
        selection: TextSelection(
          baseOffset: newStart + open.length,
          extentOffset: newEnd + open.length,
        ),
      );
    }
    if (!skipHistory) saveHistory(description: 'Apply $family');
  }

  /// v3.9.5.1: Specialized Broadcast for Alignment to preserve other styles
  void broadcastAlign(String align, {required String open, required String close}) {
    if (isGlobalSelection) {
      isCleaning = true;
      try {
        for (final c in controllers) {
          if (c.text.isEmpty) continue;
          // Exact 3.9.5.1 logic: Strip only alignment tags
          final clean = c.text.replaceAll(RegExp(r"\[(?:align=)?(?:center|left|right)\]|\[\/(?:align=)?(?:center|left|right)\]"), '');
          c.text = '$open$clean$close';
        }
        // v3.9.5.1: Save history AFTER operation
        saveHistory(description: 'Global Align: $align', debounce: false);
      } finally {
        isCleaning = false;
      }
      return;
    }
    
    // Fallback to standard wrap for single block
    wrapSelection(open, close);
  }


  /// Detect if cursor position is inside an open/close tag pair.
  bool _isStyleActiveAt(String text, int start, int end, String open, String close) {
    final mid = (start + (end - start) / 2).floor().clamp(0, text.length);

    bool checkAt(int p) {
      if (p < 0 || p > text.length) return false;
      if (open == '**' && close == '**') {
        final before = text.substring(0, p);
        return RegExp(r'\*\*').allMatches(before).length % 2 != 0;
      }
      // Find the nearest open tag before p — try exact match first
      int tagIdx = text.lastIndexOf(open, p);
      int tagLen = open.length;
      // If exact match fails, try family-based search (e.g., [bg= instead of [bg=#FF0000])
      if (tagIdx == -1) {
        final familyMatch = RegExp(r'^\[(\w+)=').firstMatch(open);
        if (familyMatch != null) {
          final family = familyMatch.group(1)!;
          final pattern = '[$family=';
          int searchFrom = p;
          while (searchFrom >= 0) {
            tagIdx = text.lastIndexOf(pattern, searchFrom);
            if (tagIdx == -1) break;
            final closeBracket = text.indexOf(']', tagIdx);
            if (closeBracket != -1) {
              tagLen = closeBracket - tagIdx + 1;
              break;
            }
            searchFrom = tagIdx - 1;
          }
        }
      }
      if (tagIdx == -1) return false;
      final exitIdx = text.indexOf(close, tagIdx + tagLen);
      return exitIdx != -1 && exitIdx >= p;
    }

    // Check at multiple points for robustness
    if (checkAt(start)) return true;
    if (checkAt(end)) return true;
    if (checkAt(mid)) return true;
    // Check nearby positions to handle invisible tag characters
    for (int d = 1; d <= open.length + 2; d++) {
      if (start - d >= 0 && checkAt(start - d)) return true;
      if (start + d <= text.length && checkAt(start + d)) return true;
    }
    return false;
  }

  /// Remove or surgically split the enclosing open/close tag pair.
  /// If the selection covers the entire styled content, removes both tags.
  /// If the selection is a subset, splits: keeps style on the unselected
  /// portions and removes it only from the selected portion.
  _StripResult? _removeEnclosingStyle(String text, int selStart, int selEnd, String open, String close) {
    int openIdx = -1;
    int closeIdx = -1;

    if (open == '**' && close == '**') {
      // Find the opening ** before or at selStart (backward search)
      for (int i = selStart; i >= 0; i--) {
        final idx = text.lastIndexOf('**', i);
        if (idx == -1) break;
        final countBefore = RegExp(r'\*\*').allMatches(text.substring(0, idx)).length;
        if (countBefore % 2 == 0) {
          openIdx = idx;
          break;
        }
        i = idx - 1;
        if (i < 0) break;
      }
      // Fallback: forward search (for nested tags where ** is after selStart)
      if (openIdx == -1) {
        for (final m in RegExp(r'\*\*').allMatches(text)) {
          final countBefore = RegExp(r'\*\*').allMatches(text.substring(0, m.start)).length;
          if (countBefore % 2 == 0) {
            openIdx = m.start;
            break;
          }
        }
      }
      if (openIdx == -1) return null;
      closeIdx = text.indexOf('**', openIdx + 2);
      if (closeIdx == -1) return null;
    } else {
      // For bracketed tags like [u]...[/u], [i]...[/i], [bg=#hex]...[/bg]
      // Try exact match first, then family-based search for parameterized tags
      String effectiveOpen = open;

      // Backward search from selStart
      for (int i = selStart; i >= 0; i--) {
        int idx = text.lastIndexOf(open, i);
        // If exact match fails, try family-based search (e.g., [bg= for [bg=#FF0000])
        if (idx == -1) {
          final familyMatch = RegExp(r'^\[(\w+)=').firstMatch(open);
          if (familyMatch != null) {
            final pattern = '[${familyMatch.group(1)!}=';
            idx = text.lastIndexOf(pattern, i);
            if (idx != -1) {
              final closeBracket = text.indexOf(']', idx);
              if (closeBracket != -1) {
                effectiveOpen = text.substring(idx, closeBracket + 1);
              } else {
                idx = -1;
              }
            }
          }
        }
        if (idx == -1) break;
        final matchClose = text.indexOf(close, idx + effectiveOpen.length);
        if (matchClose != -1 && matchClose >= selEnd - close.length) {
          openIdx = idx;
          break;
        }
        i = idx - 1;
        if (i < 0) break;
      }
      // Fallback: forward search
      if (openIdx == -1) {
        int idx = text.indexOf(open);
        if (idx == -1) {
          final familyMatch = RegExp(r'^\[(\w+)=').firstMatch(open);
          if (familyMatch != null) {
            final pattern = '[${familyMatch.group(1)!}=';
            idx = text.indexOf(pattern);
            if (idx != -1) {
              final closeBracket = text.indexOf(']', idx);
              if (closeBracket != -1) {
                effectiveOpen = text.substring(idx, closeBracket + 1);
              } else {
                idx = -1;
              }
            }
          }
        }
        if (idx != -1) {
          final matchClose = text.indexOf(close, idx + effectiveOpen.length);
          if (matchClose != -1) {
            openIdx = idx;
          }
        }
      }
      if (openIdx == -1) return null;
      closeIdx = text.indexOf(close, openIdx + effectiveOpen.length);
      if (closeIdx == -1) return null;
      // Use the effective (actual) open tag for length calculations
      open = effectiveOpen;
    }

    final oLen = open.length;
    final cLen = close.length;
    final contentStart = openIdx + oLen; // first char of styled content
    final contentEnd = closeIdx;         // last char + 1 of styled content

    // Clamp selection to content boundaries (selection may overlap tag chars)
    final effStart = selStart.clamp(contentStart, contentEnd);
    final effEnd = selEnd.clamp(contentStart, contentEnd);

    // Content portions relative to clamped selection
    final beforeContent = text.substring(contentStart, effStart);
    final selectedContent = text.substring(effStart, effEnd);
    final afterContent = text.substring(effEnd, contentEnd);

    // If selection covers ALL styled content (or is collapsed), remove tags entirely
    if (effStart <= contentStart && effEnd >= contentEnd) {
      final newText = text.substring(0, openIdx) +
          text.substring(contentStart, contentEnd) +
          text.substring(closeIdx + cLen);
      final newStart = (effStart - oLen).clamp(0, newText.length);
      final newEnd = (effEnd - oLen).clamp(0, newText.length);
      return _StripResult(newText, newStart, newEnd);
    }

    // Surgical split: re-wrap only the portions that should keep style
    final buf = StringBuffer();
    buf.write(text.substring(0, openIdx));

    // Track where the unstyled selection starts in the new string
    int newSelStart;
    int newSelEnd;

    if (beforeContent.isNotEmpty) {
      buf.write(open);
      buf.write(beforeContent);
      buf.write(close);
    }
    newSelStart = buf.length;
    buf.write(selectedContent);
    newSelEnd = buf.length;
    if (afterContent.isNotEmpty) {
      buf.write(open);
      buf.write(afterContent);
      buf.write(close);
    }

    buf.write(text.substring(closeIdx + cLen));

    return _StripResult(buf.toString(), newSelStart, newSelEnd);
  }
}

class _StripResult {
  final String text;
  final int newStart;
  final int newEnd;
  _StripResult(this.text, this.newStart, this.newEnd);
}
