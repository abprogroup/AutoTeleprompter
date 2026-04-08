import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final double fontSize;
  final String languageMode; // 'auto', 'he', 'en'
  final double scrollLead;   // 0.2–0.5, viewport ratio for reading line
  final String lastScript;
  final String lastScriptTitle;
  final String scrollMode;   // 'auto' (speech) | 'manual' (timer)
  final double scrollSpeed;  // words per minute for manual mode
  final String textAlign;    // 'center' | 'left' | 'right'
  final bool mirrorHorizontal; // flip horizontally
  final bool mirrorVertical;   // flip vertically
  final int flipRotation;    // screen rotation: 0, 90, 180, 270 degrees
  final double lineSpacing;  // 1.0–2.5
  final double wordSpacing;  // extra spacing between words (px)
  final double letterSpacing; // extra spacing between letters (px)
  final int scriptBgColor;      // ARGB int, default black
  final int currentWordColor;   // ARGB int, default amber
  final int futureWordColor;    // ARGB int, default white
  final double pastWordOpacity; // 0.0–0.6
  final bool debugMode;         // technical mode for STT logs
  final String videoResolution; // '480p', '720p', '1080p'
  final List<String> recentScripts; // JSON strings of script metadata
  final String displayName;      // User's name
  final int lastTextColor;       // Persisted selection color
  final int lastHighlightColor;  // Persisted selection highlight
  final String lastImportPath;  // Persisted folder path for importer
  final int lastHistoryIndex;    // v3.8 persistence
  final bool showCurrentWordHighlight; // v3.9.5 toggle
  final bool showUpcomingWordColor;    // v3.9.5 toggle (default off)

  const AppSettings({
    this.fontSize = 40.0,
    this.languageMode = 'auto',
    this.scrollLead = 0.32,
    this.lastScript = '',
    this.lastScriptTitle = '',
    this.scrollMode = 'auto',
    this.scrollSpeed = 100.0,
    this.textAlign = 'center',
    this.mirrorHorizontal = false,
    this.mirrorVertical = false,
    this.flipRotation = 0,
    this.lineSpacing = 1.65,
    this.wordSpacing = 6.0,      // default: slightly wider than zero
    this.letterSpacing = 0.5,    // default: subtle extra letter spacing
    this.scriptBgColor = 0xFF000000,
    this.currentWordColor = 0xFFFFBF00,
    this.futureWordColor = 0xFFFFFFFF,
    this.pastWordOpacity = 0.3,
    this.debugMode = false,
    this.videoResolution = '720p',
    this.recentScripts = const [],
    this.displayName = 'Guest',
    this.lastTextColor = 0xFFFFBF00,
    this.lastHighlightColor = 0x4DFFFFFF,
    this.lastImportPath = '',
    this.lastHistoryIndex = -1,
    this.showCurrentWordHighlight = true,
    this.showUpcomingWordColor = false,
  });

  AppSettings copyWith({
    double? fontSize,
    String? languageMode,
    double? scrollLead,
    String? lastScript,
    String? lastScriptTitle,
    String? scrollMode,
    double? scrollSpeed,
    String? textAlign,
    bool? mirrorHorizontal,
    bool? mirrorVertical,
    int? flipRotation,
    double? lineSpacing,
    double? wordSpacing,
    double? letterSpacing,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
    double? pastWordOpacity,
    bool? debugMode,
    String? videoResolution,
    List<String>? recentScripts,
    String? displayName,
    int? lastTextColor,
    int? lastHighlightColor,
    String? lastImportPath,
    int? lastHistoryIndex,
    bool? showCurrentWordHighlight,
    bool? showUpcomingWordColor,
  }) {
    return AppSettings(
      fontSize: fontSize ?? this.fontSize,
      languageMode: languageMode ?? this.languageMode,
      scrollLead: scrollLead ?? this.scrollLead,
      lastScript: lastScript ?? this.lastScript,
      lastScriptTitle: lastScriptTitle ?? this.lastScriptTitle,
      scrollMode: scrollMode ?? this.scrollMode,
      scrollSpeed: scrollSpeed ?? this.scrollSpeed,
      textAlign: textAlign ?? this.textAlign,
      mirrorHorizontal: mirrorHorizontal ?? this.mirrorHorizontal,
      mirrorVertical: mirrorVertical ?? this.mirrorVertical,
      flipRotation: flipRotation ?? this.flipRotation,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      scriptBgColor: scriptBgColor ?? this.scriptBgColor,
      currentWordColor: currentWordColor ?? this.currentWordColor,
      futureWordColor: futureWordColor ?? this.futureWordColor,
      pastWordOpacity: pastWordOpacity ?? this.pastWordOpacity,
      debugMode: debugMode ?? this.debugMode,
      videoResolution: videoResolution ?? this.videoResolution,
      recentScripts: recentScripts ?? this.recentScripts,
      displayName: displayName ?? this.displayName,
      lastTextColor: lastTextColor ?? this.lastTextColor,
      lastHighlightColor: lastHighlightColor ?? this.lastHighlightColor,
      lastImportPath: lastImportPath ?? this.lastImportPath,
      lastHistoryIndex: lastHistoryIndex ?? this.lastHistoryIndex,
      showCurrentWordHighlight: showCurrentWordHighlight ?? this.showCurrentWordHighlight,
      showUpcomingWordColor: showUpcomingWordColor ?? this.showUpcomingWordColor,
    );
  }
}

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

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      fontSize: prefs.getDouble(_fontSizeKey) ?? 40.0,
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
      lineSpacing: prefs.getDouble(_lineSpacingKey) ?? 1.65,
      wordSpacing: prefs.getDouble(_wordSpacingKey) ?? 6.0,
      letterSpacing: prefs.getDouble(_letterSpacingKey) ?? 0.5,
      scriptBgColor: prefs.getInt(_scriptBgColorKey) ?? 0xFF000000,
      currentWordColor: prefs.getInt(_currentWordColorKey) ?? 0xFFFFBF00,
      futureWordColor: prefs.getInt(_futureWordColorKey) ?? 0xFFFFFFFF,
      pastWordOpacity: prefs.getDouble(_pastWordOpacityKey) ?? 0.3,
      debugMode: prefs.getBool(_debugModeKey) ?? false,
      videoResolution: prefs.getString(_videoResolutionKey) ?? '720p',
      recentScripts: prefs.getStringList(_recentScriptsKey) ?? [],
      displayName: prefs.getString(_displayNameKey) ?? 'Guest',
      lastTextColor: prefs.getInt(_lastTextColorKey) ?? 0xFFFFBF00,
      lastHighlightColor: prefs.getInt(_lastHighlightColorKey) ?? 0x4DFFFFFF,
      lastImportPath: prefs.getString(_lastImportPathKey) ?? '',
      lastHistoryIndex: prefs.getInt(_lastHistoryIndexKey) ?? -1,
      showCurrentWordHighlight: prefs.getBool(_showCurrentWordHighlightKey) ?? true,
      showUpcomingWordColor: prefs.getBool(_showUpcomingWordColorKey) ?? false,
    );
  }

  Future<void> setFontSize(double size) async {
    state = state.copyWith(fontSize: size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, size);
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

  Future<void> saveScript(String text, {String? title, int? historyIndex}) async {
    state = state.copyWith(
      lastScript: text, 
      lastScriptTitle: title ?? state.lastScriptTitle,
      lastHistoryIndex: historyIndex ?? state.lastHistoryIndex,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastScriptKey, text);
    if (title != null) {
      await prefs.setString('last_script_title', title);
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
    state = state.copyWith(lineSpacing: spacing);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lineSpacingKey, spacing);
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
    list.removeWhere((item) {
      try {
        final decoded = jsonDecode(item);
        final bool idMatch = newSessionId != null && decoded['sessionId'] == newSessionId;
        final bool contentMatch = newFullText != null && newTitle != null && 
                                 normalize(decoded['fullText'] as String?) == normalizedNewText && 
                                 decoded['title'] == newTitle;
        return idMatch || contentMatch;
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
    // Factory defaults for a clean Teleprompt experience
    state = state.copyWith(
      scriptBgColor: 0xFF000000,
      currentWordColor: 0xFFFFBF00,
      futureWordColor: 0xFFFFFFFF,
      lineSpacing: 1.65,
      wordSpacing: 6.0,
      letterSpacing: 0.5,
      fontSize: 40.0,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scriptBgColorKey, 0xFF000000);
    await prefs.setInt(_currentWordColorKey, 0xFFFFBF00);
    await prefs.setInt(_futureWordColorKey, 0xFFFFFFFF);
    await prefs.setDouble(_lineSpacingKey, 1.65);
    await prefs.setDouble(_wordSpacingKey, 6.0);
    await prefs.setDouble(_letterSpacingKey, 0.5);
    await prefs.setDouble(_fontSizeKey, 40.0);
  }

  Future<void> applySessionStyles(Map<String, dynamic> styles) async {
    // Apply saved styles from a specific session
    state = state.copyWith(
      scriptBgColor: styles['scriptBgColor'] ?? state.scriptBgColor,
      currentWordColor: styles['currentWordColor'] ?? state.currentWordColor,
      futureWordColor: styles['futureWordColor'] ?? state.futureWordColor,
      lineSpacing: styles['lineSpacing'] ?? state.lineSpacing,
      wordSpacing: styles['wordSpacing'] ?? state.wordSpacing,
      letterSpacing: styles['letterSpacing'] ?? state.letterSpacing,
      fontSize: styles['fontSize'] ?? state.fontSize,
    );
    final prefs = await SharedPreferences.getInstance();
    if (styles.containsKey('scriptBgColor')) await prefs.setInt(_scriptBgColorKey, styles['scriptBgColor']);
    if (styles.containsKey('currentWordColor')) await prefs.setInt(_currentWordColorKey, styles['currentWordColor']);
    if (styles.containsKey('futureWordColor')) await prefs.setInt(_futureWordColorKey, styles['futureWordColor']);
    if (styles.containsKey('lineSpacing')) await prefs.setDouble(_lineSpacingKey, styles['lineSpacing']);
    if (styles.containsKey('wordSpacing')) await prefs.setDouble(_wordSpacingKey, styles['wordSpacing']);
    if (styles.containsKey('letterSpacing')) await prefs.setDouble(_letterSpacingKey, styles['letterSpacing']);
    if (styles.containsKey('fontSize')) await prefs.setDouble(_fontSizeKey, styles['fontSize']);
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
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
