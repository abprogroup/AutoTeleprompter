part of 'app_settings_screen.dart';

extension _AppSettingsSpeechInput on _AppSettingsScreenState {
  List<Widget> _languageAndSpeechSection(AppSettings settings) {
    final sttBusy = Platform.isWindows
        ? ref.watch(
            teleprompterProvider.select(
              (state) => state.isStarting || state.isListening,
            ),
          )
        : false;

    return [
      const _SectionHeader(title: 'LANGUAGE'),
      const SizedBox(height: 8),
      _SettingsChoiceTile<String>(
        icon: Icons.translate_outlined,
        title: 'Speech recognition language',
        subtitle: _languageModeDescription(settings.languageMode),
        value: settings.languageMode,
        choices: const [
          _SettingsChoice(
            label: 'Auto',
            value: AppSettings.languageModeAuto,
          ),
          _SettingsChoice(
            label: 'Hebrew',
            value: AppSettings.languageModeHebrew,
          ),
          _SettingsChoice(
            label: 'English',
            value: AppSettings.languageModeEnglish,
          ),
        ],
        onChanged: ref.read(settingsProvider.notifier).setLanguageMode,
      ),
      if (Platform.isWindows) ...[
        const SizedBox(height: 8),
        WindowsSttEngineSelector(
          value: settings.sttEngine,
          enabled: !sttBusy,
          accentColor: const Color(0xFFFFBF00),
          backgroundColor: const Color(0xFF1A1A1A),
          onChanged: ref.read(settingsProvider.notifier).setSttEngine,
        ),
      ],
    ];
  }

  String _languageModeDescription(String mode) {
    switch (mode) {
      case AppSettings.languageModeHebrew:
        return 'Prefer Hebrew speech recognition when starting sessions';
      case AppSettings.languageModeEnglish:
        return 'Prefer English speech recognition when starting sessions';
      default:
        return 'Detect script language automatically when possible';
    }
  }
}
