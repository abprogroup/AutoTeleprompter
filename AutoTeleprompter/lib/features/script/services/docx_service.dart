import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:flutter/foundation.dart';

class DocxService {
  static const String _documentXmlRel = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>';
  static const String _documentXmlFooter = '</w:body></w:document>';
  
  static const String _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
  
  static const String _rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';

  /// Converts our internal markup to styled DOCX bytes
  static List<int> generate(String text) {
    final archive = Archive();
    
    // 1. Content Types
    archive.addFile(ArchiveFile('[Content_Types].xml', _contentTypes.length, utf8.encode(_contentTypes)));
    
    // 2. Base Relations
    archive.addFile(ArchiveFile('_rels/.rels', _rels.length, utf8.encode(_rels)));
    
    // 3. Document Body
    final paragraphs = text.split('\n');
    final buf = StringBuffer(_documentXmlRel);
    
    for (final p in paragraphs) {
      if (p.trim().isEmpty) {
         buf.write('<w:p/>');
         continue;
      }
      buf.write('<w:p>');
      
      // Parse segments for bold, color, size
      final segments = _parseSegments(p);
      for (final s in segments) {
        buf.write('<w:r>');
        buf.write('<w:rPr>');
        if (s.isBold) buf.write('<w:b/>');
        if (s.color != null) {
          final hex = s.color!.replaceAll('#', '');
          buf.write('<w:color w:val="$hex"/>');
        }
        if (s.size != null) {
          final halfPts = (s.size! * 2).toInt();
          buf.write('<w:sz w:val="$halfPts"/>');
        }
        buf.write('</w:rPr>');
        buf.write('<w:t xml:space="preserve">${SecurityContext.defaultContext != null ? s.text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;") : s.text}</w:t>');
        buf.write('</w:r>');
      }
      
      buf.write('</w:p>');
    }
    
    buf.write(_documentXmlFooter);
    final docXml = buf.toString();
    archive.addFile(ArchiveFile('word/document.xml', docXml.length, utf8.encode(docXml)));
    
    return ZipEncoder().encode(archive)!;
  }

  static List<_TextSegment> _parseSegments(String text) {
    // Basic greedy regex segmentation for Phase 3
    final List<_TextSegment> results = [];
    
    // Simplification: We look for BOLD, COLOR, SIZE tags
    // For now, let's treat the entire paragraph as a series of runs
    // In a future update, we can use a proper recursive parser.
    // For now, we look for simple tags.
    
    final reg = RegExp(r'(\[color=([^\]]+)\])?(\[size=([^\]]+)\])?(\*\*)?([^\*\[]+)(\*\*)?(\[/size\])?(\[/color\])?');
    final matches = reg.allMatches(text);
    
    if (matches.isEmpty) {
      results.add(_TextSegment(text: text));
      return results;
    }

    for (final m in matches) {
      String? color = m.group(2);
      String? sizeStr = m.group(4);
      bool bold = m.group(5) != null || m.group(7) != null;
      String content = m.group(6) ?? '';
      
      double? size;
      if (sizeStr != null) size = double.tryParse(sizeStr);
      
      results.add(_TextSegment(
        text: content,
        isBold: bold,
        color: color,
        size: size,
      ));
    }
    
    return results;
  }
}

class _TextSegment {
  final String text;
  final bool isBold;
  final String? color;
  final double? size;
  _TextSegment({required this.text, this.isBold = false, this.color, this.size});
}
