import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/providers/settings_provider.dart';

/// Present-mode visual scroll tuning, separate from speech/profile controls.
class SpeechScrollControls extends ConsumerWidget {
  const SpeechScrollControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final smoothness = AppSettings.normalizeSpeechScrollSmoothness(
      settings.speechScrollSmoothness,
    );
    final speed = AppSettings.normalizeSpeechScrollSpeed(
      settings.speechScrollSpeed,
    );
    final accent = Color(settings.currentWordColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Speech-following scroll',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Page movement only, not speech recognition. '
          'Speed is a limit, not a fixed pace. More smoothing softens catch-up.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 12),
        _ScrollTuningSlider(
          id: 'speech-scroll-smoothness',
          title: 'Smoothness',
          valueLabel: '${(smoothness * 100).round()}%',
          value: smoothness,
          min: 0,
          max: 1,
          divisions: 20,
          startLabel: 'Responsive',
          endLabel: 'Smoother',
          resetTooltip: 'Reset smoothness to default (50%)',
          accent: accent,
          onChanged:
              (value) => unawaited(notifier.setSpeechScrollSmoothness(value)),
          onReset:
              () => unawaited(
                notifier.setSpeechScrollSmoothness(
                  AppSettings.defaultSpeechScrollSmoothness,
                ),
              ),
        ),
        const SizedBox(height: 12),
        _ScrollTuningSlider(
          id: 'speech-scroll-speed',
          title: 'Scroll speed limit',
          valueLabel: '${speed.toStringAsFixed(2)}x',
          value: speed,
          min: 0.25,
          max: 2,
          divisions: 35,
          startLabel: 'Slower',
          endLabel: 'Faster',
          resetTooltip: 'Reset scroll speed to default (1.00x)',
          accent: accent,
          onChanged: (value) => unawaited(notifier.setSpeechScrollSpeed(value)),
          onReset:
              () => unawaited(
                notifier.setSpeechScrollSpeed(
                  AppSettings.defaultSpeechScrollSpeed,
                ),
              ),
        ),
      ],
    );
  }
}

class _ScrollTuningSlider extends StatelessWidget {
  const _ScrollTuningSlider({
    required this.id,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.startLabel,
    required this.endLabel,
    required this.resetTooltip,
    required this.accent,
    required this.onChanged,
    required this.onReset,
  });

  final String id, title, valueLabel, startLabel, endLabel, resetTooltip;
  final double value, min, max;
  final int divisions;
  final Color accent;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(color: Colors.white70)),
            ),
            Text(valueLabel, style: const TextStyle(color: Colors.white)),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                key: ValueKey(id),
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: valueLabel,
                semanticFormatterCallback: (_) => '$title $valueLabel',
                activeColor: accent,
                inactiveColor: Colors.white24,
                onChanged: onChanged,
              ),
            ),
            IconButton(
              key: ValueKey('$id-reset'),
              tooltip: resetTooltip,
              onPressed: onReset,
              color: Colors.white70,
              icon: const Icon(Icons.restart_alt, size: 20),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 64),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  startLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  endLabel,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
