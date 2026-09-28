import 'package:autoteleprompter/features/settings/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const currentReleaseEngine = AppSettings.sttEngineBrowserSmartCompatibility;

  group('AppSettings.normalizeSttEngine current-release boundary', () {
    test('new settings default to the hidden in-app speech path', () {
      expect(const AppSettings().sttEngine, currentReleaseEngine);
    });

    test('every persisted engine value migrates to hidden in-app speech', () {
      const persistedValues = <String?>[
        null,
        AppSettings.sttEngineAuto,
        AppSettings.sttEngineWindowsOffline,
        AppSettings.sttEngineBrowserOnline,
        AppSettings.sttEngineBrowserExternalEdge,
        AppSettings.sttEngineBrowserExternalChrome,
        AppSettings.sttEngineBrowserSmartCompatibility,
        AppSettings.sttEngineWhisperTiny,
        AppSettings.sttEngineWhisperBase,
        AppSettings.sttEngineWhisperSmall,
        AppSettings.sttEngineWhisperMedium,
        'google',
        'unexpected',
      ];

      for (final value in persistedValues) {
        expect(
          AppSettings.normalizeSttEngine(value),
          currentReleaseEngine,
          reason:
              'Persisted STT engine "$value" must not reactivate a '
              'future or external speech engine.',
        );
      }
    });

    test('normalization never returns an external or Whisper engine', () {
      const unsupportedCurrentReleaseEngines = <String>{
        AppSettings.sttEngineWindowsOffline,
        AppSettings.sttEngineBrowserExternalEdge,
        AppSettings.sttEngineBrowserExternalChrome,
        AppSettings.sttEngineWhisperTiny,
        AppSettings.sttEngineWhisperBase,
        AppSettings.sttEngineWhisperSmall,
        AppSettings.sttEngineWhisperMedium,
      };

      for (final value in unsupportedCurrentReleaseEngines) {
        expect(
          unsupportedCurrentReleaseEngines,
          isNot(contains(AppSettings.normalizeSttEngine(value))),
          reason: 'The current release must sanitize "$value".',
        );
      }
    });
  });
}
