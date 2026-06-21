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
    required bool isListening,
    required bool isStarting,
    required bool allowActiveManualScroll,
  }) {
    return (isListening || isStarting) && !allowActiveManualScroll;
  }

  static bool controlsAutoHideActive({
    required bool isListening,
    required bool isStarting,
  }) {
    return isListening || isStarting;
  }
}
