import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/script.dart';
import '../models/script_word.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/extensions/string_extensions.dart';
import '../../../features/teleprompter/services/word_aligner.dart';

part 'script_provider.docx.dart';
part 'script_provider.pages_rtf.dart';
part 'script_provider.models.dart';

class ScriptNotifier extends Notifier<Script?> {
  @override
  Script? build() {
    // Load last saved script on startup
    final settings = ref.read(settingsProvider);
    final lastText = settings.lastScript;
    final lastTitle = settings.lastScriptTitle;

    String sourceType = 'TEMP';
    String? sessionId;
    int? historyIndex;
    String? historyJson;
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
          final metaIdx = meta['historyIndex'];
          if (metaIdx != null) historyIndex = metaIdx;
          final metaHistJson = meta['historyJson'];
          if (metaHistJson is String) historyJson = metaHistJson;

          // v3.9.5.70: Extract styling metadata (Nested for Gallery Compatibility)
          final style = meta['style'] as Map<String, dynamic>?;
          if (style != null) {
            if (style['fontSize'] != null)
              fontSize = (style['fontSize'] as num).toDouble();
            if (style['fontFamily'] != null) fontFamily = style['fontFamily'];
            if (style['lineSpacing'] != null)
              lineSpacing = (style['lineSpacing'] as num).toDouble();
            if (style['letterSpacing'] != null)
              letterSpacing = (style['letterSpacing'] as num).toDouble();
            if (style['wordSpacing'] != null)
              wordSpacing = (style['wordSpacing'] as num).toDouble();
            if (style['textAlign'] != null) textAlign = style['textAlign'];
            if (style['scriptBgColor'] != null)
              scriptBgColor = style['scriptBgColor'];
            if (style['currentWordColor'] != null)
              currentWordColor = style['currentWordColor'];
            if (style['futureWordColor'] != null)
              futureWordColor = style['futureWordColor'];
          }

          break;
        }
      } catch (_) {}
    }

    if (lastText.isNotEmpty) {
      return _buildScript(
        lastText,
        title: lastTitle.isNotEmpty ? lastTitle : null,
        sourceType: sourceType,
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

  Script _buildScript(
    String text, {
    String? title,
    String? sourceType,
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
  }) {
    final words = WordAligner.tokenize(text);
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
  }) {
    state = _buildScript(
      text,
      title: title,
      sourceType: sourceType,
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
    );
    ref.read(settingsProvider.notifier).saveScript(
          text,
          title: title,
          type: sourceType,
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

  Future<_ParsedFile> parseFile(File file) async {
    final lower = file.path.toLowerCase();
    final rawBytes = await file.readAsBytes();
    _ParsedFile result = _ParsedFile('');

    try {
      if (lower.endsWith('.docx')) {
        result = _parseDocx(rawBytes);
      } else if (lower.endsWith('.pages')) {
        result = _parsePages(rawBytes);
      } else if (lower.endsWith('.rtf') || lower.endsWith('.doc')) {
        final raw = utf8.decode(rawBytes, allowMalformed: true);
        if (raw.trimLeft().startsWith('{\\rtf')) {
          result = _parseRtf(raw);
        } else if (lower.endsWith('.rtf')) {
          // Non-RTF content in a .rtf file (e.g. saved before the fix) â€” treat as UTF-8
          result = _ParsedFile(raw.trim());
        } else {
          // Legacy .doc binary files â€” strip non-printable bytes
          final content = String.fromCharCodes(
            rawBytes.where(
                (b) => (b >= 0x20 && b < 0x7F) || b == 0x0A || b == 0x0D),
          ).replaceAll(RegExp(r'[ \t]{3,}'), '  ').trim();
          result = _ParsedFile(content);
        }
      } else {
        result = _ParsedFile(utf8.decode(rawBytes, allowMalformed: true));
      }
    } catch (e) {
      final errStr = e.toString();
      String errContent = '';
      if (errStr.contains('Central Directory') || errStr.contains('Format')) {
        errContent =
            'This file appears to be corrupted or is not a valid ${file.path.split('.').last.toUpperCase()} file.';
      } else {
        errContent = 'Error loading file: $errStr';
      }
      result = _ParsedFile(errContent);
    }
    return result;
  }

  Future<void> importFile(File file) async {
    final result = await parseFile(file);
    if (result.text.isNotEmpty) {
      final title = file.path.split('/').last;
      final extension =
          title.contains('.') ? title.split('.').last.toUpperCase() : 'FILE';
      loadText(result.text,
          title: title, sourceType: extension, fontSize: result.fontSize);
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
    ref.read(settingsProvider.notifier).saveScript('', title: '');
  }
}

final scriptProvider =
    NotifierProvider<ScriptNotifier, Script?>(ScriptNotifier.new);

extension ScriptUtils on Script {
  Script copyWith({
    String? title,
    String? rawText,
    List<ScriptWord>? words,
    bool? isRtl,
    String? sourceType,
    String? sessionId,
    String? historyJson,
  }) {
    return Script(
      id: id,
      title: title ?? this.title,
      rawText: rawText ?? this.rawText,
      words: words ?? this.words,
      isRtl: isRtl ?? this.isRtl,
      sourceType: sourceType ?? this.sourceType,
      sessionId: sessionId ?? this.sessionId,
      historyJson: historyJson ?? this.historyJson,
    );
  }
}
