part of 'script_provider.dart';

/// Resolves the representable Word styles without consulting app preferences.
/// Paragraph-mark rPr formats the pilcrow, never the visible paragraph text.
class _DocxStyleResolver {
  final Map<String, XmlElement> _styles = {};
  final Map<String, String> _defaults = {};
  final Map<String, List<XmlElement>> _chains = {};
  final XmlElement? _runDefaults;
  final XmlElement? _paragraphDefaults;

  _DocxStyleResolver(XmlElement? styles)
    : _runDefaults = styles
          ?.getElement('w:docDefaults')
          ?.getElement('w:rPrDefault')
          ?.getElement('w:rPr'),
      _paragraphDefaults = styles
          ?.getElement('w:docDefaults')
          ?.getElement('w:pPrDefault')
          ?.getElement('w:pPr') {
    if (styles == null) return;
    for (final style in styles.findElements('w:style')) {
      final id = _attr(style, 'styleId');
      final type = _attr(style, 'type');
      if (id == null || (type != 'paragraph' && type != 'character')) continue;
      _styles['$type:$id'] = style;
      if (['1', 'true', 'on'].contains(_attr(style, 'default'))) {
        _defaults[type!] = id;
      }
    }
  }

  static String? _attr(XmlElement element, String name) =>
      _ScriptProviderDocxParsing._docxAttr(element, name);

  List<XmlElement> _chain(String type, String? requested) {
    final id =
        requested != null && _styles.containsKey('$type:$requested')
            ? requested
            : _defaults[type];
    if (id == null) return const [];
    return _chains.putIfAbsent('$type:$id', () {
      final result = <XmlElement>[];
      final seen = <String>{};
      var current = id;
      // Damaged/cyclic styles cannot hang import or exhaust the call stack.
      while (seen.add(current) && result.length < 64) {
        final style = _styles['$type:$current'];
        if (style == null) break;
        result.add(style);
        final basedOn = style.getElement('w:basedOn');
        final parent = basedOn == null ? null : _attr(basedOn, 'val');
        if (parent == null) break;
        current = parent;
      }
      return result.reversed.toList(growable: false);
    });
  }

  List<XmlElement> _paragraphChain(XmlElement paragraph) {
    final style = paragraph.getElement('w:pPr')?.getElement('w:pStyle');
    return _chain('paragraph', style == null ? null : _attr(style, 'val'));
  }

  XmlElement paragraphProperties(XmlElement paragraph) {
    final properties = _DocxPropertySet();
    properties.add(_paragraphDefaults);
    for (final style in _paragraphChain(paragraph)) {
      properties.add(style.getElement('w:pPr'));
    }
    properties.add(paragraph.getElement('w:pPr'));
    return properties.element('pPr');
  }

  XmlElement runProperties(XmlElement paragraph, XmlElement run) {
    final properties = _DocxPropertySet();
    properties.add(_runDefaults);
    for (final style in _paragraphChain(paragraph)) {
      properties.add(style.getElement('w:rPr'), toggle: true);
    }
    final direct = run.getElement('w:rPr');
    final characterStyle = direct?.getElement('w:rStyle');
    for (final style in _chain(
      'character',
      characterStyle == null ? null : _attr(characterStyle, 'val'),
    )) {
      properties.add(style.getElement('w:rPr'), toggle: true);
    }
    properties.add(direct);
    return properties.element('rPr');
  }

  XmlElement numberingRunProperties(
    XmlElement paragraph,
    XmlElement? levelProperties,
  ) {
    // List labels inherit document/paragraph and paragraph-mark typography,
    // not the first text run's incidental size/font. Explicit level typography
    // is scoped to the label; paragraph-mark properties never leak into text.
    final mark = paragraph.getElement('w:pPr')?.getElement('w:rPr');
    final markRun = XmlElement(XmlName('r', 'w'), [], [
      if (mark != null) mark.copy(),
    ]);
    final properties = _DocxPropertySet();
    properties.add(runProperties(paragraph, markRun));
    properties.add(levelProperties);
    return properties.element('rPr');
  }
}

class _DocxPropertySet {
  final Map<String, XmlElement> _values = {};
  static const _toggles = {'b', 'bCs', 'i', 'iCs'};

  void add(XmlElement? properties, {bool toggle = false}) {
    if (properties == null) return;
    for (final property in properties.childElements) {
      final name = property.name.local;
      if (name == 'rPr' || name == 'rPrChange' || name == 'pPrChange') continue;
      if (toggle && _toggles.contains(name)) {
        // In styles, true toggles the inherited state; false leaves it alone.
        // Direct run properties (toggle=false) are absolute on/off overrides.
        if (!_ScriptProviderDocxParsing._docxBoolOn(property)) continue;
        final previous = _values[name];
        final wasOn =
            previous != null &&
            _ScriptProviderDocxParsing._docxBoolOn(previous);
        _values[name] = XmlElement(XmlName(name, 'w'), [
          XmlAttribute(XmlName('val', 'w'), wasOn ? '0' : '1'),
        ]);
      } else if (name == 'rFonts' && _values.containsKey(name)) {
        final merged = _values[name]!.copy();
        for (final attribute in property.attributes) {
          final key = attribute.name.local;
          merged.setAttribute('w:$key', attribute.value);
          // A directly supplied family replaces an inherited theme reference.
          if (['ascii', 'hAnsi', 'cs', 'eastAsia'].contains(key)) {
            merged.removeAttribute(
              'w:${key == 'cs' ? 'cstheme' : '${key}Theme'}',
            );
          }
        }
        _values[name] = merged;
      } else {
        _values[name] = property.copy();
      }
    }
  }

  XmlElement element(String name) => XmlElement(
    XmlName(name, 'w'),
    [],
    _values.values.map((value) => value.copy()),
  );
}

extension _ScriptProviderDocxStyles on ScriptNotifier {
  _DocxStyleResolver _docxStylesFromArchive(Archive archive) {
    final entry =
        archive.findFile('word/styles.xml') ??
        archive.findFile('word/Styles.xml');
    if (entry == null) return _DocxStyleResolver(null);
    // Use the same XML-size/archive limits as document.xml. Malformed styles
    // must report an import error rather than silently claim correct metadata.
    final bytes = _archiveFileBytes(entry, format: 'DOCX', isXml: true);
    return _DocxStyleResolver(
      XmlDocument.parse(utf8.decode(bytes)).rootElement,
    );
  }
}
