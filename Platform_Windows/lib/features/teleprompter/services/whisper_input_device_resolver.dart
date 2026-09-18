import 'package:record/record.dart';

Future<InputDevice?> resolveWhisperInputDevice({
  required AudioRecorder recorder,
  required String preferredLabel,
  void Function(String)? onDiagnostic,
}) async {
  final preferred = preferredLabel.trim();
  if (preferred.isEmpty ||
      preferred.toLowerCase() == 'system default microphone') {
    _safeDiagnostic(
      onDiagnostic,
      '[Whisper] Microphone: Windows system default input',
    );
    return null;
  }

  try {
    final target = _normalizeInputLabel(preferred);
    final devices = await recorder.listInputDevices();
    InputDevice? partialMatch;
    for (final device in devices) {
      final candidate = _normalizeInputLabel(device.label);
      if (candidate == target) {
        _safeDiagnostic(
          onDiagnostic,
          '[Whisper] Using configured microphone: $preferred',
        );
        return device;
      }
      if (target.length >= 4 &&
          (candidate.contains(target) || target.contains(candidate))) {
        partialMatch ??= device;
      }
    }
    if (partialMatch != null) {
      _safeDiagnostic(
        onDiagnostic,
        '[Whisper] Matched configured microphone: $preferred',
      );
      return partialMatch;
    }
  } catch (_) {
    // Enumeration may be unavailable even when default capture still works.
  }
  _safeDiagnostic(
    onDiagnostic,
    '[Whisper] Configured microphone unavailable; using Windows system default.',
  );
  return null;
}

String _normalizeInputLabel(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

void _safeDiagnostic(void Function(String)? callback, String message) {
  try {
    callback?.call(message);
  } catch (_) {}
}
