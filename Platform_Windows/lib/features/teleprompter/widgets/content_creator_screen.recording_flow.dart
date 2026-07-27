part of 'content_creator_screen.dart';

extension _ContentCreatorRecordingFlow on _ContentCreatorScreenState {
  Future<void> _playRecordingCountdownTick() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.recordingCountdownTick',
      );
    }
  }

  Future<void> _playRecordingStartCue() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.recordingStartCue',
      );
    }
  }
}
