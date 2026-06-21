class MarkupExportService {
  MarkupExportService._();

  static final RegExp _tagRegex = RegExp(
    r'\*\*'
    r'|\[\/?u\]'
    r'|\[\/?i\]'
    r'|\[color=([^\]]+)\]|\[\/color\]'
    r'|\[bg=([^\]]+)\]|\[\/bg\]'
    r'|\[size=(\d+(?:\.\d+)?)\]|\[\/size\]'
    r'|\[font=([^\]]+)\]|\[\/font\]'
    r'|\[align=(center|left|right)\]|\[\/align(?:=(?:center|left|right))?\]'
    r'|\[(center|left|right)\]|\[\/(?:center|left|right)\]'
    r'|\[rtl\]|\[\/rtl\]|\[ltr\]|\[\/ltr\]'
    r'|\[(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc)\]'
    r'|\[\/(?:y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc)\]',
  );

  static const _shorthandHighlightColors = <String, String>{
    'y': 'FFD700',
    'r': 'FF4444',
    'g': '44DD44',
    'b': '4488FF',
    'o': 'FFA500',
    'p': 'AA44FF',
    'c': '44DDDD',
    'pk': 'FF44AA',
  };

  static const _shorthandTextColors = <String, String>{
    'yc': 'FFD700',
    'rc': 'FF4444',
    'gc': '44DD44',
    'bc': '4488FF',
    'oc': 'FFA500',
    'pc': 'AA44FF',
    'cc': '44DDDD',
    'pkc': 'FF44AA',
  };

  static List<ExportParagraph> parse(String markup, {bool? defaultRtl}) {
    return markup
        .split('\n')
        .map((paragraph) => _parseParagraph(
              paragraph,
              defaultRtl: defaultRtl,
            ))
        .toList();
  }

  static String toPlainText(String markup, {bool? defaultRtl}) {
    return parse(markup, defaultRtl: defaultRtl)
        .map((paragraph) => paragraph.runs.map((run) => run.text).join())
        .join('\n');
  }

  static String toDirectionalPlainText(String markup, {bool? defaultRtl}) {
    return parse(markup, defaultRtl: defaultRtl).map((paragraph) {
      final text = paragraph.runs.map((run) => run.text).join();
      if (!paragraph.isRtl || text.trim().isEmpty) return text;
      return BidiExportMarks.wrap(text, rtl: true);
    }).join('\n');
  }

  static List<ExportDirectionalRun> directionalRuns(
    ExportParagraph paragraph,
  ) {
    final result = <ExportDirectionalRun>[];
    for (final run in paragraph.runs) {
      result.addAll(splitDirectionalRun(run, paragraph.isRtl));
    }
    return result;
  }

  static List<ExportDirectionalRun> documentRuns(
    ExportParagraph paragraph,
  ) {
    return directionalRuns(paragraph)
        .where((run) => run.text.isNotEmpty)
        .toList(growable: false);
  }

  static List<ExportDirectionalRun> splitDirectionalRun(
    ExportTextRun run,
    bool paragraphRtl,
  ) {
    if (run.text.isEmpty) return const [];
    final result = <ExportDirectionalRun>[];
    final buffer = StringBuffer();
    final pendingNeutral = StringBuffer();
    var currentRtl = paragraphRtl;
    var hasStrong = false;

    void emit({bool includePendingNeutral = true}) {
      if (includePendingNeutral &&
          pendingNeutral.isNotEmpty &&
          buffer.isNotEmpty) {
        buffer.write(pendingNeutral);
        pendingNeutral.clear();
      }
      final text = buffer.toString();
      if (text.isEmpty) return;
      result.add(ExportDirectionalRun(run: run, text: text, isRtl: currentRtl));
      buffer.clear();
      hasStrong = false;
    }

    for (final rune in run.text.runes) {
      final direction = strongRtlForRune(rune);
      final char = String.fromCharCodes([rune]);
      if (direction == null) {
        pendingNeutral.write(char);
        continue;
      }
      if (!hasStrong) {
        currentRtl = direction;
        buffer.write(pendingNeutral);
        pendingNeutral.clear();
        buffer.write(char);
        hasStrong = true;
        continue;
      }
      if (direction != currentRtl) {
        emit(includePendingNeutral: currentRtl == paragraphRtl);
        currentRtl = direction;
      }
      buffer.write(pendingNeutral);
      pendingNeutral.clear();
      buffer.write(char);
      hasStrong = true;
    }

    if (buffer.isEmpty && pendingNeutral.isNotEmpty) {
      currentRtl = paragraphRtl;
      buffer.write(pendingNeutral);
      pendingNeutral.clear();
    }
    emit();
    return result;
  }

  static bool? strongRtlForRune(int rune) {
    if ((rune >= 0x0590 && rune <= 0x05FF) ||
        (rune >= 0x0600 && rune <= 0x06FF) ||
        (rune >= 0x0750 && rune <= 0x077F)) {
      return true;
    }
    if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A) ||
        (rune >= 0x0030 && rune <= 0x0039)) {
      return false;
    }
    return null;
  }

  static ExportParagraph _parseParagraph(String markup, {bool? defaultRtl}) {
    String align = 'left';
    bool hasExplicitAlign = false;
    bool isRtl = false;
    bool hasExplicitDirection = false;
    bool bold = false;
    bool italic = false;
    bool underline = false;
    final colors = <String>[];
    final backgrounds = <String>[];
    final sizes = <double>[];
    final fonts = <String>[];
    final runs = <ExportTextRun>[];

    void emit(String text) {
      if (text.isEmpty) return;
      runs.add(ExportTextRun(
        text: text,
        isBold: bold,
        isItalic: italic,
        isUnderline: underline,
        color: colors.isEmpty ? null : _normalizeColor(colors.last),
        backgroundColor:
            backgrounds.isEmpty ? null : _normalizeColor(backgrounds.last),
        fontSize: sizes.isEmpty ? null : sizes.last,
        fontFamily: fonts.isEmpty ? null : fonts.last,
      ));
    }

    int cursor = 0;
    for (final match in _tagRegex.allMatches(markup)) {
      if (match.start > cursor) {
        emit(markup.substring(cursor, match.start));
      }
      final tag = match.group(0)!;
      if (tag == '**') {
        bold = !bold;
      } else if (tag == '[u]') {
        underline = true;
      } else if (tag == '[/u]') {
        underline = false;
      } else if (tag == '[i]') {
        italic = true;
      } else if (tag == '[/i]') {
        italic = false;
      } else if (match.group(1) != null) {
        colors.add(match.group(1)!);
      } else if (tag == '[/color]') {
        if (colors.isNotEmpty) colors.removeLast();
      } else if (match.group(2) != null) {
        backgrounds.add(match.group(2)!);
      } else if (tag == '[/bg]') {
        if (backgrounds.isNotEmpty) backgrounds.removeLast();
      } else if (match.group(3) != null) {
        final size = double.tryParse(match.group(3)!);
        if (size != null) sizes.add(size);
      } else if (tag == '[/size]') {
        if (sizes.isNotEmpty) sizes.removeLast();
      } else if (match.group(4) != null) {
        fonts.add(match.group(4)!);
      } else if (tag == '[/font]') {
        if (fonts.isNotEmpty) fonts.removeLast();
      } else if (match.group(5) != null) {
        align = match.group(5)!;
        hasExplicitAlign = true;
      } else if (match.group(6) != null) {
        align = match.group(6)!;
        hasExplicitAlign = true;
      } else if (tag == '[rtl]') {
        isRtl = true;
        hasExplicitDirection = true;
      } else if (tag == '[ltr]') {
        isRtl = false;
        hasExplicitDirection = true;
      } else if (match.group(7) != null) {
        final shorthand = match.group(7)!;
        final highlight = _shorthandHighlightColors[shorthand];
        final textColor = _shorthandTextColors[shorthand];
        if (highlight != null) {
          backgrounds.add(highlight);
        } else if (textColor != null) {
          colors.add(textColor);
        }
      } else if (RegExp(
        r'^\[/(?:y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc)\]$',
      ).hasMatch(tag)) {
        final shorthand = tag.substring(2, tag.length - 1);
        if (_shorthandHighlightColors.containsKey(shorthand)) {
          if (backgrounds.isNotEmpty) backgrounds.removeLast();
        } else if (colors.isNotEmpty) {
          colors.removeLast();
        }
      }
      cursor = match.end;
    }
    if (cursor < markup.length) {
      emit(markup.substring(cursor));
    }
    if (!hasExplicitDirection) {
      final plainText = runs.map((run) => run.text).join();
      isRtl = _paragraphRtl(plainText, defaultRtl: defaultRtl);
    }
    return ExportParagraph(
      align: align,
      hasExplicitAlign: hasExplicitAlign,
      isRtl: isRtl,
      runs: runs,
    );
  }

  static String? _normalizeColor(String raw) {
    final hex = raw.trim().replaceFirst('#', '').toUpperCase();
    if (hex.length == 8) return hex.substring(2);
    if (hex.length == 6) return hex;
    return null;
  }

  static bool _looksRtl(String text) {
    var rtl = 0;
    var ltr = 0;
    for (final rune in text.runes) {
      if ((rune >= 0x0590 && rune <= 0x05FF) ||
          (rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F)) {
        rtl++;
      } else if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
        ltr++;
      }
    }
    return rtl > 0 && rtl >= ltr;
  }

  static bool _paragraphRtl(String text, {bool? defaultRtl}) {
    for (final rune in text.runes) {
      final strongDirection = strongRtlForRune(rune);
      if (strongDirection != null) return strongDirection;
    }
    if (defaultRtl == true && _hasRtl(text)) {
      return true;
    }
    if (defaultRtl == false && _hasLtr(text) && !_hasRtl(text)) {
      return false;
    }
    return _looksRtl(text);
  }

  static bool _hasRtl(String text) {
    for (final rune in text.runes) {
      if (strongRtlForRune(rune) == true) return true;
    }
    return false;
  }

  static bool _hasLtr(String text) {
    for (final rune in text.runes) {
      if (strongRtlForRune(rune) == false) return true;
    }
    return false;
  }
}

class BidiExportMarks {
  BidiExportMarks._();

  static const rle = '\u202B';
  static const lre = '\u202A';
  static const pdf = '\u202C';
  static const rlm = '\u200F';
  static const rtlOpen = '$rlm$rle';
  static const rtlClose = '$pdf$rlm';
  static const ltrOpen = lre;
  static const ltrClose = pdf;

  static String wrap(String text, {required bool rtl}) {
    if (text.isEmpty) return text;
    return rtl ? '$rtlOpen$text$rtlClose' : '$ltrOpen$text$ltrClose';
  }

  static String markPlain(String text, {required bool rtl}) {
    if (text.isEmpty || !rtl) return text;
    return '$rlm$text';
  }
}

class ExportParagraph {
  final String align;
  final bool hasExplicitAlign;
  final bool isRtl;
  final List<ExportTextRun> runs;

  const ExportParagraph({
    required this.align,
    this.hasExplicitAlign = false,
    this.isRtl = false,
    required this.runs,
  });

  bool get isEmpty => runs.every((run) => run.text.isEmpty);
}

class ExportTextRun {
  final String text;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final String? color;
  final String? backgroundColor;
  final double? fontSize;
  final String? fontFamily;

  const ExportTextRun({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.color,
    this.backgroundColor,
    this.fontSize,
    this.fontFamily,
  });
}

class ExportDirectionalRun {
  final ExportTextRun run;
  final String text;
  final bool isRtl;

  const ExportDirectionalRun({
    required this.run,
    required this.text,
    required this.isRtl,
  });
}
