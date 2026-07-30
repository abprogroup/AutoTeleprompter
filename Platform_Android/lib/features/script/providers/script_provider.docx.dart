part of 'script_provider.dart';

mixin ScriptNotifierDocxImport on Notifier<Script?> {
  _ParsedFile _parseDocx(List<int> rawBytes) {
    final archive = ZipDecoder().decodeBytes(rawBytes);
    double? detectedFontSize;

    // Find document.xml — try common paths
    ArchiveFile? docEntry;
    for (final candidate in ['word/document.xml', 'word/Document.xml']) {
      docEntry = archive.findFile(candidate);
      if (docEntry != null) break;
    }
    if (docEntry == null) {
      for (final f in archive.files) {
        if (f.name.toLowerCase().endsWith('document.xml')) {
          docEntry = f;
          break;
        }
      }
    }
    if (docEntry == null) throw Exception('No document.xml in DOCX');

    // Get bytes safely — archive 3.x content can be List<int> or InputStream
    final dynamic rawContent = docEntry.content;
    final List<int> bytes;
    if (rawContent is List<int>) {
      bytes = rawContent;
    } else {
      bytes = List<int>.from(rawContent);
    }

    final xmlStr = utf8.decode(bytes, allowMalformed: true);
    final document = XmlDocument.parse(xmlStr);
    final paragraphs = document.findAllElements('w:p').toList();
    final numbering = _docxNumberingFromArchive(archive);
    final buf = StringBuffer();

    for (final p in paragraphs) {
      final paragraph = StringBuffer();
      for (final r in p.findAllElements('w:r')) {
        final rPr = r.getElement('w:rPr');
        final textNode = r.getElement('w:t');
        if (textNode == null) continue;

        String text = textNode.innerText;
        if (text.isEmpty) continue;

        if (rPr != null) {
          final isBold = rPr.getElement('w:b') != null;
          final color = rPr.getElement('w:color')?.getAttribute('w:val');

          if (detectedFontSize == null) {
            final sz = rPr.getElement('w:sz')?.getAttribute('w:val') ??
                rPr.getElement('w:szCs')?.getAttribute('w:val');
            if (sz != null) {
              final halfPoints = double.tryParse(sz);
              if (halfPoints != null) detectedFontSize = halfPoints / 2.0;
            }
          }

          if (color != null && color != 'auto') {
            text = '[color=#$color]$text[/color]';
          }
          if (isBold) {
            text = '**$text**';
          }
        }
        paragraph.write(text);
      }

      final listLabel = numbering.labelForParagraph(p);
      if (listLabel != null && paragraph.toString().trim().isNotEmpty) {
        buf.write('$listLabel ');
      }
      buf.write(paragraph.toString());
      buf.write('\n');
    }

    // Background color detection
    try {
      final background = document.rootElement.getElement('w:background');
      final bgColorVal = background?.getAttribute('w:color');
      if (bgColorVal != null && bgColorVal != 'auto') {
        final colorInt = int.parse('FF$bgColorVal', radix: 16);
        ref.read(settingsProvider.notifier).setScriptBgColor(colorInt);
      } else if (paragraphs.isNotEmpty) {
        final shd = paragraphs.first
            .getElement('w:pPr')
            ?.getElement('w:shd')
            ?.getAttribute('w:fill');
        if (shd != null && shd != 'auto' && shd != 'clear') {
          final colorInt = int.parse('FF$shd', radix: 16);
          ref.read(settingsProvider.notifier).setScriptBgColor(colorInt);
        }
      }
    } catch (_) {}

    return _ParsedFile(buf.toString().trim(), fontSize: detectedFontSize);
  }
}
