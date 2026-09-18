import 'package:autoteleprompter/features/settings/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings.normalizeSttEngine', () {
    test('uses Smart compatibility for new settings', () {
      expect(
        const AppSettings().sttEngine,
        AppSettings.sttEngineBrowserSmartCompatibility,
      );
    });

    test('preserves explicit supported engine values', () {
      expect(
        AppSettings.normalizeSttEngine(AppSettings.sttEngineWindowsOffline),
        AppSettings.sttEngineWhisperTiny,
      );
      expect(
        AppSettings.normalizeSttEngine(AppSettings.sttEngineBrowserOnline),
        AppSettings.sttEngineBrowserOnline,
      );
      expect(
        AppSettings.normalizeSttEngine(
          AppSettings.sttEngineBrowserExternalEdge,
        ),
        AppSettings.sttEngineBrowserExternalEdge,
      );
      expect(
        AppSettings.normalizeSttEngine(
          AppSettings.sttEngineBrowserExternalChrome,
        ),
        AppSettings.sttEngineBrowserExternalChrome,
      );
      expect(
        AppSettings.normalizeSttEngine(
          AppSettings.sttEngineBrowserSmartCompatibility,
        ),
        AppSettings.sttEngineBrowserSmartCompatibility,
      );
      expect(
        AppSettings.normalizeSttEngine(AppSettings.sttEngineWhisperTiny),
        AppSettings.sttEngineWhisperTiny,
      );
      expect(
        AppSettings.normalizeSttEngine(AppSettings.sttEngineWhisperBase),
        AppSettings.sttEngineWhisperTiny,
      );
    });

    test('migrates legacy and missing values to Smart compatibility', () {
      expect(
        AppSettings.normalizeSttEngine(AppSettings.sttEngineAuto),
        AppSettings.sttEngineBrowserSmartCompatibility,
      );
      expect(
        AppSettings.normalizeSttEngine(null),
        AppSettings.sttEngineBrowserSmartCompatibility,
      );
      expect(
        AppSettings.normalizeSttEngine('google'),
        AppSettings.sttEngineBrowserSmartCompatibility,
      );
      expect(
        AppSettings.normalizeSttEngine('unexpected'),
        AppSettings.sttEngineBrowserSmartCompatibility,
      );
    });
  });
}
