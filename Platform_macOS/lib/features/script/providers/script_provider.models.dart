part of 'script_provider.dart';

class _ParsedFile {
  final String text;
  final double? fontSize;
  _ParsedFile(this.text, {this.fontSize});
}

class _DocxNumberingResolver {
  final Map<String, String> _numToAbstract;
  final Map<String, Map<int, _DocxNumberLevel>> _levels;
  final Map<String, int> _counters = {};

  _DocxNumberingResolver._(this._numToAbstract, this._levels);

  factory _DocxNumberingResolver.empty() => _DocxNumberingResolver._(
      <String, String>{}, <String, Map<int, _DocxNumberLevel>>{});

  static _DocxNumberingResolver fromArchive(Archive archive) {
    final entry = archive.findFile('word/numbering.xml');
    if (entry == null) return _DocxNumberingResolver.empty();
    try {
      final xml =
          utf8.decode(List<int>.from(entry.content), allowMalformed: true);
      final doc = XmlDocument.parse(xml);
      final levels = <String, Map<int, _DocxNumberLevel>>{};
      final numToAbstract = <String, String>{};

      for (final abstractNum in doc.findAllElements('w:abstractNum')) {
        final abstractId =
            ScriptNotifier._docxAttr(abstractNum, 'abstractNumId');
        if (abstractId == null) continue;
        final abstractLevels = <int, _DocxNumberLevel>{};
        for (final lvl in abstractNum.findElements('w:lvl')) {
          final ilvl =
              int.tryParse(ScriptNotifier._docxAttr(lvl, 'ilvl') ?? '0') ?? 0;
          final start = int.tryParse(ScriptNotifier._docxAttr(
                    lvl.getElement('w:start') ?? lvl,
                    'val',
                  ) ??
                  '1') ??
              1;
          final numFmt = ScriptNotifier._docxAttr(
                  lvl.getElement('w:numFmt') ?? lvl, 'val') ??
              'decimal';
          final lvlText = ScriptNotifier._docxAttr(
                  lvl.getElement('w:lvlText') ?? lvl, 'val') ??
              '%${ilvl + 1}.';
          abstractLevels[ilvl] = _DocxNumberLevel(
            start: start,
            format: numFmt,
            text: lvlText,
          );
        }
        levels[abstractId] = abstractLevels;
      }

      for (final num in doc.findAllElements('w:num')) {
        final numId = ScriptNotifier._docxAttr(num, 'numId');
        final abstractIdElement = num.getElement('w:abstractNumId');
        final abstractId = abstractIdElement == null
            ? null
            : ScriptNotifier._docxAttr(abstractIdElement, 'val');
        if (numId != null && abstractId != null) {
          numToAbstract[numId] = abstractId;
        }
      }

      return _DocxNumberingResolver._(numToAbstract, levels);
    } catch (_) {
      return _DocxNumberingResolver.empty();
    }
  }

  String? prefixForParagraph(XmlElement paragraph) {
    final numPr = paragraph.getElement('w:pPr')?.getElement('w:numPr');
    if (numPr == null) return null;
    final numIdElement = numPr.getElement('w:numId');
    final numId = numIdElement == null
        ? null
        : ScriptNotifier._docxAttr(numIdElement, 'val');
    if (numId == null) return null;
    final ilvlElement = numPr.getElement('w:ilvl');
    final ilvl = int.tryParse(
          ilvlElement == null
              ? '0'
              : ScriptNotifier._docxAttr(ilvlElement, 'val') ?? '0',
        ) ??
        0;

    final abstractId = _numToAbstract[numId];
    final level = abstractId == null ? null : _levels[abstractId]?[ilvl];
    final counterKey = '$numId:$ilvl';
    final next = (_counters[counterKey] ?? ((level?.start ?? 1) - 1)) + 1;
    _counters[counterKey] = next;

    final deeperPrefix = '$numId:';
    _counters.removeWhere((key, value) {
      if (!key.startsWith(deeperPrefix)) return false;
      final parts = key.split(':');
      final depth = parts.length > 1 ? int.tryParse(parts[1]) : null;
      return depth != null && depth > ilvl;
    });

    final format = level?.format ?? 'decimal';
    if (format == 'bullet') return 'ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢';

    final pattern = level?.text ?? '%${ilvl + 1}.';
    final rendered = pattern.replaceAllMapped(RegExp(r'%(\d+)'), (match) {
      final depth = (int.tryParse(match.group(1) ?? '1') ?? 1) - 1;
      if (depth == ilvl) return next.toString();
      return _counters['$numId:$depth']?.toString() ?? next.toString();
    });
    return rendered.trim().isEmpty ? '${next.toString()}.' : rendered;
  }
}

class _DocxNumberLevel {
  final int start;
  final String format;
  final String text;

  const _DocxNumberLevel({
    required this.start,
    required this.format,
    required this.text,
  });
}

class _DocxRunStyle {
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final String? color;
  final String? highlightColor;

  const _DocxRunStyle({
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.color,
    this.highlightColor,
  });
}

class _DocxRunSegment {
  final String text;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final String? color;
  final String? highlightColor;

  const _DocxRunSegment(
    this.text, {
    required this.isBold,
    required this.isItalic,
    required this.isUnderline,
    required this.color,
    required this.highlightColor,
  });

  bool sameStyle(_DocxRunSegment other) =>
      isBold == other.isBold &&
      isItalic == other.isItalic &&
      isUnderline == other.isUnderline &&
      color == other.color &&
      highlightColor == other.highlightColor;

  _DocxRunSegment copyWith({required String text}) => _DocxRunSegment(
        text,
        isBold: isBold,
        isItalic: isItalic,
        isUnderline: isUnderline,
        color: color,
        highlightColor: highlightColor,
      );
}

class _RtfRun {
  final String text;
  final bool bold;
  final int cfIndex;
  _RtfRun(this.text, this.bold, this.cfIndex);
}
