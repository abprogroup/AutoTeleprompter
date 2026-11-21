import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/script_provider.dart';
import 'script_folder_import_service.dart';

/// The existing DOCX parser applies background metadata through settings.
/// Preview/import must not change the active reader or persist those settings.
class _ImportSettings extends SettingsNotifier {
  _ImportSettings(this.preferences);
  final AppSettings preferences;
  @override
  AppSettings build() => preferences.copyWith(lastScript: '',
      lastScriptTitle: '', lastScriptSessionId: '', recentScripts: const []);
  @override
  Future<void> setScriptBgColor(int color) async {
    state = state.copyWith(scriptBgColor: color);
  }
}

Future<FolderScriptContent> parseScriptForLibrary(File file,
    {AppSettings preferences = const AppSettings()}) async {
  final container = ProviderContainer(
    overrides: [settingsProvider.overrideWith(() => _ImportSettings(preferences))],
  );
  try {
    final parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    if (parsed.isError) {
      throw FormatException(parsed.errorMessage ?? 'Could not parse this script.');
    }
    final parsedSettings = container.read(settingsProvider);
    // Match the individual-file import policy, but only on this local snapshot.
    final documentColors = preferences.importColorMode == AppSettings.importColorModeDocument;
    final style = documentColors
        ? parsedSettings.copyWith(
            scriptBgColor: parsedSettings.scriptBgColor != preferences.scriptBgColor
                ? parsedSettings.scriptBgColor : 0xFFFFFFFF,
            currentWordColor: 0xFFFFBF00, futureWordColor: 0xFF000000)
        : parsedSettings.copyWith(scriptBgColor: 0xFF000000,
            currentWordColor: 0xFFFFBF00, futureWordColor: 0xFFFFFFFF,
            lineSpacing: 1.2, wordSpacing: 0, letterSpacing: 0,
            fontSize: 18, fontFamily: 'Inter');
    return FolderScriptContent(
      parsed.text,
      style: {
        'fontSize': parsed.fontSize ?? style.fontSize,
        'fontFamily': style.fontFamily,
        'lineSpacing': style.lineSpacing,
        'wordSpacing': style.wordSpacing,
        'letterSpacing': style.letterSpacing,
        'textAlign': style.textAlign,
        'scriptBgColor': style.scriptBgColor,
        'currentWordColor': style.currentWordColor,
        'futureWordColor': style.futureWordColor,
      },
    );
  } finally {
    container.dispose();
  }
}
