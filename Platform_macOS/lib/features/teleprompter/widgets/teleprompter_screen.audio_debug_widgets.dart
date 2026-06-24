part of 'teleprompter_screen.dart';

class _SoundLevelBar extends StatelessWidget {
  final double level;
  final bool isListening;
  final bool isStarting;
  final Color accentColor;
  final bool compact;
  final String? qualityLabel;
  final Color? qualityColor;

  const _SoundLevelBar({
    required this.level,
    required this.isListening,
    required this.isStarting,
    required this.accentColor,
    this.compact = false,
    this.qualityLabel,
    this.qualityColor,
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
            if (!compact) ...[
              const Text(
                'Mic signal',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
            ],
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
              if (qualityLabel != null && qualityLabel!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:
                        (qualityColor ?? activeColor).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          (qualityColor ?? activeColor).withValues(alpha: 0.42),
                    ),
                  ),
                  child: Text(
                    qualityLabel!,
                    style: TextStyle(
                      color: qualityColor ?? activeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.8,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  ),
                  Icon(Icons.hourglass_top, color: accentColor, size: 18),
                ],
              ),
              const SizedBox(width: 14),
              const Flexible(
                child: Text(
                  'Starting speech-to-text...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Control bar ────────────────────────────────────────────────────────────────
