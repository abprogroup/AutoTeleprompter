class PresenterInputLockService {
  const PresenterInputLockService._();

  static bool allowActiveManualScroll({
    required bool settingEnabled,
    required bool isListening,
    required bool isStarting,
  }) {
    return settingEnabled && isListening && !isStarting;
  }

  static bool inputLocked({
    required bool isWindows,
    required bool isListening,
    required bool isStarting,
    required bool allowActiveManualScroll,
  }) {
    return isWindows && (isListening || isStarting) && !allowActiveManualScroll;
  }
}
