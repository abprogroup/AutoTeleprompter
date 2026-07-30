part of 'script_provider.dart';

_DocxNumberingResolver _docxNumberingFromArchive(Archive archive) {
  final entry = archive.findFile('word/numbering.xml') ??
      archive.findFile('word/Numbering.xml');
  if (entry == null) return _DocxNumberingResolver.empty();
  try {
    final dynamic rawContent = entry.content;
    final List<int> bytes =
        rawContent is List<int> ? rawContent : List<int>.from(rawContent);
    return _DocxNumberingResolver.fromXmlBytes(bytes);
  } catch (_) {
    return _DocxNumberingResolver.empty();
  }
}

const String _docxNumberingNamespace =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String? _docxNumberingAttr(XmlElement? element, String name) {
  if (element == null) return null;
  return element.getAttribute('w:$name') ??
      element.getAttribute(name) ??
      element.getAttribute(name, namespace: _docxNumberingNamespace);
}

class _DocxNumberingResolver {
  final Map<int, Map<int, _DocxNumberLevel>> abstractLevels;
  final Map<int, int> numToAbstract;
  final Map<int, Map<int, _DocxNumberLevel>> numOverrides;
  final Map<int, Map<int, int>> counters = {};

  _DocxNumberingResolver({
    required this.abstractLevels,
    required this.numToAbstract,
    required this.numOverrides,
  });

  factory _DocxNumberingResolver.fromXmlBytes(List<int> bytes) {
    try {
      final document =
          XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
      return _DocxNumberingResolver(
        abstractLevels: _parseAbstractLevels(document),
        numToAbstract: _parseNumMappings(document),
        numOverrides: _parseNumOverrides(document),
      );
    } catch (_) {
      return _DocxNumberingResolver.empty();
    }
  }

  factory _DocxNumberingResolver.empty() => _DocxNumberingResolver(
        abstractLevels: const {},
        numToAbstract: const {},
        numOverrides: const {},
      );

  String? labelForParagraph(XmlElement paragraph) {
    final numPr = paragraph.getElement('w:pPr')?.getElement('w:numPr');
    if (numPr == null) return null;
    final numId = _docxNumberingIntAttr(numPr.getElement('w:numId'), 'val');
    if (numId == null) return null;
    final level = _docxNumberingIntAttr(numPr.getElement('w:ilvl'), 'val') ?? 0;
    final effective = _levelFor(numId, level);
    if (effective == null || effective.format == 'none') return null;

    final current = _advanceCounter(numId, level, effective.start);
    return _formatLabel(numId, level, current, effective);
  }

  _DocxNumberLevel? _levelFor(int numId, int level) {
    final override = numOverrides[numId]?[level];
    if (override != null) return override;
    final abstractId = numToAbstract[numId];
    if (abstractId == null) return null;
    return abstractLevels[abstractId]?[level] ??
        const _DocxNumberLevel(start: 1, format: 'decimal', text: '%1.');
  }

  int _advanceCounter(int numId, int level, int start) {
    final levels = counters.putIfAbsent(numId, () => {});
    final current = levels[level];
    final next = current == null || current == 0 ? start : current + 1;
    levels[level] = next;
    for (final key in levels.keys.where((key) => key > level).toList()) {
      levels[key] = 0;
    }
    return next;
  }

  String? _formatLabel(
    int numId,
    int level,
    int current,
    _DocxNumberLevel effective,
  ) {
    final pattern = effective.text.isEmpty ? '%${level + 1}.' : effective.text;
    final label = pattern.replaceAllMapped(RegExp(r'%(\d+)'), (match) {
      final placeholderLevel = (int.tryParse(match.group(1) ?? '') ?? 1) - 1;
      final levelValue = placeholderLevel == level
          ? current
          : counters[numId]?[placeholderLevel] ??
              _levelFor(numId, placeholderLevel)?.start ??
              1;
      final levelFormat =
          _levelFor(numId, placeholderLevel)?.format ?? effective.format;
      return _formatDocxNumber(levelValue, levelFormat);
    }).trim();
    return label.isEmpty ? null : label;
  }

  static Map<int, Map<int, _DocxNumberLevel>> _parseAbstractLevels(
    XmlDocument document,
  ) {
    final result = <int, Map<int, _DocxNumberLevel>>{};
    for (final abstractNum in document.findAllElements('w:abstractNum')) {
      final id = _docxNumberingIntAttr(abstractNum, 'abstractNumId');
      if (id == null) continue;
      final levels = <int, _DocxNumberLevel>{};
      for (final level in abstractNum.findElements('w:lvl')) {
        final ilvl = _docxNumberingIntAttr(level, 'ilvl');
        if (ilvl == null) continue;
        levels[ilvl] = _parseLevel(level);
      }
      result[id] = levels;
    }
    return result;
  }

  static Map<int, int> _parseNumMappings(XmlDocument document) {
    final result = <int, int>{};
    for (final num in document.findAllElements('w:num')) {
      final numId = _docxNumberingIntAttr(num, 'numId');
      final abstractId =
          _docxNumberingIntAttr(num.getElement('w:abstractNumId'), 'val');
      if (numId != null && abstractId != null) result[numId] = abstractId;
    }
    return result;
  }

  static Map<int, Map<int, _DocxNumberLevel>> _parseNumOverrides(
    XmlDocument document,
  ) {
    final result = <int, Map<int, _DocxNumberLevel>>{};
    for (final num in document.findAllElements('w:num')) {
      final numId = _docxNumberingIntAttr(num, 'numId');
      if (numId == null) continue;
      for (final override in num.findElements('w:lvlOverride')) {
        final ilvl = _docxNumberingIntAttr(override, 'ilvl');
        if (ilvl == null) continue;
        final parsedLevel = override.getElement('w:lvl') == null
            ? null
            : _parseLevel(override.getElement('w:lvl')!);
        final start = _docxNumberingIntAttr(
            override.getElement('w:startOverride'), 'val');
        if (parsedLevel != null) {
          result.putIfAbsent(numId, () => {})[ilvl] =
              parsedLevel.copyWith(start: start);
        } else if (start != null) {
          result.putIfAbsent(numId, () => {})[ilvl] =
              _DocxNumberLevel(start: start, format: 'decimal', text: '%1.');
        }
      }
    }
    return result;
  }

  static _DocxNumberLevel _parseLevel(XmlElement level) {
    final start =
        _docxNumberingIntAttr(level.getElement('w:start'), 'val') ?? 1;
    final format =
        _docxNumberingAttr(level.getElement('w:numFmt') ?? level, 'val') ??
            'decimal';
    final text =
        _docxNumberingAttr(level.getElement('w:lvlText') ?? level, 'val') ??
            '%1.';
    return _DocxNumberLevel(start: start, format: format, text: text);
  }

  static int? _docxNumberingIntAttr(XmlElement? element, String attr) {
    if (element == null) return null;
    final value = _docxNumberingAttr(element, attr);
    return int.tryParse(value ?? '');
  }

  static String _formatDocxNumber(int value, String format) {
    return switch (format) {
      'lowerLetter' => _docxNumberingLetters(value).toLowerCase(),
      'upperLetter' => _docxNumberingLetters(value).toUpperCase(),
      'lowerRoman' => _docxNumberingRoman(value).toLowerCase(),
      'upperRoman' => _docxNumberingRoman(value),
      'bullet' => '•',
      _ => value.toString(),
    };
  }

  static String _docxNumberingLetters(int value) {
    if (value <= 0) return value.toString();
    var remaining = value;
    final chars = <String>[];
    while (remaining > 0) {
      remaining--;
      chars.insert(0, String.fromCharCode(0x41 + remaining % 26));
      remaining ~/= 26;
    }
    return chars.join();
  }

  static String _docxNumberingRoman(int value) {
    if (value <= 0 || value > 3999) return value.toString();
    const numerals = [
      (1000, 'M'),
      (900, 'CM'),
      (500, 'D'),
      (400, 'CD'),
      (100, 'C'),
      (90, 'XC'),
      (50, 'L'),
      (40, 'XL'),
      (10, 'X'),
      (9, 'IX'),
      (5, 'V'),
      (4, 'IV'),
      (1, 'I'),
    ];
    var remaining = value;
    final buffer = StringBuffer();
    for (final entry in numerals) {
      while (remaining >= entry.$1) {
        buffer.write(entry.$2);
        remaining -= entry.$1;
      }
    }
    return buffer.toString();
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

  _DocxNumberLevel copyWith({int? start}) => _DocxNumberLevel(
        start: start ?? this.start,
        format: format,
        text: text,
      );
}
