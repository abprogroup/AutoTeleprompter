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
part 'script_provider.docx_numbering.dart';
part 'script_provider.pages_rtf.dart';
part 'script_provider.imports.dart';
part 'script_provider.models.dart';

const int _maxPlainImportBytes = 25 * 1024 * 1024;
const int _maxArchiveImportBytes = 80 * 1024 * 1024;
const int _maxArchiveEntries = 2000;
const int _maxArchiveExpandedBytes = 120 * 1024 * 1024;
const int _maxImportXmlBytes = 30 * 1024 * 1024;

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
    final settings = ref.read(settingsProvider);
    scheduleStoredScriptLoad(settings);
    final lastText = settings.lastScript;
    final lastTitle = settings.lastScriptTitle;

    String sourceType = 'TEMP';
    String? sessionId;
    int? historyIndex;
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
      } catch (_) {}
    }

    if (lastText.isNotEmpty) {
      return _buildScript(
        lastText,
        title: lastTitle.isNotEmpty ? lastTitle : null,
        sourceType: sourceType,
        sourcePath: sourcePath,
        sessionId: sessionId,
        historyIndex: historyIndex ?? settings.lastHistoryIndex,
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

  bool get _hasActiveScript => state != null;

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
        final secureId = SecureScriptStore.recordIdFromMetadata(decoded);
        if (secureId == settings.lastScriptSessionId ||
            decoded['sessionId'] == settings.lastScriptSessionId) {
          meta = decoded;
          break;
        }
      } catch (_) {}
    }
    try {
      final data = await SecureScriptStore().read(settings.lastScriptSessionId);
      if (_isDisposed || generation != _storedLoadGeneration || data == null) {
        return;
      }
      state = _buildScript(
        data.text,
        title: settings.lastScriptTitle.isNotEmpty
            ? settings.lastScriptTitle
            : meta?['title'] as String?,
        sourceType: meta?['type'] as String?,
        sourcePath: meta?['sourcePath'] as String?,
        sessionId: meta?['sessionId'] as String?,
        historyJson: data.historyJson,
        historyIndex: (meta?['historyIndex'] as num?)?.toInt(),
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
    } catch (error, stackTrace) {
      LightweightDiagnostics.instance.recordError(
        error,
        stackTrace,
        source: 'script-provider-ios-secure-read',
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
    );
    if (!persist) return;
    ref.read(settingsProvider.notifier).saveScript(
          text,
          title: title,
          sourcePath: sourcePath,
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

  /// Keep the in-memory script state in sync with the editor's current undo
  /// position. Without this, re-entering the editor reads the stale historyIndex
  /// that was set when the script was first loaded, ignoring any undo/redo.
  void updateHistoryIndex(int index) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(historyIndex: index);
  }

  void clear() {
    state = null;
    ref.read(settingsProvider.notifier).saveScript('', title: '');
  }
}

final scriptProvider =
    NotifierProvider<ScriptNotifier, Script?>(ScriptNotifier.new);
