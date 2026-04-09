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

      // v3.9.5.7: Standardized Alignment Handling
      String align = 'left';
      String cleanP = p;
      if (p.contains('[center]')) {
        align = 'center';
        cleanP = p.replaceAll(RegExp(r'\[\/?center\]'), '');
      } else if (p.contains('[right]')) {
        align = 'right';
        cleanP = p.replaceAll(RegExp(r'\[\/?right\]'), '');
      }

      buf.write('<w:p>');
      buf.write('<w:pPr><w:jc w:val="$align"/></w:pPr>');
      
      // Parse segments for bold, color, size
      final segments = _parseSegments(cleanP);
      for (final s in segments) {
        buf.write('<w:r>');
        buf.write('<w:rPr>');
        if (s.isBold) buf.write('<w:b/>');
        if (s.color != null) {
          final hex = s.color!.replaceAll('#', '').trim();
          if (hex.length == 6) buf.write('<w:color w:val="$hex"/>');
        }
        if (s.size != null) {
          final halfPts = (s.size! * 2).toInt();
          buf.write('<w:sz w:val="$halfPts"/>');
        }
        if (s.font != null) {
          buf.write('<w:rFonts w:ascii="${s.font}" w:hAnsi="${s.font}"/>');
        }
        buf.write('</w:rPr>');
        
        // v3.9.5.7: Absolute Guard - Strip residual tags from text run
        final finalContent = s.text.replaceAll(RegExp(r'\[\/?(?:u|i|color|size|font|bg|align|center|left|right)(?:=[^\]]+)?\]|\*\*'), '');
        final escaped = finalContent.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
        buf.write('<w:t xml:space="preserve">$escaped</w:t>');
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
    final List<_TextSegment> results = [];
    // v3.9.5.7 Hardened Regex for Fragment Isolation
    final reg = RegExp(r'(?:\[color=([^\]]+)\])?(?:\[size=([^\]]+)\])?(?:\[font=([^\]]+)\])?(\*\*)?([^\*\[]+)(?:\*\*)?(?:\[\/(?:color|size|font)\])*');
    final matches = reg.allMatches(text);
    
    if (matches.isEmpty) {
      results.add(_TextSegment(text: text));
      return results;
    }

    for (final m in matches) {
      String? color = m.group(1);
      String? sizeStr = m.group(2);
      String? font = m.group(3);
      bool bold = m.group(4) != null;
      String content = m.group(5) ?? '';
      
      double? size;
      if (sizeStr != null) size = double.tryParse(sizeStr);
      
      results.add(_TextSegment(
        text: content,
        isBold: bold,
        color: color,
        size: size,
        font: font,
      ));
    }
    
    return results;
  }
}

class _TextSegment {
  final String text;
  final bool isBold;
  final String? color, font;
  final double? size;
  _TextSegment({required this.text, this.isBold = false, this.color, this.size, this.font});
}
