import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

export '../models/app_settings.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  static const _fontSizeKey = 'fontSize';
  static const _languageKey = 'languageMode';
  static const _scrollLeadKey = 'scrollLead';
  static const _lastScriptKey = 'lastScript';
  static const _scrollModeKey = 'scrollMode';
  static const _scrollSpeedKey = 'scrollSpeed';
  static const _textAlignKey = 'textAlign';
  static const _mirrorHorizontalKey = 'mirrorHorizontal';
  static const _mirrorVerticalKey = 'mirrorVertical';
  static const _flipRotationKey = 'flipRotation';
  static const _lineSpacingKey = 'lineSpacing';
  static const _wordSpacingKey = 'wordSpacing';
  static const _letterSpacingKey = 'letterSpacing';
  static const _scriptBgColorKey = 'scriptBgColor';
  static const _currentWordColorKey = 'currentWordColor';
  static const _futureWordColorKey = 'futureWordColor';
  static const _pastWordOpacityKey = 'pastWordOpacity';
  static const _debugModeKey = 'debugMode';
  static const _videoResolutionKey = 'videoResolution';
  static const _recentScriptsKey = 'recentScripts';
  static const _displayNameKey = 'displayName';
  static const _lastTextColorKey = 'lastTextColor';
  static const _lastHighlightColorKey = 'lastHighlightColor';
  static const _lastImportPathKey = 'lastImportPath';
  static const _lastHistoryIndexKey = 'lastHistoryIndex';
  static const _showCurrentWordHighlightKey = 'showCurrentWordHighlight';
  static const _showUpcomingWordColorKey = 'showUpcomingWordColor';
  static const _fontFamilyKey = 'fontFamily';
  static const _showAlignmentOverrideKey = 'showAlignmentOverride';
  static const _sttEngineKey = 'sttEngine';
  static const _readFadeIntensityKey = 'readFadeIntensity';
  static const _sttInputDeviceIdKey = 'sttInputDeviceId';
  static const _sttInputDeviceLabelKey = 'sttInputDeviceLabel';
  static const _sttVisibleSkipEnabledKey = 'sttVisibleSkipEnabled';
  static const _sttStrictBulletModeKey = 'sttStrictBulletMode';
  static const _sttHardVisibleSkipEnabledKey = 'sttHardVisibleSkipEnabled';
  static const _sttManualProfileEnabledKey = 'sttManualProfileEnabled';
  static const _sttManualStartAdvanceSmallWordsKey =
      'sttManualStartAdvanceSmallWords';
  static const _sttManualStartAdvanceBigWordsKey =
      'sttManualStartAdvanceBigWords';
  static const _sttManualSafetySmallWordsKey = 'sttManualSafetySmallWords';
  static const _sttManualSafetyBigWordsKey = 'sttManualSafetyBigWords';
  static const _sttManualVisibleSkipSmallWordsKey =
      'sttManualVisibleSkipSmallWords';
  static const _sttManualVisibleSkipBigWordsKey =
      'sttManualVisibleSkipBigWords';
  static const _sttManualBigWordMinLettersKey = 'sttManualBigWordMinLetters';

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawRecents = prefs.getStringList(_recentScriptsKey) ?? [];

    // v3.9.5.55: Institutional Heuristic Healer (Data Reconstruction)
    final List<String> sanitizedRecents = [];
    bool needsResave = false;

    for (final json in rawRecents) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(json));
        bool itemModified = false;

        // 1. Repair Type Integrity (PDF/DOCX/RTF guessing)
        if (decoded['type'] == null || decoded['type'] == 'FILE') {
          final String title = (decoded['title'] ?? '').toLowerCase();
          String guessedType = 'FILE';
          if (title.endsWith('.pdf'))
            guessedType = 'PDF';
          else if (title.endsWith('.docx') || title.endsWith('.doc'))
            guessedType = 'DOCX';
          else if (title.endsWith('.rtf'))
            guessedType = 'RTF';
          else if (title.endsWith('.txt')) guessedType = 'TXT';

          decoded['type'] = guessedType;
          itemModified = true;
        }

        // 2. Repair Date/Session IDs
        if (decoded['lastModified'] == null) {
          decoded['lastModified'] = DateTime.now().toIso8601String();
          itemModified = true;
        }
        if (decoded['date'] == null) {
          // Format date for UI compatibility (e.g. Apr 10, 2026)
          decoded['date'] = 'Imported Script';
          itemModified = true;
        }
        if (decoded['sessionId'] == null) {
          decoded['sessionId'] =
              'rec_${DateTime.now().millisecondsSinceEpoch}_${rawRecents.indexOf(json)}';
          itemModified = true;
        }

        if (itemModified) needsResave = true;
        sanitizedRecents.add(jsonEncode(decoded));
      } catch (_) {
        sanitizedRecents.add(json); // Preservation
      }
    }

    if (needsResave) {
      await prefs.setStringList(_recentScriptsKey, sanitizedRecents);
    }

    final manualStartSmall =
        (prefs.getInt(_sttManualStartAdvanceSmallWordsKey) ?? 4)
            .clamp(2, 8)
            .toInt();
    final manualStartBig = (prefs.getInt(_sttManualStartAdvanceBigWordsKey) ??
            (manualStartSmall <= 2 ? 1 : manualStartSmall - 1))
        .clamp(1, 8)
        .toInt();
    final manualSafetySmall =
        (prefs.getInt(_sttManualSafetySmallWordsKey) ?? 2).clamp(1, 5).toInt();
    final manualSafetyBig = (prefs.getInt(_sttManualSafetyBigWordsKey) ??
            (manualSafetySmall <= 2 ? 1 : manualSafetySmall - 1))
        .clamp(1, 5)
        .toInt();
    final manualVisibleSmall =
        (prefs.getInt(_sttManualVisibleSkipSmallWordsKey) ?? 0)
            .clamp(0, 8)
            .toInt();
    final manualVisibleBig = (prefs.getInt(_sttManualVisibleSkipBigWordsKey) ??
            (manualVisibleSmall <= 0
                ? 0
                : (manualVisibleSmall <= 2 ? 1 : manualVisibleSmall - 1)))
        .clamp(0, 8)
        .toInt();
    final manualBigWordMinLetters =
        (prefs.getInt(_sttManualBigWordMinLettersKey) ?? 5)
            .clamp(3, 10)
            .toInt();

    state = AppSettings(
      fontSize:
          (prefs.getDouble(_fontSizeKey) ?? 20.0).clamp(14.0, 120.0).toDouble(),
      languageMode: prefs.getString(_languageKey) ?? 'auto',
      scrollLead: prefs.getDouble(_scrollLeadKey) ?? 0.32,
      lastScript: prefs.getString(_lastScriptKey) ?? '',
      lastScriptTitle: prefs.getString('last_script_title') ?? '',
      scrollMode: prefs.getString(_scrollModeKey) ?? 'auto',
      scrollSpeed: prefs.getDouble(_scrollSpeedKey) ?? 100.0,
      textAlign: prefs.getString(_textAlignKey) ?? 'center',
      mirrorHorizontal: prefs.getBool(_mirrorHorizontalKey) ?? false,
      mirrorVertical: prefs.getBool(_mirrorVerticalKey) ?? false,
      flipRotation: prefs.getInt(_flipRotationKey) ?? 0,
      lineSpacing: prefs.getDouble(_lineSpacingKey) ?? 1.2,
      wordSpacing: prefs.getDouble(_wordSpacingKey) ?? 0.0,
      letterSpacing: prefs.getDouble(_letterSpacingKey) ?? 0.0,
      scriptBgColor: prefs.getInt(_scriptBgColorKey) ?? 0xFF000000,
      currentWordColor: prefs.getInt(_currentWordColorKey) ?? 0xFFFFBF00,
      futureWordColor: prefs.getInt(_futureWordColorKey) ?? 0xFFFFFFFF,
      pastWordOpacity: prefs.getDouble(_pastWordOpacityKey) ?? 0.3,
      debugMode: prefs.getBool(_debugModeKey) ?? false,
      videoResolution: prefs.getString(_videoResolutionKey) ?? '720p',
      recentScripts: sanitizedRecents,
      displayName: prefs.getString(_displayNameKey) ?? 'Guest',
      lastTextColor: prefs.getInt(_lastTextColorKey) ?? 0xFFFFBF00,
      lastHighlightColor: prefs.getInt(_lastHighlightColorKey) ?? 0x4DFFFFFF,
      lastImportPath: prefs.getString(_lastImportPathKey) ?? '',
      lastHistoryIndex: prefs.getInt(_lastHistoryIndexKey) ?? -1,
      showCurrentWordHighlight:
          prefs.getBool(_showCurrentWordHighlightKey) ?? true,
      showUpcomingWordColor: prefs.getBool(_showUpcomingWordColorKey) ?? false,
      fontFamily: prefs.getString(_fontFamilyKey) ?? 'Inter',
      showAlignmentOverride: prefs.getBool(_showAlignmentOverrideKey) ?? false,
      sttEngine: prefs.getString(_sttEngineKey) ?? 'google',
      readFadeIntensity: prefs.getDouble(_readFadeIntensityKey) ?? 0.0,
      sttInputDeviceId: prefs.getString(_sttInputDeviceIdKey) ?? '',
      sttInputDeviceLabel: prefs.getString(_sttInputDeviceLabelKey) ??
          'System default microphone',
      sttVisibleSkipEnabled: prefs.getBool(_sttVisibleSkipEnabledKey) ?? false,
      sttStrictBulletMode: prefs.getBool(_sttStrictBulletModeKey) ?? false,
      sttHardVisibleSkipEnabled:
          prefs.getBool(_sttHardVisibleSkipEnabledKey) ?? false,
      sttManualProfileEnabled:
          prefs.getBool(_sttManualProfileEnabledKey) ?? false,
      sttManualStartAdvanceSmallWords: manualStartSmall,
      sttManualStartAdvanceBigWords: manualStartBig,
      sttManualSafetySmallWords: manualSafetySmall,
      sttManualSafetyBigWords: manualSafetyBig,
      sttManualVisibleSkipSmallWords: manualVisibleSmall,
      sttManualVisibleSkipBigWords: manualVisibleBig,
      sttManualBigWordMinLetters: manualBigWordMinLetters,
    );
  }

  Future<void> setFontSize(double size) async {
    final clamped = size.clamp(14.0, 120.0).toDouble();
    state = state.copyWith(fontSize: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, clamped);
  }

  Future<void> setLanguageMode(String mode) async {
    state = state.copyWith(languageMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, mode);
  }

  Future<void> setScrollLead(double lead) async {
    state = state.copyWith(scrollLead: lead);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrollLeadKey, lead);
  }

  Future<void> saveScript(
    String text, {
    String? title,
    String? type,
    int? historyIndex,
    String? sessionId,
    bool isSilent = false,
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? wordSpacing,
    String? textAlign,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
    String? historyJson,
  }) async {
    final currentTitle = title ?? state.lastScriptTitle;

    // v3.36.7: Silent Persistence Guard
    if (!isSilent) {
      state = state.copyWith(
        lastScript: text,
        lastScriptTitle: currentTitle,
        lastHistoryIndex: historyIndex ?? state.lastHistoryIndex,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastScriptKey, text);
    if (title != null) {
      await prefs.setString('last_script_title', title);
    }

    // v3.9.8.1: Mandatory recentList sync to preserve Undo state
    final recentList = List<String>.from(state.recentScripts);
    bool updated = false;
    final matchKey = sessionId ?? (historyIndex != null ? null : currentTitle);

    for (int i = 0; i < recentList.length; i++) {
      try {
        final decoded = jsonDecode(recentList[i]);
        final itemSessionId = decoded['sessionId'];
        final itemTitle = decoded['title'];

        bool isMatch = false;
        if (sessionId != null && itemSessionId == sessionId) {
          isMatch = true;
        } else if (sessionId == null && itemTitle == currentTitle) {
          isMatch = true;
        }

        if (isMatch) {
          decoded['fullText'] = text;
          if (historyIndex != null) decoded['historyIndex'] = historyIndex;
          if (type != null) decoded['type'] = type;
          if (decoded['type'] == null) decoded['type'] = 'FILE';
          if (historyJson != null) decoded['historyJson'] = historyJson;

          // v3.9.5.70: Persist detected/applied metadata (Nested for Gallery Compatibility)
          final styleMap = decoded['style'] as Map<String, dynamic>? ?? {};
          if (fontSize != null) styleMap['fontSize'] = fontSize;
          if (fontFamily != null) styleMap['fontFamily'] = fontFamily;
          if (lineSpacing != null) styleMap['lineSpacing'] = lineSpacing;
          if (letterSpacing != null) styleMap['letterSpacing'] = letterSpacing;
          if (wordSpacing != null) styleMap['wordSpacing'] = wordSpacing;
          if (textAlign != null) styleMap['textAlign'] = textAlign;
          if (scriptBgColor != null) styleMap['scriptBgColor'] = scriptBgColor;
          if (currentWordColor != null)
            styleMap['currentWordColor'] = currentWordColor;
          if (futureWordColor != null)
            styleMap['futureWordColor'] = futureWordColor;

          if (styleMap.isNotEmpty) decoded['style'] = styleMap;

          // v3.9.5.56: Positional Sovereignty (Lift-and-Prepend)
          recentList.removeAt(i);
          recentList.insert(0, jsonEncode(decoded));

          updated = true;
          break;
        }
      } catch (_) {}
    }

    if (updated) {
      if (!isSilent) {
        state = state.copyWith(recentScripts: recentList);
      }
      await prefs.setStringList(_recentScriptsKey, recentList);
    } else if (sessionId != null) {
      // v3.9.5.52: Automatic Prepention for new sessions
      final newEntry = {
        'title': currentTitle,
        'fullText': text,
        'type': type ?? 'FILE', // v3.9.5.54: Restore Label Integrity
        'sessionId': sessionId,
        'historyIndex': historyIndex ?? 0,
        'lastModified': DateTime.now().toIso8601String(),
        // v3.9.5.70: Initial metadata baseline (Nested for Gallery Compatibility)
        'style': {
          if (fontSize != null) 'fontSize': fontSize,
          if (fontFamily != null) 'fontFamily': fontFamily,
          if (lineSpacing != null) 'lineSpacing': lineSpacing,
          if (letterSpacing != null) 'letterSpacing': letterSpacing,
          if (wordSpacing != null) 'wordSpacing': wordSpacing,
          if (textAlign != null) 'textAlign': textAlign,
          if (scriptBgColor != null) 'scriptBgColor': scriptBgColor,
          if (currentWordColor != null) 'currentWordColor': currentWordColor,
          if (futureWordColor != null) 'futureWordColor': futureWordColor,
        },
        'historyJson': historyJson,
      };
      recentList.insert(0, jsonEncode(newEntry));
      if (!isSilent) {
        state = state.copyWith(recentScripts: recentList);
      }
      await prefs.setStringList(_recentScriptsKey, recentList);
    }

    if (historyIndex != null) {
      await prefs.setInt(_lastHistoryIndexKey, historyIndex);
    }
  }

  Future<void> setScrollMode(String mode) async {
    state = state.copyWith(scrollMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scrollModeKey, mode);
  }

  Future<void> setScrollSpeed(double speed) async {
    state = state.copyWith(scrollSpeed: speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrollSpeedKey, speed);
  }

  Future<void> setTextAlign(String align) async {
    state = state.copyWith(textAlign: align);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textAlignKey, align);
  }

  Future<void> setMirrorHorizontal(bool mirror) async {
    state = state.copyWith(mirrorHorizontal: mirror);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mirrorHorizontalKey, mirror);
  }

  Future<void> setMirrorVertical(bool flip) async {
    state = state.copyWith(mirrorVertical: flip);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mirrorVerticalKey, flip);
  }

  Future<void> setFlipRotation(int degrees) async {
    state = state.copyWith(flipRotation: degrees);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_flipRotationKey, degrees);
  }

  Future<void> setLineSpacing(double spacing) async {
    // v3.9.5.69: Allow ultra-tight spacing but clamp at 0.1 to avoid layout crashes
    final clamped = spacing < 0.1 ? 0.1 : spacing;
    state = state.copyWith(lineSpacing: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lineSpacingKey, clamped);
  }

  Future<void> setWordSpacing(double spacing) async {
    state = state.copyWith(wordSpacing: spacing);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_wordSpacingKey, spacing);
  }

  Future<void> setLetterSpacing(double spacing) async {
    state = state.copyWith(letterSpacing: spacing);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_letterSpacingKey, spacing);
  }

  Future<void> setScriptBgColor(int color) async {
    state = state.copyWith(scriptBgColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scriptBgColorKey, color);
  }

  Future<void> setCurrentWordColor(int color) async {
    state = state.copyWith(currentWordColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentWordColorKey, color);
  }

  Future<void> setFutureWordColor(int color) async {
    state = state.copyWith(futureWordColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_futureWordColorKey, color);
  }

  Future<void> setPastWordOpacity(double opacity) async {
    state = state.copyWith(pastWordOpacity: opacity);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pastWordOpacityKey, opacity);
  }

  Future<void> toggleDebugMode() async {
    final newVal = !state.debugMode;
    state = state.copyWith(debugMode: newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debugModeKey, newVal);
  }

  Future<void> setVideoResolution(String resolution) async {
    state = state.copyWith(videoResolution: resolution);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_videoResolutionKey, resolution);
  }

  Future<void> addToRecent(String metadataJson) async {
    final list = List<String>.from(state.recentScripts);
    final Map<String, dynamic> newData = jsonDecode(metadataJson);
    final String? newSessionId = newData['sessionId'] as String?;
    final String? newFullText = newData['fullText'] as String?;
    final String? newTitle = newData['title'] as String?;

    // Text Normalization Helper
    String normalize(String? t) => (t ?? '').replaceAll('\r', '').trim();
    final String normalizedNewText = normalize(newFullText);

    // Smart Upsert: Deduplicate by sessionId OR (fullText + title)
    // Smart Upsert: Deduplicate by title (Primary) or sessionId
    list.removeWhere((item) {
      try {
        final decoded = jsonDecode(item);
        final bool idMatch =
            newSessionId != null && decoded['sessionId'] == newSessionId;
        final bool titleMatch =
            newTitle != null && decoded['title'] == newTitle;
        return idMatch || titleMatch;
      } catch (e) {
        return false;
      }
    });

    // Insert the latest version at the top
    list.insert(0, metadataJson);
    if (list.length > 20) list.removeLast();

    state = state.copyWith(recentScripts: list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentScriptsKey, list);
  }

  Future<void> removeFromRecent(String sessionId) async {
    final list = List<String>.from(state.recentScripts);
    list.removeWhere((item) {
      try {
        final decoded = jsonDecode(item);
        return decoded['sessionId'] == sessionId;
      } catch (e) {
        return false;
      }
    });

    state = state.copyWith(recentScripts: list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentScriptsKey, list);
  }

  Future<void> setDisplayName(String name) async {
    state = state.copyWith(displayName: name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
  }

  Future<void> setLastChosenTextColor(int color) async {
    state = state.copyWith(lastTextColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastTextColorKey, color);
  }

  Future<void> setLastChosenHighlightColor(int color) async {
    state = state.copyWith(lastHighlightColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastHighlightColorKey, color);
  }

  Future<void> resetToDefaultAppearance() async {
    // v3.9.5.60: Calibrated defaults â€” line spacing 1.2 matches AppSettings baseline
    state = state.copyWith(
      scriptBgColor: 0xFF000000,
      currentWordColor: 0xFFFFBF00,
      futureWordColor: 0xFFFFFFFF,
      lineSpacing: 1.2,
      wordSpacing: 0.0,
      letterSpacing: 0.0,
      fontSize: 18.0,
      fontFamily: 'Inter',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scriptBgColorKey, 0xFF000000);
    await prefs.setInt(_currentWordColorKey, 0xFFFFBF00);
    await prefs.setInt(_futureWordColorKey, 0xFFFFFFFF);
    await prefs.setDouble(_lineSpacingKey, 1.2);
    await prefs.setDouble(_wordSpacingKey, 0.0);
    await prefs.setDouble(_letterSpacingKey, 0.0);
    await prefs.setDouble(_fontSizeKey, 18.0);
    await prefs.setString(_fontFamilyKey, 'Inter');
  }

  Future<void> applySessionStyles(Map<String, dynamic> styles) async {
    // Apply saved styles from a specific session
    state = state.copyWith(
      scriptBgColor: styles['scriptBgColor'] ?? state.scriptBgColor,
      currentWordColor: styles['currentWordColor'] ?? state.currentWordColor,
      futureWordColor: styles['futureWordColor'] ?? state.futureWordColor,
      lineSpacing:
          (styles['lineSpacing'] as num?)?.toDouble() ?? state.lineSpacing,
      wordSpacing:
          (styles['wordSpacing'] as num?)?.toDouble() ?? state.wordSpacing,
      letterSpacing:
          (styles['letterSpacing'] as num?)?.toDouble() ?? state.letterSpacing,
      fontSize: (styles['fontSize'] as num?)?.toDouble() ?? state.fontSize,
      fontFamily: styles['fontFamily'] ?? state.fontFamily,
    );
    final prefs = await SharedPreferences.getInstance();
    if (styles.containsKey('scriptBgColor'))
      await prefs.setInt(_scriptBgColorKey, styles['scriptBgColor']);
    if (styles.containsKey('currentWordColor'))
      await prefs.setInt(_currentWordColorKey, styles['currentWordColor']);
    if (styles.containsKey('futureWordColor'))
      await prefs.setInt(_futureWordColorKey, styles['futureWordColor']);
    if (styles.containsKey('lineSpacing'))
      await prefs.setDouble(
          _lineSpacingKey, (styles['lineSpacing'] as num).toDouble());
    if (styles.containsKey('wordSpacing'))
      await prefs.setDouble(
          _wordSpacingKey, (styles['wordSpacing'] as num).toDouble());
    if (styles.containsKey('letterSpacing'))
      await prefs.setDouble(
          _letterSpacingKey, (styles['letterSpacing'] as num).toDouble());
    if (styles.containsKey('fontSize'))
      await prefs.setDouble(
          _fontSizeKey, (styles['fontSize'] as num).toDouble());
    if (styles.containsKey('fontFamily'))
      await prefs.setString(_fontFamilyKey, styles['fontFamily']);
  }

  Future<void> setFontFamily(String family) async {
    state = state.copyWith(fontFamily: family);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontFamilyKey, family);
  }

  Future<void> setLastImportPath(String path) async {
    state = state.copyWith(lastImportPath: path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastImportPathKey, path);
  }

  void applyPreset(String type) {
    switch (type) {
      case 'Classic':
        state = state.copyWith(
          fontSize: 42,
          lineSpacing: 1.7,
          currentWordColor: 0xFFFFBF00, // Amber
          scriptBgColor: 0xFF000000,
          futureWordColor: 0xFFFFFFFF,
        );
        break;
      case 'High Contrast':
        state = state.copyWith(
          fontSize: 48,
          lineSpacing: 1.8,
          currentWordColor: 0xFF00FF00, // Green
          scriptBgColor: 0xFF000000,
          futureWordColor: 0xFFFFFFFF,
        );
        break;
      case 'Modern Soft':
        state = state.copyWith(
          fontSize: 38,
          lineSpacing: 1.6,
          currentWordColor: 0xFF00BFFF, // DeepSkyBlue
          scriptBgColor: 0xFF121212,
          futureWordColor: 0xFFE0E0E0,
        );
        break;
    }
  }

  Future<void> setShowCurrentWordHighlight(bool val) async {
    state = state.copyWith(showCurrentWordHighlight: val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showCurrentWordHighlightKey, val);
  }

  Future<void> setShowUpcomingWordColor(bool val) async {
    state = state.copyWith(showUpcomingWordColor: val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showUpcomingWordColorKey, val);
  }

  Future<void> setShowAlignmentOverride(bool val) async {
    state = state.copyWith(showAlignmentOverride: val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showAlignmentOverrideKey, val);
  }

  Future<void> setSttEngine(String engine) async {
    state = state.copyWith(sttEngine: engine);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sttEngineKey, engine);
  }

  Future<void> setReadFadeIntensity(double intensity) async {
    state = state.copyWith(readFadeIntensity: intensity);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_readFadeIntensityKey, intensity);
  }

  Future<void> setSttInputDevice(String deviceId, String label) async {
    final normalizedLabel =
        label.trim().isEmpty ? 'System default microphone' : label.trim();
    state = state.copyWith(
      sttInputDeviceId: deviceId,
      sttInputDeviceLabel: normalizedLabel,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sttInputDeviceIdKey, deviceId);
    await prefs.setString(_sttInputDeviceLabelKey, normalizedLabel);
  }

  Future<void> setSttVisibleSkipEnabled(bool enabled) async {
    state = state.copyWith(
      sttVisibleSkipEnabled: enabled,
      sttHardVisibleSkipEnabled:
          enabled ? state.sttHardVisibleSkipEnabled : false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sttVisibleSkipEnabledKey, enabled);
    if (!enabled) {
      await prefs.setBool(_sttHardVisibleSkipEnabledKey, false);
    }
  }

  Future<void> setSttStrictBulletMode(bool enabled) async {
    state = state.copyWith(sttStrictBulletMode: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sttStrictBulletModeKey, enabled);
  }

  Future<void> setSttHardVisibleSkipEnabled(bool enabled) async {
    final active = state.sttVisibleSkipEnabled && enabled;
    state = state.copyWith(sttHardVisibleSkipEnabled: active);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sttHardVisibleSkipEnabledKey, active);
  }

  Future<void> setSttManualProfileEnabled(bool enabled) async {
    state = state.copyWith(sttManualProfileEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sttManualProfileEnabledKey, enabled);
  }

  Future<void> setSttManualStartAdvanceSmallWords(int value) async {
    final clamped = value.clamp(2, 8).toInt();
    state = state.copyWith(sttManualStartAdvanceSmallWords: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualStartAdvanceSmallWordsKey, clamped);
  }

  Future<void> setSttManualStartAdvanceBigWords(int value) async {
    final clamped = value.clamp(1, 8).toInt();
    state = state.copyWith(sttManualStartAdvanceBigWords: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualStartAdvanceBigWordsKey, clamped);
  }

  Future<void> setSttManualSafetySmallWords(int value) async {
    final clamped = value.clamp(1, 5).toInt();
    state = state.copyWith(sttManualSafetySmallWords: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualSafetySmallWordsKey, clamped);
  }

  Future<void> setSttManualSafetyBigWords(int value) async {
    final clamped = value.clamp(1, 5).toInt();
    state = state.copyWith(sttManualSafetyBigWords: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualSafetyBigWordsKey, clamped);
  }

  Future<void> setSttManualVisibleSkipSmallWords(int value) async {
    final normalized = value <= 0 ? 0 : value.clamp(2, 8).toInt();
    final nextBig = normalized <= 0
        ? 0
        : (state.sttManualVisibleSkipBigWords <= 0
            ? 3
            : state.sttManualVisibleSkipBigWords);
    state = state.copyWith(
      sttManualVisibleSkipSmallWords: normalized,
      sttManualVisibleSkipBigWords: nextBig,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualVisibleSkipSmallWordsKey, normalized);
    await prefs.setInt(_sttManualVisibleSkipBigWordsKey, nextBig);
  }

  Future<void> setSttManualVisibleSkipBigWords(int value) async {
    final normalized = value <= 0 ? 0 : value.clamp(1, 8).toInt();
    final nextSmall = normalized <= 0
        ? 0
        : (state.sttManualVisibleSkipSmallWords <= 0
            ? 4
            : state.sttManualVisibleSkipSmallWords);
    state = state.copyWith(
      sttManualVisibleSkipSmallWords: nextSmall,
      sttManualVisibleSkipBigWords: normalized,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualVisibleSkipSmallWordsKey, nextSmall);
    await prefs.setInt(_sttManualVisibleSkipBigWordsKey, normalized);
  }

  Future<void> setSttManualBigWordMinLetters(int value) async {
    final clamped = value.clamp(3, 10).toInt();
    state = state.copyWith(sttManualBigWordMinLetters: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualBigWordMinLettersKey, clamped);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
