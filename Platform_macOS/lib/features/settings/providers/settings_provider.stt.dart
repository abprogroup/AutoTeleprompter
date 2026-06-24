part of 'settings_provider.dart';

mixin SettingsNotifierSttSettings on Notifier<AppSettings> {
  Future<void> setSttEngine(String engine) async {
    final normalized = _normalizeSttEngine(engine);
    state = state.copyWith(sttEngine: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sttEngineKey, normalized);
  }

  Future<void> setAllowScrollDuringActiveSession(bool enabled) async {
    state = state.copyWith(allowScrollDuringActiveSession: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowScrollDuringActiveSessionKey, enabled);
  }

  Future<void> setReadFadeIntensity(double intensity) async {
    final normalized = intensity.clamp(0.0, 1.0).toDouble();
    state = state.copyWith(readFadeIntensity: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_readFadeIntensityKey, normalized);
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

  Future<void> setSttReliabilityMode(String mode) async {
    final normalized = _normalizeSttReliabilityMode(mode);
    state = state.copyWith(sttReliabilityMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sttReliabilityModeKey, normalized);
  }

  Future<void> setSttPreflightCompletedForVersion(String version) async {
    final sanitized = version.replaceAll(RegExp(r'[\r\n]'), '').trim();
    state = state.copyWith(sttPreflightCompletedForVersion: sanitized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sttPreflightCompletedForVersionKey, sanitized);
  }
}
