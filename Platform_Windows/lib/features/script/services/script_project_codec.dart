import 'dart:convert';

import 'script_bookmark_service.dart';

class ScriptProjectExport {
  final String fileName;
  final String mimeType;
  final List<int> bytes;

  const ScriptProjectExport({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });
}

class ScriptProjectData {
  final String title;
  final String rawText;
  final String sourceType;
  final String? primaryFileName;
  final String? sourceFileName;
  final String sessionId;
  final String? historyJson;
  final int historyIndex;
  final double? fontSize;
  final String? fontFamily;
  final double? lineSpacing;
  final double? letterSpacing;
  final double? wordSpacing;
  final String? textAlign;
  final int? scriptBgColor;
  final int? currentWordColor;
  final int? futureWordColor;
  final bool? isRtl;
  final List<ScriptBookmark> bookmarks;

  const ScriptProjectData({
    required this.title,
    required this.rawText,
    required this.sourceType,
    required this.primaryFileName,
    required this.sourceFileName,
    required this.sessionId,
    required this.historyJson,
    required this.historyIndex,
    required this.fontSize,
    required this.fontFamily,
    required this.lineSpacing,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.textAlign,
    required this.scriptBgColor,
    required this.currentWordColor,
    required this.futureWordColor,
    required this.isRtl,
    required this.bookmarks,
  });
}

class ScriptProjectCodec {
  static const kind = 'autoteleprompter.script.project';
  static const version = 1;
  static const extension = 'atp';
  static const companionSuffix = '.autoteleprompter.json';
  static const mimeType = 'application/json; charset=utf-8';

  static ScriptProjectExport buildCompanion({
    required String primaryFileName,
    required String title,
    required String rawText,
    required String? sourceType,
    required String? sourcePath,
    required String? sessionId,
    required String? historyJson,
    required int? historyIndex,
    required double? fontSize,
    required String? fontFamily,
    required double? lineSpacing,
    required double? letterSpacing,
    required double? wordSpacing,
    required String? textAlign,
    required int? scriptBgColor,
    required int? currentWordColor,
    required int? futureWordColor,
    bool? isRtl,
    required List<ScriptBookmark> bookmarks,
  }) {
    return _build(
      fileName: metadataFileNameFor(primaryFileName),
      primaryFileName: primaryFileName,
      title: title,
      rawText: rawText,
      sourceType: sourceType,
      sourcePath: sourcePath,
      sessionId: sessionId,
      historyJson: historyJson,
      historyIndex: historyIndex,
      fontSize: fontSize,
      fontFamily: fontFamily,
      lineSpacing: lineSpacing,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textAlign: textAlign,
      scriptBgColor: scriptBgColor,
      currentWordColor: currentWordColor,
      futureWordColor: futureWordColor,
      isRtl: isRtl,
      bookmarks: bookmarks,
    );
  }

  static ScriptProjectExport build({
    required String title,
    required String rawText,
    required String? sourceType,
    required String? sourcePath,
    required String? sessionId,
    required String? historyJson,
    required int? historyIndex,
    required double? fontSize,
    required String? fontFamily,
    required double? lineSpacing,
    required double? letterSpacing,
    required double? wordSpacing,
    required String? textAlign,
    required int? scriptBgColor,
    required int? currentWordColor,
    required int? futureWordColor,
    bool? isRtl,
    required List<ScriptBookmark> bookmarks,
  }) {
    final safeTitle = title.trim().isEmpty ? 'Untitled script' : title.trim();
    return _build(
      fileName:
          '${_safeBaseName(title: safeTitle, sourcePath: sourcePath)}.$extension',
      primaryFileName: null,
      title: title,
      rawText: rawText,
      sourceType: sourceType,
      sourcePath: sourcePath,
      sessionId: sessionId,
      historyJson: historyJson,
      historyIndex: historyIndex,
      fontSize: fontSize,
      fontFamily: fontFamily,
      lineSpacing: lineSpacing,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textAlign: textAlign,
      scriptBgColor: scriptBgColor,
      currentWordColor: currentWordColor,
      futureWordColor: futureWordColor,
      isRtl: isRtl,
      bookmarks: bookmarks,
    );
  }

  static ScriptProjectExport _build({
    required String fileName,
    required String? primaryFileName,
    required String title,
    required String rawText,
    required String? sourceType,
    required String? sourcePath,
    required String? sessionId,
    required String? historyJson,
    required int? historyIndex,
    required double? fontSize,
    required String? fontFamily,
    required double? lineSpacing,
    required double? letterSpacing,
    required double? wordSpacing,
    required String? textAlign,
    required int? scriptBgColor,
    required int? currentWordColor,
    required int? futureWordColor,
    required bool? isRtl,
    required List<ScriptBookmark> bookmarks,
  }) {
    final safeTitle = title.trim().isEmpty ? 'Untitled script' : title.trim();
    final sourceFileName = _sourceFileName(sourcePath);
    final payload = <String, Object?>{
      'kind': kind,
      'version': version,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'script': {
        'title': safeTitle,
        'rawText': rawText,
        if (primaryFileName?.trim().isNotEmpty == true)
          'primaryFileName': primaryFileName!.trim(),
        'sourceType':
            sourceType?.trim().isNotEmpty == true ? sourceType!.trim() : 'FILE',
        if (sourceFileName != null) 'sourceFileName': sourceFileName,
        'sessionId': sessionId?.trim().isNotEmpty == true
            ? sessionId!.trim()
            : 'cloud_${DateTime.now().microsecondsSinceEpoch}',
        'historyIndex': historyIndex ?? -1,
        if (historyJson?.trim().isNotEmpty == true) 'historyJson': historyJson,
        'style': {
          if (fontSize != null) 'fontSize': fontSize,
          if (fontFamily?.trim().isNotEmpty == true)
            'fontFamily': fontFamily!.trim(),
          if (lineSpacing != null) 'lineSpacing': lineSpacing,
          if (letterSpacing != null) 'letterSpacing': letterSpacing,
          if (wordSpacing != null) 'wordSpacing': wordSpacing,
          if (textAlign?.trim().isNotEmpty == true)
            'textAlign': textAlign!.trim(),
          if (scriptBgColor != null) 'scriptBgColor': scriptBgColor,
          if (currentWordColor != null) 'currentWordColor': currentWordColor,
          if (futureWordColor != null) 'futureWordColor': futureWordColor,
          if (isRtl != null) 'isRtl': isRtl,
        },
        'bookmarks': bookmarks.map((b) => b.toJson()).toList(growable: false),
      },
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    return ScriptProjectExport(
      fileName: fileName,
      mimeType: mimeType,
      bytes: utf8.encode(encoded),
    );
  }

  static String metadataFileNameFor(String primaryFileName) {
    final clean = primaryFileName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final base = clean.isEmpty ? 'Untitled script.txt' : clean;
    return '$base$companionSuffix';
  }

  static bool isMetadataFileName(String fileName) =>
      fileName.toLowerCase().endsWith(companionSuffix);

  static ScriptProjectData? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['kind'] != kind) {
        return null;
      }
      final script = decoded['script'];
      if (script is! Map<String, dynamic>) return null;
      final style = script['style'] is Map<String, dynamic>
          ? script['style'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final bookmarksRaw =
          script['bookmarks'] is List ? script['bookmarks'] as List : const [];
      return ScriptProjectData(
        title: script['title']?.toString() ?? 'Untitled script',
        rawText: script['rawText']?.toString() ?? '',
        sourceType: script['sourceType']?.toString() ?? 'CLOUD',
        primaryFileName: script['primaryFileName']?.toString(),
        sourceFileName: script['sourceFileName']?.toString(),
        sessionId: script['sessionId']?.toString() ??
            'cloud_${DateTime.now().microsecondsSinceEpoch}',
        historyJson: script['historyJson']?.toString(),
        historyIndex: (script['historyIndex'] as num?)?.toInt() ?? -1,
        fontSize: (style['fontSize'] as num?)?.toDouble(),
        fontFamily: style['fontFamily']?.toString(),
        lineSpacing: (style['lineSpacing'] as num?)?.toDouble(),
        letterSpacing: (style['letterSpacing'] as num?)?.toDouble(),
        wordSpacing: (style['wordSpacing'] as num?)?.toDouble(),
        textAlign: style['textAlign']?.toString(),
        scriptBgColor: (style['scriptBgColor'] as num?)?.toInt(),
        currentWordColor: (style['currentWordColor'] as num?)?.toInt(),
        futureWordColor: (style['futureWordColor'] as num?)?.toInt(),
        isRtl: style['isRtl'] is bool ? style['isRtl'] as bool : null,
        bookmarks: [
          for (final item in bookmarksRaw)
            if (item is Map)
              ScriptBookmark.fromJson(Map<String, dynamic>.from(item)),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  static String? _sourceFileName(String? sourcePath) {
    final value = sourcePath?.trim();
    if (value == null || value.isEmpty) return null;
    return value.split(RegExp(r'[\\/]')).last;
  }

  static String _safeBaseName({
    required String title,
    String? sourcePath,
  }) {
    final sourceName = _sourceFileName(sourcePath);
    final rawName = sourceName?.isNotEmpty == true ? sourceName! : title;
    final stripped = rawName.replaceFirst(
      RegExp(
        r'\.(?:docx?|rtf|txt|text|log|md|pdf|odt|pages|atp|atp\.txt)$',
        caseSensitive: false,
      ),
      '',
    );
    final safe = stripped
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return safe.isEmpty ? 'Untitled script' : safe;
  }
}
