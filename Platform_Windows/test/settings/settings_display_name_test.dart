import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('login seed uses email prefix when display name is still Guest',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(settingsProvider.notifier)
        .seedDisplayNameFromEmail('speaker.name@example.com');

    expect(container.read(settingsProvider).displayName, 'speaker.name');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('displayName'), 'speaker.name');
  });

  test('login seed preserves an existing custom display name', () async {
    SharedPreferences.setMockInitialValues({'displayName': 'Amit'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(settingsProvider.notifier)
        .seedDisplayNameFromEmail('speaker.name@example.com');

    expect(container.read(settingsProvider).displayName, 'Amit');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('displayName'), 'Amit');
  });

  test('manual display name trims input and ignores blank values', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final notifier = container.read(settingsProvider.notifier);
    await notifier.setDisplayName('  Amit Bar  ');

    expect(container.read(settingsProvider).displayName, 'Amit Bar');
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('displayName'), 'Amit Bar');

    await notifier.setDisplayName('   ');

    expect(container.read(settingsProvider).displayName, 'Amit Bar');
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('displayName'), 'Amit Bar');
  });

  test('language mode normalizes and persists', () async {
    SharedPreferences.setMockInitialValues({'languageMode': 'gibberish'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(settingsProvider).languageMode,
      AppSettings.languageModeAuto,
    );

    await container
        .read(settingsProvider.notifier)
        .setLanguageMode(AppSettings.languageModeHebrew);

    expect(
      container.read(settingsProvider).languageMode,
      AppSettings.languageModeHebrew,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('languageMode'), AppSettings.languageModeHebrew);

    await container.read(settingsProvider.notifier).setLanguageMode('bad');
    expect(
      container.read(settingsProvider).languageMode,
      AppSettings.languageModeAuto,
    );
  });

  test('active session manual scrolling override persists', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final notifier = container.read(settingsProvider.notifier);
    await notifier.setAllowScrollDuringActiveSession(true);

    expect(
      container.read(settingsProvider).allowScrollDuringActiveSession,
      isTrue,
    );
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('allowScrollDuringActiveSession'), isTrue);

    await notifier.setAllowScrollDuringActiveSession(false);

    expect(
      container.read(settingsProvider).allowScrollDuringActiveSession,
      isFalse,
    );
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('allowScrollDuringActiveSession'), isFalse);
  });

  test('windows stt engine setting normalizes and persists', () async {
    SharedPreferences.setMockInitialValues({'sttEngine': 'google'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(settingsProvider).sttEngine,
      AppSettings.sttEngineAuto,
    );

    final notifier = container.read(settingsProvider.notifier);
    await notifier.setSttEngine(AppSettings.sttEngineWindowsOffline);

    expect(
      container.read(settingsProvider).sttEngine,
      AppSettings.sttEngineWindowsOffline,
    );
    var prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('sttEngine'),
      AppSettings.sttEngineWindowsOffline,
    );

    await notifier.setSttEngine('unknown');

    expect(
      container.read(settingsProvider).sttEngine,
      AppSettings.sttEngineAuto,
    );
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sttEngine'), AppSettings.sttEngineAuto);
  });

  test('legacy plaintext script keys are removed if secure migration fails',
      () async {
    SharedPreferences.setMockInitialValues({
      'lastScript': 'PRIVATE_SCRIPT_TEXT_SHOULD_NOT_REMAIN',
      'last_script_title': 'Legacy Secret',
      'autosave_script': 'PRIVATE_AUTOSAVE_TEXT_SHOULD_NOT_REMAIN',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(settingsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 25));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('lastScript'), isNull);
    expect(prefs.getString('autosave_script'), isNull);
    expect(container.read(settingsProvider).lastScript, isEmpty);
  });
}
