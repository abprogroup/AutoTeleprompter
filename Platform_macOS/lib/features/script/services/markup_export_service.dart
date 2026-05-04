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

  static const _shorthandColors = <String, String>{
    'y': 'FFD700',
    'r': 'FF4444',
    'g': '44DD44',
    'b': '4488FF',
    'o': 'FFA500',
    'p': 'AA44FF',
    'c': '44DDDD',
    'pk': 'FF44AA',
    'yc': 'FFD700',
    'rc': 'FF4444',
    'gc': '44DD44',
    'bc': '4488FF',
    'oc': 'FFA500',
    'pc': 'AA44FF',
    'cc': '44DDDD',
    'pkc': 'FF44AA',
  };

  static List<ExportParagraph> parse(String markup) {
    return markup.split('\n').map(_parseParagraph).toList();
  }

  static String toPlainText(String markup) {
    return parse(markup)
        .map((paragraph) => paragraph.runs.map((run) => run.text).join())
        .join('\n');
  }

  static ExportParagraph _parseParagraph(String markup) {
    String align = 'left';
    bool bold = false;
    bool italic = false;
    bool underline = false;
    final colors = <String>[];
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
      } else if (match.group(6) != null) {
        align = match.group(6)!;
      } else if (match.group(7) != null) {
        colors.add(_shorthandColors[match.group(7)!]!);
      } else if (RegExp(
        r'^\[/(?:y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc)\]$',
      ).hasMatch(tag)) {
        if (colors.isNotEmpty) colors.removeLast();
      }
      cursor = match.end;
    }
    if (cursor < markup.length) {
      emit(markup.substring(cursor));
    }
    return ExportParagraph(align: align, runs: runs);
  }

  static String? _normalizeColor(String raw) {
    final hex = raw.trim().replaceFirst('#', '').toUpperCase();
    if (hex.length == 8) return hex.substring(2);
    if (hex.length == 6) return hex;
    return null;
  }
}

class ExportParagraph {
  final String align;
  final List<ExportTextRun> runs;

  const ExportParagraph({
    required this.align,
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
  final double? fontSize;
  final String? fontFamily;

  const ExportTextRun({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.color,
    this.fontSize,
    this.fontFamily,
  });
}
