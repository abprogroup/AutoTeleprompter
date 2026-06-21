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

  static bool bottomControlsHotZoneContains({
    required double localX,
    required double localY,
    required double surfaceWidth,
    required double surfaceHeight,
    required double hotZoneHeight,
  }) {
    if (surfaceWidth <= 0 || surfaceHeight <= 0 || hotZoneHeight <= 0) {
      return false;
    }
    return localX >= 0 &&
        localX <= surfaceWidth &&
        localY >= surfaceHeight - hotZoneHeight &&
        localY <= surfaceHeight;
  }

  static bool shouldDeferControlsAutoHide({
    required bool hoveringControls,
    required bool pointerInHotZone,
  }) {
    return hoveringControls || pointerInHotZone;
  }

  static bool recordingControlsAutoHideActive({
    required bool isRecording,
    required bool recordStartInFlight,
    required bool isListening,
    required bool isStarting,
  }) {
    return isRecording ||
        recordStartInFlight ||
        controlsAutoHideActive(
          isListening: isListening,
          isStarting: isStarting,
        );
  }
}
