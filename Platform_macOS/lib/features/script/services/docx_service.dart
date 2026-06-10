import 'dart:convert';

import 'package:archive/archive.dart';

import 'markup_export_service.dart';

class DocxService {
  static const String _documentXmlRel =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<w:body>';
  static const String _documentXmlFooter =
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" '
      'w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>'
      '</w:sectPr></w:body></w:document>';

  static const String _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
      '</Types>';

  static const String _rels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
      '</Relationships>';

  static const String _documentRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>'
      '</Relationships>';

  static const String _stylesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
      '<w:name w:val="Normal"/><w:qFormat/>'
      '<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>'
      '<w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr>'
      '</w:style>'
      '</w:styles>';

  static const String _settingsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:defaultTabStop w:val="720"/>'
      '<w:themeFontLang w:val="en-US" w:bidi="he-IL"/>'
      '<w:compat/>'
      '</w:settings>';

  static const String _appXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
      'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
      '<Application>AutoTeleprompter</Application>'
      '</Properties>';

  /// Converts internal markup to styled DOCX bytes.
  static List<int> generate(String text, {bool? defaultRtl}) {
    final archive = Archive();
    final contentTypeBytes = utf8.encode(_contentTypes);
    archive.addFile(ArchiveFile(
      '[Content_Types].xml',
      contentTypeBytes.length,
      contentTypeBytes,
    ));
    final relsBytes = utf8.encode(_rels);
    archive.addFile(ArchiveFile(
      '_rels/.rels',
      relsBytes.length,
      relsBytes,
    ));
    _addTextFile(archive, 'word/_rels/document.xml.rels', _documentRels);
    _addTextFile(archive, 'word/styles.xml', _stylesXml);
    _addTextFile(archive, 'word/settings.xml', _settingsXml);
    _addTextFile(archive, 'docProps/app.xml', _appXml);
    _addTextFile(archive, 'docProps/core.xml', _coreXml());

    final buf = StringBuffer(_documentXmlRel);
    for (final paragraph in MarkupExportService.parse(
      text,
      defaultRtl: defaultRtl,
    )) {
      if (paragraph.isEmpty) {
        buf.write('<w:p/>');
        continue;
      }

      buf.write('<w:p>');
      buf.write('<w:pPr>');
      if (paragraph.isRtl) buf.write('<w:bidi/>');
      buf.write('<w:jc w:val="${_docxAlign(paragraph)}"/>');
      if (paragraph.isRtl) {
        buf.write(
          '<w:rPr><w:rtl/><w:lang w:val="he-IL" '
          'w:bidi="he-IL"/></w:rPr>',
        );
      }
      buf.write('</w:pPr>');
      for (final directionalRun in MarkupExportService.documentRuns(
        paragraph,
      )) {
        _writeRun(
          directionalRun.run,
          directionalRun.text,
          buf,
          directionalRun.isRtl,
        );
      }
      buf.write('</w:p>');
    }

    buf.write(_documentXmlFooter);
    final docXml = utf8.encode(buf.toString());
    archive.addFile(ArchiveFile(
      'word/document.xml',
      docXml.length,
      docXml,
    ));

    return ZipEncoder().encode(archive)!;
  }

  static void _writeRun(
    ExportTextRun run,
    String text,
    StringBuffer buf,
    bool rtl,
  ) {
    if (text.isEmpty) return;
    buf.write('<w:r>');
    buf.write('<w:rPr>');
    if (run.isBold) buf.write('<w:b/>');
    if (run.isBold) buf.write('<w:bCs/>');
    if (run.isItalic) buf.write('<w:i/>');
    if (run.isItalic) buf.write('<w:iCs/>');
    if (run.isUnderline) buf.write('<w:u w:val="single"/>');
    if (rtl) buf.write('<w:rtl/>');
    if (run.color != null && !_isDefaultDisplayWhite(run.color)) {
      buf.write('<w:color w:val="${run.color}"/>');
    }
    if (run.backgroundColor != null) {
      buf.write(
        '<w:shd w:val="clear" w:color="auto" '
        'w:fill="${run.backgroundColor}"/>',
      );
    }
    final halfPoints = ((run.fontSize ?? 18) * 2).round();
    buf.write('<w:sz w:val="$halfPoints"/>');
    buf.write('<w:szCs w:val="$halfPoints"/>');
    if (run.fontFamily != null) {
      final font = _escapeXml(run.fontFamily!);
      buf.write(
        '<w:rFonts w:ascii="$font" w:hAnsi="$font" '
        'w:cs="$font" w:hint="cs"/>',
      );
    }
    if (rtl) buf.write('<w:lang w:val="he-IL" w:bidi="he-IL"/>');
    buf.write('</w:rPr>');
    buf.write('<w:t xml:space="preserve">${_escapeXml(text)}</w:t>');
    buf.write('</w:r>');
  }

  static String _docxAlign(ExportParagraph paragraph) {
    if (paragraph.isRtl && !paragraph.hasExplicitAlign) return 'right';
    switch (paragraph.align) {
      case 'center':
        return 'center';
      case 'right':
        return 'right';
      default:
        return 'left';
    }
  }

  static bool _isDefaultDisplayWhite(String? hex) =>
      hex != null && hex.toUpperCase() == 'FFFFFF';

  static String _escapeXml(String s) => _sanitizeXmlText(s)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _sanitizeXmlText(String value) {
    return String.fromCharCodes(
      value.runes.where((rune) {
        return rune == 0x09 ||
            rune == 0x0A ||
            rune == 0x0D ||
            (rune >= 0x20 && rune <= 0xD7FF) ||
            (rune >= 0xE000 && rune <= 0xFFFD) ||
            (rune >= 0x10000 && rune <= 0x10FFFF);
      }),
    );
  }

  static void _addTextFile(Archive archive, String path, String contents) {
    final bytes = utf8.encode(contents);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  static String _coreXml() {
    final now = DateTime.now().toUtc().toIso8601String();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties '
        'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:creator>AutoTeleprompter</dc:creator>'
        '<cp:lastModifiedBy>AutoTeleprompter</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>'
        '</cp:coreProperties>';
  }
}
