import 'dart:convert';

import 'package:archive/archive.dart';

import 'markup_export_service.dart';

/// Generates minimal Apple Pages (.pages) files from the app's internal markup.
///
/// A .pages file is a ZIP archive. We use the old XML-based format (index.xml)
/// which is the only format we can write without Apple's private protobuf
/// schema. The visible Pages XML stays plain text, but the original app markup
/// is stored in a private archive member so AutoTeleprompter can round-trip
/// styles when reopening files it created.
class PagesService {
  PagesService._();
  static const markupEntryName = 'AutoTeleprompter/raw_markup.txt';

  /// Converts internal-markup text to .pages ZIP bytes.
  static List<int> generate(String text) {
    final xml = _buildIndexXml(text);
    final xmlBytes = utf8.encode(xml);
    final markupBytes = utf8.encode(text.replaceAll('\r\n', '\n'));

    final archive = Archive();
    archive.addFile(ArchiveFile('index.xml', xmlBytes.length, xmlBytes));
    archive.addFile(
      ArchiveFile(markupEntryName, markupBytes.length, markupBytes),
    );

    return ZipEncoder().encode(archive)!;
  }

  static String _buildIndexXml(String text) {
    final buf = StringBuffer();
    buf.write('<?xml version="1.0" encoding="UTF-8"?>\n');
    buf.write('<sl:document'
        ' xmlns:sl="http://developer.apple.com/namespaces/sl"'
        ' xmlns:sf="http://developer.apple.com/namespaces/sf"'
        ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
        ' xsi:type="sl:document">\n');
    buf.write('  <sl:drawables>\n');
    buf.write(
        '    <wp:body xmlns:wp="http://developer.apple.com/namespaces/wp">\n');
    buf.write('      <sf:section>\n');
    buf.write('        <sf:layout>\n');

    for (final line in MarkupExportService.toPlainText(text).split('\n')) {
      buf.write('          <sf:p>');
      if (line.isNotEmpty) {
        buf.write('<sf:s><sf:t>');
        buf.write(_escapeXml(line));
        buf.write('</sf:t></sf:s>');
      }
      buf.write('</sf:p>\n');
    }

    buf.write('        </sf:layout>\n');
    buf.write('      </sf:section>\n');
    buf.write('    </wp:body>\n');
    buf.write('  </sl:drawables>\n');
    buf.write('</sl:document>\n');
    return buf.toString();
  }

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
