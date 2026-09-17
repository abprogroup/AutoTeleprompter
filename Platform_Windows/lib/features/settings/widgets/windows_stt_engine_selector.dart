import 'package:flutter/material.dart';

import '../models/app_settings.dart';

class WindowsSttEngineSelector extends StatelessWidget {
  static const Key smartChoiceKey = Key('windows-stt-engine-smart');
  static const Key inAppChoiceKey = Key('windows-stt-engine-in-app');
  static const Key edgeChoiceKey = Key('windows-stt-engine-edge');
  static const Key offlineChoiceKey = Key('windows-stt-engine-offline');

  final String value;
  final bool enabled;
  final Color accentColor;
  final Color backgroundColor;
  final ValueChanged<String> onChanged;

  const WindowsSttEngineSelector({
    super.key,
    required this.value,
    required this.enabled,
    required this.accentColor,
    required this.onChanged,
    this.backgroundColor = const Color(0xFF111111),
  });

  @override
  Widget build(BuildContext context) {
    final normalized = AppSettings.normalizeSttEngine(value);
    final selected = switch (normalized) {
      AppSettings.sttEngineBrowserOnline => AppSettings.sttEngineBrowserOnline,
      AppSettings.sttEngineBrowserExternalEdge =>
        AppSettings.sttEngineBrowserExternalEdge,
      AppSettings.sttEngineWhisperTiny => AppSettings.sttEngineWhisperTiny,
      _ => AppSettings.sttEngineBrowserSmartCompatibility,
    };

    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 160),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.language_rounded, color: accentColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Speech recognition host',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled
                            ? _selectionGuidance(selected)
                            : 'Stop listening to change this. A new choice takes effect on the next listening session.',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _EngineChoiceChip(
                  key: smartChoiceKey,
                  label: 'Smart compatibility (recommended)',
                  selected: selected ==
                      AppSettings.sttEngineBrowserSmartCompatibility,
                  enabled: enabled,
                  accentColor: accentColor,
                  onSelected: () => onChanged(
                    AppSettings.sttEngineBrowserSmartCompatibility,
                  ),
                ),
                _EngineChoiceChip(
                  key: inAppChoiceKey,
                  label: 'In-app browser only',
                  selected: selected == AppSettings.sttEngineBrowserOnline,
                  enabled: enabled,
                  accentColor: accentColor,
                  onSelected: () =>
                      onChanged(AppSettings.sttEngineBrowserOnline),
                ),
                _EngineChoiceChip(
                  key: edgeChoiceKey,
                  label: 'Microsoft Edge only',
                  selected:
                      selected == AppSettings.sttEngineBrowserExternalEdge,
                  enabled: enabled,
                  accentColor: accentColor,
                  onSelected: () =>
                      onChanged(AppSettings.sttEngineBrowserExternalEdge),
                ),
                _EngineChoiceChip(
                  key: offlineChoiceKey,
                  label: 'Offline Whisper',
                  selected: selected == AppSettings.sttEngineWhisperTiny,
                  enabled: enabled,
                  accentColor: accentColor,
                  onSelected: () => onChanged(AppSettings.sttEngineWhisperTiny),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _selectionGuidance(String selected) {
    switch (selected) {
      case AppSettings.sttEngineBrowserOnline:
        return 'Always uses the in-app browser. Changes take effect on the next listening session.';
      case AppSettings.sttEngineBrowserExternalEdge:
        return 'Always uses Microsoft Edge. Changes take effect on the next listening session.';
      case AppSettings.sttEngineWhisperTiny:
        return 'Runs fully on this computer with the bundled multilingual model. No browser speech service is used.';
      default:
        return 'Smart chooses a compatible browser host when needed. Changes take effect on the next listening session.';
    }
  }
}

class _EngineChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final Color accentColor;
  final VoidCallback onSelected;

  const _EngineChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.accentColor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: true,
      checkmarkColor: Colors.black,
      selectedColor: accentColor,
      backgroundColor: Colors.transparent,
      disabledColor: Colors.transparent,
      side: BorderSide(
        color: selected ? Colors.transparent : Colors.white54,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white70,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      onSelected: enabled ? (_) => onSelected() : null,
    );
  }
}
