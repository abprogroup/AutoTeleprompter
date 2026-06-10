part of 'teleprompter_screen.dart';

class _SoundLevelBar extends StatelessWidget {
  final double level;
  final bool isListening;
  final bool isStarting;
  final Color accentColor;
  final bool compact;

  const _SoundLevelBar({
    required this.level,
    required this.isListening,
    required this.isStarting,
    required this.accentColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final clampedLevel = level.clamp(0.0, 1.0).toDouble();
    final activeColor = isListening ? accentColor : Colors.white38;
    final iconSize = compact ? 12.0 : 16.0;
    final barHeight = compact ? 5.0 : 7.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(compact ? 999 : 8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 4 : 7,
        ),
        child: Row(
          children: [
            Icon(
              isStarting
                  ? Icons.hourglass_top
                  : (isListening ? Icons.graphic_eq : Icons.volume_off),
              color: activeColor,
              size: iconSize,
            ),
            SizedBox(width: compact ? 5 : 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: clampedLevel,
                  minHeight: barHeight,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                child: Text(
                  '${(clampedLevel * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SttStartingIndicator extends StatelessWidget {
  final Color accentColor;

  const _SttStartingIndicator({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
            const SizedBox(width: 9),
            const Text(
              'STARTING SPEECH',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Control bar ────────────────────────────────────────────────────────────────
