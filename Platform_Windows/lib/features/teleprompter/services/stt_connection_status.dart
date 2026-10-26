/// Transient connection notices, not fatal errors or speech/movement evidence.
/// Stored in the existing statusMessage contract; never persisted in settings.
abstract final class SttConnectionStatus {
  static const reconnecting = 'Reconnecting speech. Your place is saved.';
  static const offline =
      'Offline. Speech will retry when the connection returns. Your place is saved.';
  static const awaitingSpeech =
      'Speech restarted; waiting for speech. Please repeat the last line.';
  static const matching =
      'Speech received; finding your place. Repeat a visible phrase if needed.';

  static bool isTransient(String message) =>
      message == reconnecting ||
      message == offline ||
      message == awaitingSpeech ||
      message == matching;

  static String badge(String message) => switch (message) {
    offline => 'OFFLINE',
    awaitingSpeech => 'WAITING',
    matching => 'MATCHING',
    _ => 'RECONNECTING',
  };
}
