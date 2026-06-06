import 'dart:convert';

import 'package:archive/archive.dart';

import 'markup_export_service.dart';

class OdtService {
  OdtService._();

  static List<int> generate(String text, {bool? defaultRtl}) {
    final archive = Archive();
    final mimetype = utf8.encode(
      'application/vnd.oasis.opendocument.text',
    );
    archive.addFile(ArchiveFile('mimetype', mimetype.length, mimetype));

    final manifest = utf8.encode(_manifestXml);
    archive.addFile(
      ArchiveFile('META-INF/manifest.xml', manifest.length, manifest),
    );

    final content = utf8.encode(_contentXml(text, defaultRtl: defaultRtl));
    archive.addFile(ArchiveFile('content.xml', content.length, content));
    return ZipEncoder().encode(archive)!;
  }

  static String _contentXml(String text, {bool? defaultRtl}) {
    final styleBuffer = StringBuffer();
    final bodyBuffer = StringBuffer();
    var styleIndex = 0;
    for (final paragraph in MarkupExportService.parse(
      text,
      defaultRtl: defaultRtl,
    )) {
      final paragraphStyle = _paragraphStyleName(paragraph);
      bodyBuffer.write('<text:p text:style-name="$paragraphStyle">');
      for (final directionalRun in MarkupExportService.documentRuns(
        paragraph,
      )) {
        if (directionalRun.text.isEmpty) continue;
        final styleName = 'T${styleIndex++}';
        styleBuffer.write(
          _textStyleXml(styleName, directionalRun.run, directionalRun.isRtl),
        );
        bodyBuffer.write(
          '<text:span text:style-name="$styleName">'
          '${_escapeXml(directionalRun.text)}'
          '</text:span>',
        );
      }
      bodyBuffer.write('</text:p>');
    }

    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<office:document-content '
        'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
        'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
        'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
        'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
        'xmlns:style-compat="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
        'office:version="1.2">'
        '<office:automatic-styles>'
        '${_paragraphStyleXml('P_RTL_LEFT', 'left', true)}'
        '${_paragraphStyleXml('P_RTL_CENTER', 'center', true)}'
        '${_paragraphStyleXml('P_RTL_RIGHT', 'right', true)}'
        '${_paragraphStyleXml('P_LTR_LEFT', 'left', false)}'
        '${_paragraphStyleXml('P_LTR_CENTER', 'center', false)}'
        '${_paragraphStyleXml('P_LTR_RIGHT', 'right', false)}'
        '$styleBuffer'
        '</office:automatic-styles>'
        '<office:body><office:text>$bodyBuffer</office:text></office:body>'
        '</office:document-content>';
  }

  static String _paragraphStyleName(ExportParagraph paragraph) {
    final direction = paragraph.isRtl ? 'RTL' : 'LTR';
    final align = _paragraphAlign(paragraph).toUpperCase();
    return 'P_${direction}_$align';
  }

  static String _paragraphAlign(ExportParagraph paragraph) {
    if (paragraph.hasExplicitAlign) return paragraph.align;
    return paragraph.isRtl ? 'right' : 'left';
  }

  static String _paragraphStyleXml(String name, String align, bool rtl) {
    final mode = rtl ? 'rl-tb' : 'lr-tb';
    final direction = rtl ? 'rtl' : 'ltr';
    return '<style:style style:name="$name" style:family="paragraph">'
        '<style:paragraph-properties fo:text-align="$align" '
        'style:writing-mode="$mode" style:direction="$direction"/>'
        '</style:style>';
  }

  static String _textStyleXml(String name, ExportTextRun run, bool rtl) {
    final props = <String>[];
    props.add('style:writing-mode="${rtl ? 'rl-tb' : 'lr-tb'}"');
    props.add('style:direction="${rtl ? 'rtl' : 'ltr'}"');
    if (run.isBold) props.add('fo:font-weight="bold"');
    if (run.isItalic) props.add('fo:font-style="italic"');
    if (run.isUnderline) {
      props
        ..add('style:text-underline-style="solid"')
        ..add('style:text-underline-width="auto"')
        ..add('style:text-underline-color="font-color"');
    }
    final fontSize = (run.fontSize ?? 18).toStringAsFixed(1);
    props.add('fo:font-size="${fontSize}pt"');
    props.add('style:font-size-asian="${fontSize}pt"');
    props.add('style:font-size-complex="${fontSize}pt"');
    if (run.fontFamily != null) {
      final fontFamily = _escapeXml(run.fontFamily!);
      props.add('fo:font-family="$fontFamily"');
      props.add('style:font-family-asian="$fontFamily"');
      props.add('style:font-family-complex="$fontFamily"');
    }
    final color = _styleColor(run.color, omitWhite: true);
    if (color != null) props.add('fo:color="#$color"');
    final background = _styleColor(run.backgroundColor);
    if (background != null) props.add('fo:background-color="#$background"');
    return '<style:style style:name="$name" style:family="text">'
        '<style:text-properties ${props.join(' ')}/>'
        '</style:style>';
  }

  static String? _styleColor(String? hex, {bool omitWhite = false}) {
    final clean = hex?.trim().replaceFirst('#', '').toUpperCase();
    if (clean == null || clean.length != 6) return null;
    if (omitWhite && clean == 'FFFFFF') return null;
    return clean;
  }

  static const _manifestXml = '<?xml version="1.0" encoding="UTF-8"?>'
      '<manifest:manifest '
      'xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" '
      'manifest:version="1.2">'
      '<manifest:file-entry manifest:full-path="/" '
      'manifest:media-type="application/vnd.oasis.opendocument.text"/>'
      '<manifest:file-entry manifest:full-path="content.xml" '
      'manifest:media-type="text/xml"/>'
      '</manifest:manifest>';

  static String _escapeXml(String value) => _sanitizeXmlText(value)
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
}
