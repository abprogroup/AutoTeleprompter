import 'abstract_stt_service.dart';

/// Stable lifecycle phases emitted by the browser-hosted speech page.
///
/// These values deliberately describe readiness and failure milestones without
/// carrying session tokens, transcript text, or audio-device identifiers.
enum SttBrowserLifecyclePhase {
  socketConnected,
  microphoneReady,
  recognizerListening,
  speechApiUnavailable,
  permissionDenied,
  disconnected,
  network,
}

/// A validated lifecycle event from the local browser speech host.
class SttBrowserLifecycleEvent {
  const SttBrowserLifecycleEvent(this.phase);

  final SttBrowserLifecyclePhase phase;

  /// Parses only known lifecycle/error messages. Untrusted payload fields are
  /// ignored so they cannot enter diagnostics or runtime-health metadata.
  static SttBrowserLifecycleEvent? fromBrowserMessage(
    Map<String, dynamic> message,
  ) {
    final type = message['type'];
    if (type == 'lifecycle') {
      return _fromWirePhase(message['phase']);
    }

    // Compatibility with an already-loaded page from an earlier app build.
    if (type == 'listening') {
      return const SttBrowserLifecycleEvent(
        SttBrowserLifecyclePhase.recognizerListening,
      );
    }
    if (type == 'inputReady') {
      return const SttBrowserLifecycleEvent(
        SttBrowserLifecyclePhase.microphoneReady,
      );
    }
    if (type == 'error') {
      return _fromErrorCode(message['error']);
    }
    return null;
  }

  static SttBrowserLifecycleEvent? _fromWirePhase(Object? rawPhase) {
    switch (rawPhase) {
      case 'socketConnected':
        return const SttBrowserLifecycleEvent(
          SttBrowserLifecyclePhase.socketConnected,
        );
      case 'microphoneReady':
        return const SttBrowserLifecycleEvent(
          SttBrowserLifecyclePhase.microphoneReady,
        );
      case 'recognizerListening':
        return const SttBrowserLifecycleEvent(
          SttBrowserLifecyclePhase.recognizerListening,
        );
      case 'speechApiUnavailable':
        return const SttBrowserLifecycleEvent(
          SttBrowserLifecyclePhase.speechApiUnavailable,
        );
      case 'permissionDenied':
        return const SttBrowserLifecycleEvent(
          SttBrowserLifecyclePhase.permissionDenied,
        );
      case 'network':
        return const SttBrowserLifecycleEvent(
          SttBrowserLifecyclePhase.network,
        );
      default:
        // Disconnects are server-owned and cannot be asserted by page input.
        return null;
    }
  }

  static SttBrowserLifecycleEvent? _fromErrorCode(Object? rawError) {
    switch (sanitizeSttBrowserErrorCode(rawError)) {
      case 'speech-api-unavailable':
        return const SttBrowserLifecycleEvent(
          SttBrowserLifecyclePhase.speechApiUnavailable,
        );
      case 'not-allowed':
      case 'service-not-allowed':
        return const SttBrowserLifecycleEvent(
          SttBrowserLifecyclePhase.permissionDenied,
        );
      case 'network':
        return const SttBrowserLifecycleEvent(
          SttBrowserLifecyclePhase.network,
        );
      default:
        return null;
    }
  }

  SttRuntimeHealth toRuntimeHealth({
    required String locale,
    required bool hasListened,
  }) {
    final failure = switch (phase) {
      SttBrowserLifecyclePhase.speechApiUnavailable ||
      SttBrowserLifecyclePhase.permissionDenied ||
      SttBrowserLifecyclePhase.disconnected ||
      SttBrowserLifecyclePhase.network =>
        1,
      _ => 0,
    };
    final error = switch (phase) {
      SttBrowserLifecyclePhase.speechApiUnavailable => 'speech-api-unavailable',
      SttBrowserLifecyclePhase.permissionDenied => 'not-allowed',
      SttBrowserLifecyclePhase.disconnected => 'browser-disconnected',
      SttBrowserLifecyclePhase.network => 'network',
      _ => null,
    };

    return SttRuntimeHealth(
      type: phase.name,
      listening: phase == SttBrowserLifecyclePhase.recognizerListening ||
          (phase == SttBrowserLifecyclePhase.network && hasListened),
      locale: locale,
      failures: failure,
      error: error,
    );
  }
}

/// Returns a bounded, non-sensitive browser error code for health events and
/// diagnostics. Arbitrary page-provided text is never forwarded.
String sanitizeSttBrowserErrorCode(Object? rawError) {
  const allowed = <String>{
    'aborted',
    'audio-capture',
    'bad-grammar',
    'input-device-failed',
    'input-device-missing',
    'language-not-supported',
    'network',
    'no-speech',
    'not-allowed',
    'service-not-allowed',
    'speech-api-unavailable',
    'start-failed',
  };
  final value = rawError is String ? rawError : '';
  return allowed.contains(value) ? value : 'unknown';
}
