import 'dart:convert';

import 'package:archive/archive.dart';

import 'markup_export_service.dart';

class DocxService {
  static const String _documentXmlRel =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>';
  static const String _documentXmlFooter = '</w:body></w:document>';

  static const String _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';

  static const String _rels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  /// Converts internal markup to styled DOCX bytes.
  static List<int> generate(String text) {
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

    final buf = StringBuffer(_documentXmlRel);
    for (final paragraph in MarkupExportService.parse(text)) {
      if (paragraph.isEmpty) {
        buf.write('<w:p/>');
        continue;
      }

      buf.write('<w:p>');
      buf.write(
          '<w:pPr><w:jc w:val="${_docxAlign(paragraph.align)}"/></w:pPr>');
      for (final run in paragraph.runs) {
        _writeRun(run, buf);
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

  static void _writeRun(ExportTextRun run, StringBuffer buf) {
    if (run.text.isEmpty) return;
    buf.write('<w:r>');
    buf.write('<w:rPr>');
    if (run.isBold) buf.write('<w:b/>');
    if (run.isItalic) buf.write('<w:i/>');
    if (run.isUnderline) buf.write('<w:u w:val="single"/>');
    if (run.color != null && !_isDefaultDisplayWhite(run.color)) {
      buf.write('<w:color w:val="${run.color}"/>');
    }
    if (run.fontSize != null) {
      final halfPoints = (run.fontSize! * 2).round();
      buf.write('<w:sz w:val="$halfPoints"/>');
    }
    if (run.fontFamily != null) {
      final font = _escapeXml(run.fontFamily!);
      buf.write('<w:rFonts w:ascii="$font" w:hAnsi="$font"/>');
    }
    buf.write('</w:rPr>');
    buf.write('<w:t xml:space="preserve">${_escapeXml(run.text)}</w:t>');
    buf.write('</w:r>');
  }

  static String _docxAlign(String align) {
    switch (align) {
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

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
