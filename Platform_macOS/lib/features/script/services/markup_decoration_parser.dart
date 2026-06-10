part of 'markup_decoration_service.dart';

enum MarkupDecorationType { background, underline }

class MarkupDecorationRange {
  final MarkupDecorationType type;
  final int start;
  final int end;
  final Color? color;

  const MarkupDecorationRange({
    required this.type,
    required this.start,
    required this.end,
    this.color,
  });

  bool get isValid => end > start;
}

class MarkupDecorationParser {
  static final RegExp tagRegex = RegExp(
    r'\*\*'
    r'|\[\/?u\]'
    r'|\[\/?i\]'
    r'|\[color=([^\]]+)\]|\[\/color\]'
    r'|\[bg=([^\]]+)\]|\[\/bg\]'
    r'|\[size=(\d+(?:\.\d+)?)\]|\[\/size\]'
    r'|\[font=([^\]]+)\]|\[\/font\]'
    r'|\[align=(center|left|right)\]|\[\/align(?:=(?:center|left|right))?\]'
    r'|\[(center|left|right)\]|\[\/(?:center|left|right)\]'
    r'|\[rtl\]|\[\/rtl\]|\[ltr\]|\[\/ltr\]',
  );

  static List<MarkupDecorationRange> decorationRanges(String rawText) {
    final ranges = <MarkupDecorationRange>[];
    var cursor = 0;
    var underline = false;
    final backgroundStack = <Color>[];

    void emit(int start, int end) {
      if (end <= start) return;
      if (backgroundStack.isNotEmpty) {
        ranges.add(MarkupDecorationRange(
          type: MarkupDecorationType.background,
          start: start,
          end: end,
          color: backgroundStack.last,
        ));
      }
      if (underline) {
        ranges.add(MarkupDecorationRange(
          type: MarkupDecorationType.underline,
          start: start,
          end: end,
        ));
      }
    }

    for (final m in tagRegex.allMatches(rawText)) {
      emit(cursor, m.start);
      final tag = m.group(0)!;
      if (tag == '[u]') {
        underline = true;
      } else if (tag == '[/u]') {
        underline = false;
      } else if (m.group(2) != null) {
        final color = parseHexColor(m.group(2)!);
        if (color != null) backgroundStack.add(color);
      } else if (tag == '[/bg]') {
        if (backgroundStack.isNotEmpty) backgroundStack.removeLast();
      }
      cursor = m.end;
    }
    emit(cursor, rawText.length);
    return ranges.where((range) => range.isValid).toList(growable: false);
  }

  static String visibleText(String rawText) => rawText.replaceAll(tagRegex, '');

  static TextSpan visibleTextSpan(
    String rawText, {
    TextStyle? style,
  }) {
    bool bold = false;
    bool italic = false;
    final textColors = <Color>[];
    final sizes = <double>[];
    final fonts = <String>[];
    final children = <InlineSpan>[];

    TextStyle currentStyle() {
      var next = style ?? const TextStyle();
      if (bold) next = next.copyWith(fontWeight: FontWeight.bold);
      if (italic) next = next.copyWith(fontStyle: FontStyle.italic);
      if (textColors.isNotEmpty) {
        next = next.copyWith(color: textColors.last);
      }
      if (sizes.isNotEmpty) next = next.copyWith(fontSize: sizes.last);
      if (fonts.isNotEmpty) next = next.copyWith(fontFamily: fonts.last);
      return next;
    }

    void emitContent(int start, int end) {
      if (start >= end) return;
      children.add(TextSpan(
        text: rawText.substring(start, end),
        style: currentStyle(),
      ));
    }

    var cursor = 0;
    for (final m in tagRegex.allMatches(rawText)) {
      emitContent(cursor, m.start);
      final tag = m.group(0)!;
      if (tag == '**') {
        bold = !bold;
      } else if (tag == '[i]') {
        italic = true;
      } else if (tag == '[/i]') {
        italic = false;
      } else if (m.group(1) != null) {
        final color = parseHexColor(m.group(1)!);
        if (color != null) textColors.add(color);
      } else if (tag == '[/color]') {
        if (textColors.isNotEmpty) textColors.removeLast();
      } else if (m.group(3) != null) {
        final size = double.tryParse(m.group(3)!);
        if (size != null) sizes.add(size);
      } else if (tag == '[/size]') {
        if (sizes.isNotEmpty) sizes.removeLast();
      } else if (m.group(4) != null) {
        fonts.add(m.group(4)!);
      } else if (tag == '[/font]') {
        if (fonts.isNotEmpty) fonts.removeLast();
      }
      cursor = m.end;
    }
    emitContent(cursor, rawText.length);
    return TextSpan(style: style, children: children);
  }

  static TextSelection rawToVisibleSelection(
    String rawText,
    TextSelection rawSelection,
  ) {
    final start = rawToVisibleOffset(rawText, rawSelection.start);
    final end = rawToVisibleOffset(rawText, rawSelection.end);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  static TextRange? paintableContentRange(
    String rawText,
    MarkupDecorationRange range,
  ) {
    var start = range.start.clamp(0, rawText.length).toInt();
    var end = range.end.clamp(start, rawText.length).toInt();
    while (start < end && _isDecorationWhitespace(rawText.codeUnitAt(start))) {
      start++;
    }
    while (
        end > start && _isDecorationWhitespace(rawText.codeUnitAt(end - 1))) {
      end--;
    }
    if (end <= start) return null;
    return TextRange(start: start, end: end);
  }

  static bool _isDecorationWhitespace(int codeUnit) =>
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D ||
      codeUnit == 0x20 ||
      codeUnit == 0xA0;

  static int rawToVisibleOffset(String rawText, int rawOffset) {
    final clamped = rawOffset.clamp(0, rawText.length);
    var visible = 0;
    var cursor = 0;
    for (final m in tagRegex.allMatches(rawText)) {
      if (m.start >= clamped) break;
      if (m.start > cursor) {
        visible += (m.start.clamp(0, clamped) - cursor).toInt();
      }
      cursor = m.end;
    }
    if (cursor < clamped) visible += clamped - cursor;
    return visible;
  }

  static int visibleToRawOffset(String rawText, int visibleOffset) {
    final target = visibleOffset < 0 ? 0 : visibleOffset;
    var visible = 0;
    var cursor = 0;
    for (final m in tagRegex.allMatches(rawText)) {
      if (m.start > cursor) {
        final segmentLength = m.start - cursor;
        if (visible + segmentLength >= target) {
          return cursor + target - visible;
        }
        visible += segmentLength;
      }
      cursor = m.end;
    }
    if (cursor < rawText.length) {
      final segmentLength = rawText.length - cursor;
      if (visible + segmentLength >= target) {
        return cursor + target - visible;
      }
    }
    return rawText.length;
  }

  static Color? parseHexColor(String raw) {
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}
