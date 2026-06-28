part of 'settings_provider.dart';

const _stableSttEngine = 'google';
const _stableSttEngines = {_stableSttEngine};

String sanitizeSttEngine(String? engine) {
  return _stableSttEngines.contains(engine) ? engine! : _stableSttEngine;
}

mixin SettingsNotifierSttProfile on Notifier<AppSettings> {
  Future<void> setSttEngine(String engine) async {
    final safeEngine = sanitizeSttEngine(engine);
    state = state.copyWith(sttEngine: safeEngine);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sttEngineKey, safeEngine);
  }

  Future<void> setReadFadeIntensity(double intensity) async {
    state = state.copyWith(readFadeIntensity: intensity);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_readFadeIntensityKey, intensity);
  }

  Future<void> setShowSoundLevelMeter(bool enabled) async {
    state = state.copyWith(showSoundLevelMeter: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showSoundLevelMeterKey, enabled);
  }

  Future<void> setSttVisibleSkipEnabled(bool enabled) async {
    state = state.copyWith(
      sttVisibleSkipEnabled: enabled,
      sttHardVisibleSkipEnabled:
          enabled ? state.sttHardVisibleSkipEnabled : false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sttVisibleSkipEnabledKey, enabled);
    if (!enabled) {
      await prefs.setBool(_sttHardVisibleSkipEnabledKey, false);
    }
  }

  Future<void> setAllowScrollDuringActiveSession(bool enabled) async {
    state = state.copyWith(allowScrollDuringActiveSession: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowScrollDuringActiveSessionKey, enabled);
  }

  Future<void> setSttStrictBulletMode(bool enabled) async {
    state = state.copyWith(sttStrictBulletMode: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sttStrictBulletModeKey, enabled);
  }

  Future<void> setSttHardVisibleSkipEnabled(bool enabled) async {
    final active = state.sttVisibleSkipEnabled && enabled;
    state = state.copyWith(sttHardVisibleSkipEnabled: active);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sttHardVisibleSkipEnabledKey, active);
  }

  Future<void> setSttManualProfileEnabled(bool enabled) async {
    state = state.copyWith(sttManualProfileEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sttManualProfileEnabledKey, enabled);
  }

  Future<void> setSttManualStartAdvanceSmallWords(int value) async {
    final clamped = value.clamp(2, 8).toInt();
    state = state.copyWith(sttManualStartAdvanceSmallWords: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualStartAdvanceSmallWordsKey, clamped);
  }

  Future<void> setSttManualStartAdvanceBigWords(int value) async {
    final clamped = value.clamp(1, 8).toInt();
    state = state.copyWith(sttManualStartAdvanceBigWords: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualStartAdvanceBigWordsKey, clamped);
  }

  Future<void> setSttManualSafetySmallWords(int value) async {
    final clamped = value.clamp(1, 5).toInt();
    state = state.copyWith(sttManualSafetySmallWords: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualSafetySmallWordsKey, clamped);
  }

  Future<void> setSttManualSafetyBigWords(int value) async {
    final clamped = value.clamp(1, 5).toInt();
    state = state.copyWith(sttManualSafetyBigWords: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualSafetyBigWordsKey, clamped);
  }

  Future<void> setSttManualVisibleSkipSmallWords(int value) async {
    final normalized = value <= 0 ? 0 : value.clamp(2, 8).toInt();
    final nextBig = normalized <= 0
        ? 0
        : (state.sttManualVisibleSkipBigWords <= 0
            ? 3
            : state.sttManualVisibleSkipBigWords);
    state = state.copyWith(
      sttManualVisibleSkipSmallWords: normalized,
      sttManualVisibleSkipBigWords: nextBig,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualVisibleSkipSmallWordsKey, normalized);
    await prefs.setInt(_sttManualVisibleSkipBigWordsKey, nextBig);
  }

  Future<void> setSttManualVisibleSkipBigWords(int value) async {
    final normalized = value <= 0 ? 0 : value.clamp(1, 8).toInt();
    final nextSmall = normalized <= 0
        ? 0
        : (state.sttManualVisibleSkipSmallWords <= 0
            ? 4
            : state.sttManualVisibleSkipSmallWords);
    state = state.copyWith(
      sttManualVisibleSkipSmallWords: nextSmall,
      sttManualVisibleSkipBigWords: normalized,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualVisibleSkipSmallWordsKey, nextSmall);
    await prefs.setInt(_sttManualVisibleSkipBigWordsKey, normalized);
  }

  Future<void> setSttManualBigWordMinLetters(int value) async {
    final clamped = value.clamp(3, 10).toInt();
    state = state.copyWith(sttManualBigWordMinLetters: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sttManualBigWordMinLettersKey, clamped);
  }

  Future<void> setSttInputDevice(String deviceId, String label) async {
    final normalizedLabel =
        label.trim().isEmpty ? 'System default microphone' : label.trim();
    state = state.copyWith(
      sttInputDeviceId: deviceId,
      sttInputDeviceLabel: normalizedLabel,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sttInputDeviceIdKey, deviceId);
    await prefs.setString(_sttInputDeviceLabelKey, normalizedLabel);
  }

  Future<void> setContentCreatorRecordingFormat(String format) async {
    final normalized = switch (format) {
      AppSettings.contentCreatorRecordingFormatAudio =>
        AppSettings.contentCreatorRecordingFormatAudio,
      _ => AppSettings.contentCreatorRecordingFormatMp4,
    };
    state = state.copyWith(contentCreatorRecordingFormat: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorRecordingFormatKey, normalized);
  }

  Future<void> setContentCreatorRecordingAudioMode(String mode) async {
    const normalized = AppSettings.contentCreatorRecordingAudioCamera;
    state = state.copyWith(contentCreatorRecordingAudioMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorRecordingAudioModeKey, normalized);
  }

  Future<void> setContentCreatorRecordingControlsSpeech(bool enabled) async {
    state = state.copyWith(contentCreatorRecordingControlsSpeech: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_contentCreatorRecordingControlsSpeechKey, enabled);
  }

  Future<void> setContentCreatorFeedMode(String mode) async {
    const allowed = {
      AppSettings.contentCreatorFeedStrip,
      AppSettings.contentCreatorFeedBubble,
      AppSettings.contentCreatorFeedFull,
    };
    final normalized =
        allowed.contains(mode) ? mode : AppSettings.contentCreatorFeedStrip;
    state = state.copyWith(contentCreatorFeedMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorFeedModeKey, normalized);
  }
}
