/// Ported from Windows. `isWindows` there gates touch/mouse-drag input
/// locking to the desktop manual-scroll drag gesture; Android has the same
/// concept (block manual drag-scroll while STT is actively listening, unless
/// the user has explicitly enabled active-manual-scroll-during-session) so
/// callers should pass `true` for that parameter on Android, not gate it
/// behind a platform check the way Windows nominally does (Windows' own
/// check is always true within its own project - this mirrors that shape).
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
