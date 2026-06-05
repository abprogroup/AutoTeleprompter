import 'dart:convert';

import 'package:archive/archive.dart';

import 'markup_export_service.dart';

class OdtService {
  OdtService._();

  static List<int> generate(String text) {
    final archive = Archive();
    final mimetype = utf8.encode(
      'application/vnd.oasis.opendocument.text',
    );
    archive.addFile(ArchiveFile('mimetype', mimetype.length, mimetype));

    final manifest = utf8.encode(_manifestXml);
    archive.addFile(
      ArchiveFile('META-INF/manifest.xml', manifest.length, manifest),
    );

    final content = utf8.encode(_contentXml(text));
    archive.addFile(ArchiveFile('content.xml', content.length, content));
    return ZipEncoder().encode(archive)!;
  }

  static String _contentXml(String text) {
    final styleBuffer = StringBuffer();
    final bodyBuffer = StringBuffer();
    var styleIndex = 0;
    for (final paragraph in MarkupExportService.parse(text)) {
      final paragraphStyle = paragraph.isRtl ? 'P_RTL' : 'P_LTR';
      bodyBuffer.write('<text:p text:style-name="$paragraphStyle">');
      for (final run in paragraph.runs) {
        if (run.text.isEmpty) continue;
        final styleName = 'T${styleIndex++}';
        styleBuffer.write(_textStyleXml(styleName, run));
        bodyBuffer.write(
          '<text:span text:style-name="$styleName">'
          '${_escapeXml(run.text)}'
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
        '<style:style style:name="P_RTL" style:family="paragraph">'
        '<style:paragraph-properties fo:text-align="right" '
        'style:writing-mode="rl-tb"/>'
        '</style:style>'
        '<style:style style:name="P_LTR" style:family="paragraph">'
        '<style:paragraph-properties fo:text-align="left" '
        'style:writing-mode="lr-tb"/>'
        '</style:style>'
        '$styleBuffer'
        '</office:automatic-styles>'
        '<office:body><office:text>$bodyBuffer</office:text></office:body>'
        '</office:document-content>';
  }

  static String _textStyleXml(String name, ExportTextRun run) {
    final props = <String>[];
    if (run.isBold) props.add('fo:font-weight="bold"');
    if (run.isItalic) props.add('fo:font-style="italic"');
    if (run.isUnderline) {
      props
        ..add('style:text-underline-style="solid"')
        ..add('style:text-underline-width="auto"')
        ..add('style:text-underline-color="font-color"');
    }
    if (run.fontSize != null) {
      props.add('fo:font-size="${run.fontSize!.toStringAsFixed(1)}pt"');
    }
    if (run.fontFamily != null) {
      props.add('fo:font-family="${_escapeXml(run.fontFamily!)}"');
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

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
