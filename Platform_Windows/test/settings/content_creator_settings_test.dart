import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('fresh settings load matches immediate app defaults for fade values',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final initial = container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);
    final loaded = container.read(settingsProvider);

    expect(initial.pastWordOpacity, loaded.pastWordOpacity);
    expect(initial.readFadeIntensity, loaded.readFadeIntensity);
    expect(loaded.pastWordOpacity, 0.3);
    expect(loaded.readFadeIntensity, 0.0);
  });

  test('content creator camera source modes normalize and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final notifier = container.read(settingsProvider.notifier);
    await notifier.setContentCreatorCameraSourceMode(
      AppSettings.contentCreatorSourceVirtual,
    );

    expect(
      container.read(settingsProvider).contentCreatorCameraSourceMode,
      AppSettings.contentCreatorSourceVirtual,
    );
    var prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('contentCreatorCameraSourceMode'),
      AppSettings.contentCreatorSourceVirtual,
    );

    await notifier.setContentCreatorCameraSourceMode('wifi_virtual_legacy');

    expect(
      container.read(settingsProvider).contentCreatorCameraSourceMode,
      AppSettings.contentCreatorSourceNative,
    );
    prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('contentCreatorCameraSourceMode'),
      AppSettings.contentCreatorSourceNative,
    );
  });

  test('content creator layout preset and opacity normalize', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final notifier = container.read(settingsProvider.notifier);
    await notifier.setContentCreatorLayoutPreset(
      AppSettings.contentCreatorLayoutCamera,
    );
    await notifier.setContentCreatorCameraOpacity(1.4);

    expect(
      container.read(settingsProvider).contentCreatorLayoutPreset,
      AppSettings.contentCreatorLayoutCamera,
    );
    expect(
      container.read(settingsProvider).contentCreatorCameraOpacity,
      1.0,
    );

    await notifier.setContentCreatorLayoutPreset('unknown_layout');
    await notifier.setContentCreatorCameraOpacity(0.05);

    expect(
      container.read(settingsProvider).contentCreatorLayoutPreset,
      AppSettings.contentCreatorLayoutReading,
    );
    expect(
      container.read(settingsProvider).contentCreatorCameraOpacity,
      0.2,
    );
  });

  test('content creator feed mode and bubble settings persist', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final notifier = container.read(settingsProvider.notifier);
    await notifier.setContentCreatorFeedMode(
      AppSettings.contentCreatorFeedFull,
    );
    await notifier.setContentCreatorBubblePosition(
      AppSettings.contentCreatorBubbleTopLeft,
    );
    await notifier.setContentCreatorBubbleShape(
      AppSettings.contentCreatorBubbleShapeTriangle,
    );
    await notifier.setContentCreatorBubbleOpacity(0.1);
    await notifier.setContentCreatorBubbleRoundness(2.0);
    await notifier.setContentCreatorBubbleSize(0.8);
    await notifier.setContentCreatorBubbleOffsetX(0.8);
    await notifier.setContentCreatorBubbleOffsetY(-0.8);
    await notifier.setManualScrollBarPlacement(
      AppSettings.manualScrollBarLeft,
    );

    expect(
      container.read(settingsProvider).contentCreatorFeedMode,
      AppSettings.contentCreatorFeedFull,
    );
    expect(
      container.read(settingsProvider).contentCreatorBubblePosition,
      AppSettings.contentCreatorBubbleTopLeft,
    );
    expect(
      container.read(settingsProvider).contentCreatorBubbleShape,
      AppSettings.contentCreatorBubbleShapeTriangle,
    );
    expect(container.read(settingsProvider).contentCreatorBubbleOpacity, 0.25);
    expect(container.read(settingsProvider).contentCreatorBubbleRoundness, 1.0);
    expect(container.read(settingsProvider).contentCreatorBubbleSize, 0.60);
    expect(container.read(settingsProvider).contentCreatorBubbleOffsetX, 0.25);
    expect(
      container.read(settingsProvider).contentCreatorBubbleOffsetY,
      -0.25,
    );
    expect(
      container.read(settingsProvider).manualScrollBarPlacement,
      AppSettings.manualScrollBarLeft,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('contentCreatorFeedMode'),
      AppSettings.contentCreatorFeedFull,
    );
    expect(
      prefs.getString('contentCreatorBubblePosition'),
      AppSettings.contentCreatorBubbleTopLeft,
    );
    expect(prefs.getDouble('contentCreatorBubbleOpacity'), 0.25);
    expect(prefs.getDouble('contentCreatorBubbleRoundness'), 1.0);
    expect(
      prefs.getString('contentCreatorBubbleShape'),
      AppSettings.contentCreatorBubbleShapeTriangle,
    );
    expect(prefs.getDouble('contentCreatorBubbleOffsetX'), 0.25);
    expect(prefs.getDouble('contentCreatorBubbleOffsetY'), -0.25);
    expect(
      prefs.getString('manualScrollBarPlacement'),
      AppSettings.manualScrollBarLeft,
    );
  });

  test('content creator bubble and manual scroll settings normalize on load',
      () async {
    SharedPreferences.setMockInitialValues({
      'contentCreatorFeedMode': 'legacy_background',
      'contentCreatorBubblePosition': 'center',
      'contentCreatorBubbleShape': 'pentagon',
      'contentCreatorBubbleSize': 0.01,
      'contentCreatorBubbleOpacity': 9.0,
      'contentCreatorBubbleRoundness': -4.0,
      'contentCreatorBubbleOffsetX': -9.0,
      'contentCreatorBubbleOffsetY': 9.0,
      'manualScrollBarPlacement': 'diagonal',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final settings = container.read(settingsProvider);
    expect(
        settings.contentCreatorFeedMode, AppSettings.contentCreatorFeedBubble);
    expect(
      settings.contentCreatorBubblePosition,
      AppSettings.contentCreatorBubbleBottomRight,
    );
    expect(
      settings.contentCreatorBubbleShape,
      AppSettings.contentCreatorBubbleShapeRounded,
    );
    expect(settings.contentCreatorBubbleSize, 0.04);
    expect(settings.contentCreatorBubbleOpacity, 1.0);
    expect(settings.contentCreatorBubbleRoundness, 0.0);
    expect(settings.contentCreatorBubbleOffsetX, -0.25);
    expect(settings.contentCreatorBubbleOffsetY, 0.25);
    expect(
        settings.manualScrollBarPlacement, AppSettings.manualScrollBarBottom);
  });

  test('content creator feed styling and recording folder persist', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final notifier = container.read(settingsProvider.notifier);
    await notifier.setContentCreatorVignetteIntensity(2);
    await notifier.setContentCreatorFeedBlur(99);
    await notifier.setContentCreatorTextScrim(2);
    await notifier.setContentCreatorRecordingFolder(r'C:\Recordings');

    final settings = container.read(settingsProvider);
    expect(settings.contentCreatorVignetteIntensity, 1.0);
    expect(settings.contentCreatorFeedBlur, 30.0);
    expect(settings.contentCreatorTextScrim, 0.9);
    expect(settings.contentCreatorRecordingFolder, r'C:\Recordings');
  });

  test('content creator recording output stays on native mp4 beta formats',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final notifier = container.read(settingsProvider.notifier);
    await notifier.setContentCreatorRecordingFormat(
      AppSettings.contentCreatorRecordingFormatMp4,
    );
    await notifier.setContentCreatorRecordingAudioMode(
      AppSettings.contentCreatorRecordingAudioSilent,
    );

    var settings = container.read(settingsProvider);
    expect(
      settings.contentCreatorRecordingFormat,
      AppSettings.contentCreatorRecordingFormatMp4,
    );
    expect(
      settings.contentCreatorRecordingAudioMode,
      AppSettings.contentCreatorRecordingAudioSilent,
    );

    await notifier.setContentCreatorRecordingFormat('avi');
    await notifier.setContentCreatorRecordingAudioMode('shared_mic');

    settings = container.read(settingsProvider);
    expect(
      settings.contentCreatorRecordingFormat,
      AppSettings.contentCreatorRecordingFormatMp4,
    );
    expect(
      settings.contentCreatorRecordingAudioMode,
      AppSettings.contentCreatorRecordingAudioCamera,
    );
  });

  test('legacy extra recording formats load as mp4', () async {
    SharedPreferences.setMockInitialValues({
      'contentCreatorRecordingFormat':
          AppSettings.contentCreatorRecordingFormatMovProRes,
      'contentCreatorRecordingAudioMode':
          AppSettings.contentCreatorRecordingAudioSilent,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final settings = container.read(settingsProvider);
    expect(
      settings.contentCreatorRecordingFormat,
      AppSettings.contentCreatorRecordingFormatMp4,
    );
    expect(
      settings.contentCreatorRecordingAudioMode,
      AppSettings.contentCreatorRecordingAudioSilent,
    );
  });

  test('presentation display settings normalize on load and save', () async {
    SharedPreferences.setMockInitialValues({
      'scrollLead': 2.0,
      'scrollSpeed': -999.0,
      'scrollMode': 'teleport',
      'textAlign': 'diagonal',
      'flipRotation': 45,
      'lineSpacing': 99.0,
      'wordSpacing': -99.0,
      'letterSpacing': 99.0,
      'pastWordOpacity': -1.0,
      'scriptBgColor': -5,
      'currentWordColor': 0x1FFFFFFFF,
      'futureWordColor': 0xFF123456,
      'videoResolution': '16k',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    var settings = container.read(settingsProvider);
    expect(settings.scrollLead, 0.60);
    expect(settings.scrollSpeed, -300.0);
    expect(settings.scrollMode, 'auto');
    expect(settings.textAlign, 'center');
    expect(settings.flipRotation, 0);
    expect(settings.lineSpacing, 3.0);
    expect(settings.wordSpacing, -5.0);
    expect(settings.letterSpacing, 5.0);
    expect(settings.pastWordOpacity, 0.05);
    expect(settings.scriptBgColor, 0xFF000000);
    expect(settings.currentWordColor, 0xFFFFBF00);
    expect(settings.futureWordColor, 0xFF123456);
    expect(settings.videoResolution, '720p');

    final notifier = container.read(settingsProvider.notifier);
    await notifier.setScrollLead(-2);
    await notifier.setScrollSpeed(999);
    await notifier.setScrollMode('bad');
    await notifier.setTextAlign('bad');
    await notifier.setFlipRotation(999);
    await notifier.setLineSpacing(-10);
    await notifier.setWordSpacing(99);
    await notifier.setLetterSpacing(-99);
    await notifier.setPastWordOpacity(9);
    await notifier.setReadFadeIntensity(9);
    await notifier.setVideoResolution('4k');

    settings = container.read(settingsProvider);
    expect(settings.scrollLead, 0.15);
    expect(settings.scrollSpeed, 300.0);
    expect(settings.scrollMode, 'auto');
    expect(settings.textAlign, 'center');
    expect(settings.flipRotation, 0);
    expect(settings.lineSpacing, 0.5);
    expect(settings.wordSpacing, 20.0);
    expect(settings.letterSpacing, -2.0);
    expect(settings.pastWordOpacity, 1.0);
    expect(settings.readFadeIntensity, 1.0);
    expect(settings.videoResolution, '720p');

    await notifier.setReadFadeIntensity(-9);
    settings = container.read(settingsProvider);
    expect(settings.readFadeIntensity, 0.0);
  });

  test('session style restore normalizes display values before saving',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final notifier = container.read(settingsProvider.notifier);
    await notifier.applySessionStyles({
      'fontSize': 999.0,
      'lineSpacing': -10.0,
      'wordSpacing': 999.0,
      'letterSpacing': -99.0,
      'textAlign': 'diagonal',
      'scriptBgColor': -1,
      'currentWordColor': 0x1FFFFFFFF,
      'futureWordColor': 0xFFABCDEF,
      'fontFamily': ' Inter ',
    });

    final settings = container.read(settingsProvider);
    expect(settings.fontSize, 120.0);
    expect(settings.lineSpacing, 0.5);
    expect(settings.wordSpacing, 20.0);
    expect(settings.letterSpacing, -2.0);
    expect(settings.textAlign, 'center');
    expect(settings.scriptBgColor, 0xFF000000);
    expect(settings.currentWordColor, 0xFFFFBF00);
    expect(settings.futureWordColor, 0xFFABCDEF);
    expect(settings.fontFamily, 'Inter');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('fontSize'), 120.0);
    expect(prefs.getDouble('lineSpacing'), 0.5);
    expect(prefs.getDouble('wordSpacing'), 20.0);
    expect(prefs.getDouble('letterSpacing'), -2.0);
    expect(prefs.getString('textAlign'), 'center');
    expect(prefs.getInt('scriptBgColor'), 0xFF000000);
    expect(prefs.getInt('currentWordColor'), 0xFFFFBF00);
    expect(prefs.getInt('futureWordColor'), 0xFFABCDEF);
    expect(prefs.getString('fontFamily'), 'Inter');
  });
}
