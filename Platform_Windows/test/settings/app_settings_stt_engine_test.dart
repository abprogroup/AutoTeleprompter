import 'package:autoteleprompter/features/settings/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const defaultEngine = AppSettings.sttEngineBrowserSmartCompatibility;
  const supportedOfflineEngines = <String>[
    AppSettings.sttEngineOfflineNemo80Streaming,
    AppSettings.sttEngineOfflineNemo480Streaming,
    AppSettings.sttEngineOfflineKroko64Streaming,
    AppSettings.sttEngineOfflineKrokoStreaming,
    AppSettings.sttEngineOfflineZipformerFast,
    AppSettings.sttEngineOfflineZipformerPrecision,
    AppSettings.sttEngineOfflineParakeetV3,
    AppSettings.sttEngineOfflineParakeetV2,
  ];

  group('AppSettings.normalizeSttEngine', () {
    test('new settings default to the hidden in-app speech path', () {
      expect(const AppSettings().sttEngine, defaultEngine);
      expect(AppSettings.isOfflineSherpaEngine(defaultEngine), isFalse);
    });

    test('preserves supported offline Sherpa engines', () {
      for (final engine in supportedOfflineEngines) {
        expect(AppSettings.normalizeSttEngine(engine), engine);
        expect(AppSettings.isOfflineSherpaEngine(engine), isTrue);
      }
    });

    test('legacy and unknown persisted values migrate to hidden in-app speech', () {
      const legacyValues = <String?>[
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

      for (final value in legacyValues) {
        expect(
          AppSettings.normalizeSttEngine(value),
          defaultEngine,
          reason:
              'Persisted STT engine "$value" must not reactivate a '
              'legacy or external speech engine.',
        );
      }
    });

    test('normalization never returns an external or Whisper engine', () {
      const unsupportedEngines = <String>{
        AppSettings.sttEngineWindowsOffline,
        AppSettings.sttEngineBrowserExternalEdge,
        AppSettings.sttEngineBrowserExternalChrome,
        AppSettings.sttEngineWhisperTiny,
        AppSettings.sttEngineWhisperBase,
        AppSettings.sttEngineWhisperSmall,
        AppSettings.sttEngineWhisperMedium,
      };

      for (final value in unsupportedEngines) {
        expect(
          unsupportedEngines,
          isNot(contains(AppSettings.normalizeSttEngine(value))),
          reason: 'The current release must sanitize "$value".',
        );
      }
    });
  });
}
