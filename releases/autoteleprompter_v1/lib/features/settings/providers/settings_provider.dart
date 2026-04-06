import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final double fontSize;
  final String languageMode; // 'auto', 'he', 'en'
  final double scrollLead;   // 0.2–0.5, viewport ratio for reading line
  final String lastScript;
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

  const AppSettings({
    this.fontSize = 40.0,
    this.languageMode = 'auto',
    this.scrollLead = 0.32,
    this.lastScript = '',
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
  });

  AppSettings copyWith({
    double? fontSize,
    String? languageMode,
    double? scrollLead,
    String? lastScript,
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
  }) {
    return AppSettings(
      fontSize: fontSize ?? this.fontSize,
      languageMode: languageMode ?? this.languageMode,
      scrollLead: scrollLead ?? this.scrollLead,
      lastScript: lastScript ?? this.lastScript,
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

  Future<void> saveScript(String text) async {
    state = state.copyWith(lastScript: text);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastScriptKey, text);
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
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
