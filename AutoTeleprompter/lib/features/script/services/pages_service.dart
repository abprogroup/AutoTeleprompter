import 'dart:convert';
import 'package:archive/archive.dart';

/// Generates minimal Apple Pages (.pages) files from the app's internal markup.
///
/// A .pages file is a ZIP archive. We use the old XML-based format (index.xml)
/// which is the only format we can write without Apple's private protobuf schema.
/// The output is compatible with [ScriptProvider._parsePages] for round-trip use,
/// and can be opened in Apple Pages as a readable document.
///
/// Internal markup ([color=#HEX]...[/color], **bold**, shorthand color tags) is
/// stripped to plain text since Pages XML doesn't support our custom format.
class PagesService {
  PagesService._();

  /// Converts internal-markup text to .pages ZIP bytes.
  static List<int> generate(String text) {
    final xml = _buildIndexXml(text);
    final xmlBytes = utf8.encode(xml);

    final archive = Archive();
    archive.addFile(ArchiveFile('index.xml', xmlBytes.length, xmlBytes));

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
    buf.write('    <wp:body xmlns:wp="http://developer.apple.com/namespaces/wp">\n');
    buf.write('      <sf:section>\n');
    buf.write('        <sf:layout>\n');

    for (final line in text.split('\n')) {
      final plain = _stripMarkup(line);
      buf.write('          <sf:p>');
      if (plain.isNotEmpty) {
        buf.write('<sf:s><sf:t>');
        buf.write(_escapeXml(plain));
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

  /// Strips all internal markup tags and bold markers, returning plain text.
  static String _stripMarkup(String line) {
    return line
        // Remove [color=#HEX]...[/color] wrappers (keep text)
        .replaceAllMapped(RegExp(r'\[color=#[0-9A-Fa-f]{6}\](.*?)\[/color\]'),
            (m) => m.group(1) ?? '')
        // Remove shorthand color tags [yc]...[/yc] etc.
        .replaceAllMapped(RegExp(r'\[(?:yc|rc|gc|bc|oc|pc|cc|pkc)\](.*?)\[/(?:yc|rc|gc|bc|oc|pc|cc|pkc)\]'),
            (m) => m.group(1) ?? '')
        // Remove bold markers
        .replaceAll('**', '')
        // Remove any remaining [tag] tokens
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .trim();
  }

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
