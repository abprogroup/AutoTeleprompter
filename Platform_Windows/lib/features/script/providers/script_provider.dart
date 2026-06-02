import 'dart:convert';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/script.dart';
import '../models/script_word.dart';
import '../../settings/providers/settings_provider.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../../core/extensions/string_extensions.dart';
import '../../../core/security/secure_script_store.dart';
import '../../../features/teleprompter/services/word_aligner.dart';

part 'script_provider.docx.dart';
part 'script_provider.pages_rtf.dart';
part 'script_provider.models.dart';

const int _maxPlainImportBytes = 25 * 1024 * 1024;
const int _maxArchiveImportBytes = 80 * 1024 * 1024;
const int _maxArchiveEntries = 2000;
const int _maxArchiveExpandedBytes = 120 * 1024 * 1024;
const int _maxImportXmlBytes = 30 * 1024 * 1024;

class ImportSafetyException implements Exception {
  final String message;

  const ImportSafetyException(this.message);

  @override
  String toString() => message;
}

class ScriptNotifier extends Notifier<Script?> {
  int _storedLoadGeneration = 0;
  bool _isDisposed = false;

  @override
  Script? build() {
    void scheduleStoredScriptLoad(AppSettings settings) {
      if (settings.lastScriptSessionId.isEmpty) return;
      final generation = ++_storedLoadGeneration;
      Future<void>.delayed(Duration.zero, () {
        if (_isDisposed || generation != _storedLoadGeneration) return;
        unawaited(_loadStoredScriptFromSettings(settings, generation));
      });
    }

    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
      _storedLoadGeneration++;
    });
    ref.listen<AppSettings>(settingsProvider, (previous, next) {
      if (previous?.lastScriptSessionId != next.lastScriptSessionId) {
        scheduleStoredScriptLoad(next);
      }
    });
    // Load legacy last saved script on startup while encrypted settings hydrate.
    final settings = ref.read(settingsProvider);
    scheduleStoredScriptLoad(settings);
    final lastText = settings.lastScript;
    final lastTitle = settings.lastScriptTitle;

    String sourceType = 'TEMP';
    String? sessionId;
    int? historyIndex;
    String? historyJson;
    String? sourcePath;
    double? fontSize, lineSpacing, letterSpacing, wordSpacing;
    String? fontFamily, textAlign;
    int? scriptBgColor, currentWordColor, futureWordColor;

    for (final json in settings.recentScripts) {
      try {
        final meta = jsonDecode(json);
        if (meta['fullText'] == lastText ||
            meta['sessionId'] == sessionId ||
            meta['title'] == lastTitle) {
          sourceType = meta['type'] ?? 'TEMP';
          sessionId = meta['sessionId'];
          sourcePath = meta['sourcePath'] as String?;
          final metaIdx = meta['historyIndex'];
          if (metaIdx != null) historyIndex = metaIdx;
          final metaHistJson = meta['historyJson'];
          if (metaHistJson is String) historyJson = metaHistJson;

          // v3.9.5.70: Extract styling metadata (Nested for Gallery Compatibility)
          final style = meta['style'] as Map<String, dynamic>?;
          if (style != null) {
            if (style['fontSize'] != null) {
              fontSize = (style['fontSize'] as num).toDouble();
            }
            if (style['fontFamily'] != null) fontFamily = style['fontFamily'];
            if (style['lineSpacing'] != null) {
              lineSpacing = (style['lineSpacing'] as num).toDouble();
            }
            if (style['letterSpacing'] != null) {
              letterSpacing = (style['letterSpacing'] as num).toDouble();
            }
            if (style['wordSpacing'] != null) {
              wordSpacing = (style['wordSpacing'] as num).toDouble();
            }
            if (style['textAlign'] != null) textAlign = style['textAlign'];
            if (style['scriptBgColor'] != null) {
              scriptBgColor = style['scriptBgColor'];
            }
            if (style['currentWordColor'] != null) {
              currentWordColor = style['currentWordColor'];
            }
            if (style['futureWordColor'] != null) {
              futureWordColor = style['futureWordColor'];
            }
          }

          break;
        }
      } catch (e) {
        LightweightDiagnostics.instance.record(
          'script',
          'ignored malformed recent script metadata',
          data: {
            'source': 'startupLegacyMetadata',
            'error': e.toString(),
          },
        );
      }
    }

    if (lastText.isNotEmpty) {
      return _buildScript(
        lastText,
        title: lastTitle.isNotEmpty ? lastTitle : null,
        sourceType: sourceType,
        sourcePath: sourcePath,
        sessionId: sessionId,
        historyIndex: historyIndex ?? settings.lastHistoryIndex,
        historyJson: historyJson,
        fontSize: fontSize,
        fontFamily: fontFamily,
        lineSpacing: lineSpacing,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        textAlign: textAlign,
        scriptBgColor: scriptBgColor,
        currentWordColor: currentWordColor,
        futureWordColor: futureWordColor,
      );
    }
    return null;
  }

  bool get _hasActiveScript {
    try {
      return state != null;
    } on StateError {
      return false;
    }
  }

  Future<void> _loadStoredScriptFromSettings(
    AppSettings settings,
    int generation,
  ) async {
    if (_isDisposed ||
        generation != _storedLoadGeneration ||
        settings.lastScriptSessionId.isEmpty ||
        _hasActiveScript) {
      return;
    }
    Map<String, dynamic>? meta;
    for (final item in settings.recentScripts) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(item));
        if (decoded[SecureScriptStore.recordIdKey] ==
                settings.lastScriptSessionId ||
            decoded['sessionId'] == settings.lastScriptSessionId) {
          meta = decoded;
          break;
        }
      } catch (e) {
        LightweightDiagnostics.instance.record(
          'script',
          'ignored malformed recent script metadata',
          data: {
            'source': 'storedScriptMetadata',
            'sessionId': settings.lastScriptSessionId,
            'error': e.toString(),
          },
        );
      }
    }
    SecureScriptData? data;
    try {
      data = await SecureScriptStore().read(settings.lastScriptSessionId);
    } catch (error, stackTrace) {
      LightweightDiagnostics.instance.recordError(
        error,
        stackTrace,
        source: 'script-provider-secure-read',
      );
      return;
    }
    if (_isDisposed ||
        generation != _storedLoadGeneration ||
        _hasActiveScript) {
      return;
    }
    if (data == null || data.text.isEmpty) {
      LightweightDiagnostics.instance.record(
        'script',
        'stored script could not be loaded',
        data: {
          'sessionId': settings.lastScriptSessionId,
          'hasData': data != null,
          'hasText': data?.text.isNotEmpty == true,
        },
      );
      return;
    }
    try {
      state = _buildScript(
        data.text,
        title: settings.lastScriptTitle.isNotEmpty
            ? settings.lastScriptTitle
            : meta?['title'] as String?,
        sourceType: meta?['type'] as String?,
        sourcePath: meta?['sourcePath'] as String?,
        sessionId: meta?['sessionId'] as String?,
        historyJson: data.historyJson,
        historyIndex: meta?['historyIndex'] as int?,
        fontSize: (meta?['style']?['fontSize'] as num?)?.toDouble(),
        fontFamily: meta?['style']?['fontFamily'] as String?,
        lineSpacing: (meta?['style']?['lineSpacing'] as num?)?.toDouble(),
        letterSpacing: (meta?['style']?['letterSpacing'] as num?)?.toDouble(),
        wordSpacing: (meta?['style']?['wordSpacing'] as num?)?.toDouble(),
        textAlign: meta?['style']?['textAlign'] as String?,
        scriptBgColor: meta?['style']?['scriptBgColor'] as int?,
        currentWordColor: meta?['style']?['currentWordColor'] as int?,
        futureWordColor: meta?['style']?['futureWordColor'] as int?,
      );
    } on StateError catch (error, stackTrace) {
      LightweightDiagnostics.instance.recordError(
        error,
        stackTrace,
        source: 'script-provider-load',
      );
    }
  }

  Script _buildScript(
    String text, {
    String? title,
    String? sourceType,
    String? sourcePath,
    String? sessionId,
    String? historyJson,
    int? historyIndex,
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? wordSpacing,
    String? textAlign,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
    bool tokenize = true,
  }) {
    final words = tokenize ? WordAligner.tokenize(text) : const <ScriptWord>[];
    final isRtl = text.isHebrew;

    // v3.9.5.46: Pull baseline from settings if not provided by import
    final settings = ref.read(settingsProvider);

    return Script(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title ??
          (text.split('\n').first.trim().isNotEmpty
              ? text.split('\n').first.trim().substring(
                  0, text.split('\n').first.trim().length.clamp(0, 40))
              : 'Script'),
      rawText: text,
      words: words,
      isRtl: isRtl,
      sourceType: sourceType ?? 'TEMP',
      sourcePath: sourcePath,
      sessionId: sessionId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      historyJson: historyJson,
      historyIndex: historyIndex ?? -1,
      fontSize: fontSize ?? settings.fontSize,
      fontFamily: fontFamily ?? 'Inter',
      lineSpacing: lineSpacing ?? settings.lineSpacing,
      letterSpacing: letterSpacing ?? settings.letterSpacing,
      wordSpacing: wordSpacing ?? settings.wordSpacing,
      textAlign: textAlign ?? settings.textAlign,
      scriptBgColor: scriptBgColor ?? settings.scriptBgColor,
      currentWordColor: currentWordColor ?? settings.currentWordColor,
      futureWordColor: futureWordColor ?? settings.futureWordColor,
    );
  }

  void loadText(
    String text, {
    String? title,
    String? sourceType,
    String? sourcePath,
    String? sessionId,
    String? historyJson,
    int? historyIndex,
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? wordSpacing,
    String? textAlign,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
    bool persist = true,
    bool tokenize = true,
  }) {
    state = _buildScript(
      text,
      title: title,
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
      tokenize: tokenize,
    );
    LightweightDiagnostics.instance.record(
      'script',
      'script loaded',
      data: {
        'title': state?.title,
        'sourceType': state?.sourceType,
        'sessionId': state?.sessionId,
        'charCount': text.length,
        'persist': persist,
      },
    );
    if (persist) {
      ref.read(settingsProvider.notifier).saveScript(
            text,
            title: title,
            type: sourceType,
            sourcePath: sourcePath,
            sessionId: sessionId,
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
            historyJson: historyJson,
          );
    }
  }

  Future<void> updateStyleMetadata({
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? wordSpacing,
    String? textAlign,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
  }) async {
    final current = state;
    if (current == null) return;
    final next = current.copyWith(
      fontSize: fontSize,
      fontFamily: fontFamily,
      lineSpacing: lineSpacing,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textAlign: textAlign,
      scriptBgColor: scriptBgColor,
      currentWordColor: currentWordColor,
      futureWordColor: futureWordColor,
    );
    state = next;
    await ref.read(settingsProvider.notifier).saveScript(
          next.rawText,
          title: next.title,
          type: next.sourceType,
          sourcePath: next.sourcePath,
          historyIndex: next.historyIndex,
          sessionId: next.sessionId,
          fontSize: next.fontSize,
          fontFamily: next.fontFamily,
          lineSpacing: next.lineSpacing,
          letterSpacing: next.letterSpacing,
          wordSpacing: next.wordSpacing,
          textAlign: next.textAlign,
          scriptBgColor: next.scriptBgColor,
          currentWordColor: next.currentWordColor,
          futureWordColor: next.futureWordColor,
          historyJson: next.historyJson,
        );
  }

  double effectiveFontSize(double fallback) {
    final current = state;
    if (current == null) return fallback;
    return _uniformInlineFontSize(current.words) ?? current.fontSize;
  }

  Future<void> applyBaseFontSize(double size) async {
    final clamped = size.clamp(14.0, 120.0).toDouble();
    await ref.read(settingsProvider.notifier).setFontSize(clamped);

    final current = state;
    if (current == null) return;
    final uniformInlineSize = _uniformInlineFontSize(current.words);
    final rawText = uniformInlineSize == null
        ? current.rawText
        : _stripUniformInlineFontSize(current.rawText, uniformInlineSize);
    final next = current.copyWith(
      rawText: rawText,
      words: rawText == current.rawText
          ? current.words
          : WordAligner.tokenize(rawText),
      fontSize: clamped,
    );
    state = next;
    await ref.read(settingsProvider.notifier).saveScript(
          next.rawText,
          title: next.title,
          type: next.sourceType,
          sourcePath: next.sourcePath,
          historyIndex: next.historyIndex,
          sessionId: next.sessionId,
          fontSize: next.fontSize,
          fontFamily: next.fontFamily,
          lineSpacing: next.lineSpacing,
          letterSpacing: next.letterSpacing,
          wordSpacing: next.wordSpacing,
          textAlign: next.textAlign,
          scriptBgColor: next.scriptBgColor,
          currentWordColor: next.currentWordColor,
          futureWordColor: next.futureWordColor,
          historyJson: next.historyJson,
        );
  }

  static double? _uniformInlineFontSize(List<ScriptWord> words) {
    double? size;
    for (final word in words) {
      if (word.isNewline) continue;
      final wordSize = word.fontSize;
      if (wordSize == null) return null;
      if (size == null) {
        size = wordSize;
      } else if ((size - wordSize).abs() > 0.001) {
        return null;
      }
    }
    return size;
  }

  static String _stripUniformInlineFontSize(String text, double fontSize) {
    final withoutOpenTags = text.replaceAllMapped(
      RegExp(r'\[size=(\d+(?:\.\d+)?)\]'),
      (match) {
        final value = double.tryParse(match.group(1)!);
        return value != null && (value - fontSize).abs() < 0.001
            ? ''
            : match.group(0)!;
      },
    );
    return withoutOpenTags.replaceAll('[/size]', '');
  }

  Future<ParsedFile> parseFile(File file) async {
    final lower = file.path.toLowerCase();
    ParsedFile result = ParsedFile('');

    try {
      final byteLength = await file.length();
      _validateImportFileSize(lower, byteLength);
      final rawBytes = await file.readAsBytes();
      if (lower.endsWith('.docx')) {
        result = _parseDocx(rawBytes);
      } else if (lower.endsWith('.pages')) {
        result = _parsePages(rawBytes);
      } else if (lower.endsWith('.rtf') || lower.endsWith('.doc')) {
        final rawRtf = latin1.decode(rawBytes);
        if (rawRtf.trimLeft().startsWith('{\\rtf')) {
          result = _parseRtf(rawRtf);
        } else if (lower.endsWith('.rtf')) {
          // Non-RTF content in a .rtf file (e.g. saved before the fix) - treat as UTF-8
          final raw = utf8.decode(rawBytes, allowMalformed: true);
          result = ParsedFile(raw.trim());
        } else {
          // Legacy .doc binary files - strip non-printable bytes
          final content = String.fromCharCodes(
            rawBytes.where(
                (b) => (b >= 0x20 && b < 0x7F) || b == 0x0A || b == 0x0D),
          ).replaceAll(RegExp(r'[ \t]{3,}'), '  ').trim();
          result = ParsedFile(content);
        }
      } else {
        result = ParsedFile(utf8.decode(rawBytes, allowMalformed: true));
      }
    } catch (e) {
      final errStr = e.toString();
      LightweightDiagnostics.instance.record(
        'import',
        'file import failed',
        data: {
          'extension': lower.contains('.') ? lower.split('.').last : 'unknown',
          'safetyLimit': e is ImportSafetyException,
          'error': errStr,
        },
      );
      String errContent = '';
      if (errStr.contains('Central Directory') || errStr.contains('Format')) {
        errContent =
            'This file appears to be corrupted or is not a valid ${file.path.split('.').last.toUpperCase()} file.';
      } else {
        errContent = 'Error loading file: $errStr';
      }
      result = ParsedFile(errContent, errorMessage: errContent);
    }
    return result;
  }

  void _validateImportFileSize(String lowerPath, int byteLength) {
    final isArchive =
        lowerPath.endsWith('.docx') || lowerPath.endsWith('.pages');
    final maxBytes = isArchive ? _maxArchiveImportBytes : _maxPlainImportBytes;
    if (byteLength > maxBytes) {
      final mb = (maxBytes / (1024 * 1024)).round();
      throw ImportSafetyException(
        'This file is too large to import safely. '
        'The current limit for this format is ${mb}MB.',
      );
    }
  }

  Archive _decodeCheckedArchive(List<int> rawBytes, String format) {
    final archive = ZipDecoder().decodeBytes(rawBytes);
    if (archive.files.length > _maxArchiveEntries) {
      throw ImportSafetyException(
        '$format has too many internal files to import safely.',
      );
    }
    var expandedBytes = 0;
    for (final file in archive.files) {
      expandedBytes += file.size;
      if (expandedBytes > _maxArchiveExpandedBytes) {
        throw ImportSafetyException(
          '$format expands to too much data to import safely.',
        );
      }
    }
    return archive;
  }

  List<int> _archiveFileBytes(
    ArchiveFile file, {
    required String format,
    bool isXml = false,
  }) {
    final maxBytes = isXml ? _maxImportXmlBytes : _maxArchiveExpandedBytes;
    if (file.size > maxBytes) {
      throw ImportSafetyException(
        '$format contains an internal file that is too large to import safely.',
      );
    }
    final dynamic rawContent = file.content;
    final bytes = rawContent is List<int>
        ? rawContent
        : List<int>.from(rawContent as Iterable);
    if (bytes.length > maxBytes) {
      throw ImportSafetyException(
        '$format contains an internal file that is too large to import safely.',
      );
    }
    return bytes;
  }

  Future<void> importFile(File file) async {
    final settingsBeforeImport = ref.read(settingsProvider);
    final result = await parseFile(file);
    if (result.isError) return;
    if (result.text.isNotEmpty) {
      final parsedSettings = ref.read(settingsProvider);
      final settingsNotifier = ref.read(settingsProvider.notifier);
      if (settingsBeforeImport.importColorMode ==
          AppSettings.importColorModeDocument) {
        final parsedBgChanged =
            parsedSettings.scriptBgColor != settingsBeforeImport.scriptBgColor;
        await settingsNotifier.setDocumentImportAppearance(
          scriptBgColor: parsedBgChanged ? parsedSettings.scriptBgColor : null,
        );
      } else {
        await settingsNotifier.resetToDefaultAppearance();
      }
      final title = file.path.split(RegExp(r'[\\/]')).last;
      final extension =
          title.contains('.') ? title.split('.').last.toUpperCase() : 'FILE';
      loadText(result.text,
          title: title,
          sourceType: extension,
          sourcePath: file.path,
          fontSize: result.fontSize);
    }
  }

  void updateHistory(int historyIndex, String historyJson) {
    if (state == null) return;
    state = state!.copyWith(
      historyIndex: historyIndex,
      historyJson: historyJson,
    );
  }

  void clear() {
    state = null;
    LightweightDiagnostics.instance.record('script', 'script cleared');
    ref.read(settingsProvider.notifier).saveScript('', title: '');
  }

  void discardActive() {
    state = null;
    LightweightDiagnostics.instance.record('script', 'script discarded');
  }
}

final scriptProvider =
    NotifierProvider<ScriptNotifier, Script?>(ScriptNotifier.new);
