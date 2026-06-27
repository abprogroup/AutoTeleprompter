part of 'teleprompter_screen.dart';

/// Compact microphone signal meter for the present-mode debug console.
/// Mirrors the macOS sound bar so users can confirm STT is hearing them.
/// `level` is already normalized to 0..1 by the provider.
class _SoundLevelBar extends StatelessWidget {
  final double level;
  final bool isListening;
  final bool isStarting;
  final Color accentColor;

  const _SoundLevelBar({
    required this.level,
    required this.isListening,
    required this.isStarting,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final clampedLevel = level.clamp(0.0, 1.0).toDouble();
    final activeColor = isListening ? accentColor : Colors.white38;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            Icon(
              isStarting
                  ? Icons.hourglass_top
                  : (isListening ? Icons.graphic_eq : Icons.volume_off),
              color: activeColor,
              size: 15,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: clampedLevel,
                  minHeight: 12,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
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
        ),
      ),
    );
  }
}
