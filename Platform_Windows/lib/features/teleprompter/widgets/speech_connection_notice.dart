import 'package:flutter/material.dart';
import '../services/stt_connection_status.dart';

/// Status only: no timers, retry ownership, microphone or position mutations.
class SpeechConnectionBadge extends StatelessWidget {
  final String message;
  final bool isListening;
  final Color recoveryColor;
  const SpeechConnectionBadge({
    super.key,
    required this.message,
    required this.isListening,
    this.recoveryColor = Colors.orangeAccent,
  });

  @override
  Widget build(BuildContext context) {
    final recovering = SttConnectionStatus.isTransient(message);
    final color =
        recovering
            ? recoveryColor
            : isListening
            ? Colors.greenAccent
            : Colors.red;
    final label =
        recovering
            ? SttConnectionStatus.badge(message)
            : isListening
            ? 'MIC READY'
            : 'IDLE';
    return Tooltip(
      message: recovering ? message : label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            recovering
                ? Icons.sync
                : isListening
                ? Icons.mic
                : Icons.mic_off,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class SpeechConnectionNotice extends StatelessWidget {
  final String message;
  final Color recoveryColor;
  const SpeechConnectionNotice({
    super.key,
    required this.message,
    this.recoveryColor = Colors.orangeAccent,
  });

  @override
  Widget build(BuildContext context) {
    if (!SttConnectionStatus.isTransient(message)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.92),
            border: Border.all(color: recoveryColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: recoveryColor, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
