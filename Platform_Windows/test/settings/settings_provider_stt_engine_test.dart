import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const defaultEngine = AppSettings.sttEngineBrowserSmartCompatibility;
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
  const offlineEngines = <String>[
    AppSettings.sttEngineOfflineNemo80Streaming,
    AppSettings.sttEngineOfflineNemo480Streaming,
    AppSettings.sttEngineOfflineKroko64Streaming,
    AppSettings.sttEngineOfflineKrokoStreaming,
    AppSettings.sttEngineOfflineZipformerFast,
    AppSettings.sttEngineOfflineZipformerPrecision,
    AppSettings.sttEngineOfflineParakeetV3,
    AppSettings.sttEngineOfflineParakeetV2,
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads every legacy persisted engine as hidden in-app speech', () async {
    for (final persistedValue in legacyValues) {
      final initialValues = <String, Object>{
        'displayName': 'Loaded settings marker',
      };
      if (persistedValue != null) {
        initialValues['sttEngine'] = persistedValue;
      }
      SharedPreferences.setMockInitialValues(initialValues);

      final container = ProviderContainer();
      container.read(settingsProvider);
      await _waitForSettingsLoad(container);

      expect(
        container.read(settingsProvider).sttEngine,
        defaultEngine,
        reason: 'Persisted STT engine "$persistedValue" must be migrated.',
      );
      container.dispose();
    }
  });

  test('persists and reloads supported offline Sherpa engines', () async {
    for (final offlineEngine in offlineEngines) {
      SharedPreferences.setMockInitialValues({
        'displayName': 'Loaded settings marker',
      });
      final container = ProviderContainer();
      container.read(settingsProvider);
      await _waitForSettingsLoad(container);

      await container.read(settingsProvider.notifier).setSttEngine(
        offlineEngine,
      );
      expect(container.read(settingsProvider).sttEngine, offlineEngine);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sttEngine'), offlineEngine);
      container.dispose();

      final reloaded = ProviderContainer();
      reloaded.read(settingsProvider);
      await _waitForSettingsLoad(reloaded);
      expect(reloaded.read(settingsProvider).sttEngine, offlineEngine);
      reloaded.dispose();
    }
  });

  test('setSttEngine sanitizes and persists every legacy choice', () async {
    SharedPreferences.setMockInitialValues({
      'displayName': 'Loaded settings marker',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await _waitForSettingsLoad(container);

    final notifier = container.read(settingsProvider.notifier);
    final prefs = await SharedPreferences.getInstance();
    for (final requestedValue in legacyValues.whereType<String>()) {
      await notifier.setSttEngine(requestedValue);

      expect(
        container.read(settingsProvider).sttEngine,
        defaultEngine,
        reason: 'Requested STT engine "$requestedValue" must be sanitized.',
      );
      expect(
        prefs.getString('sttEngine'),
        defaultEngine,
        reason:
            'Unsupported engine "$requestedValue" must not survive a '
            'restart through preferences.',
      );
    }
  });
}

Future<void> _waitForSettingsLoad(ProviderContainer container) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (container.read(settingsProvider).displayName ==
        'Loaded settings marker') {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Settings did not load before the focused-test deadline.');
}
