import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/stt/offline_stt_model_catalog.dart';
import '../providers/offline_stt_models_provider.dart';
import '../providers/settings_provider.dart';

class WindowsSttEngineSelector extends ConsumerWidget {
  static const Key smartChoiceKey = Key('windows-stt-engine-smart');
  static const Key offlineNemo80StreamingKey = Key(
    'windows-stt-engine-offline-nemo80-streaming',
  );
  static const Key offlineNemo480StreamingKey = Key(
    'windows-stt-engine-offline-nemo480-streaming',
  );
  static const Key offlineKroko64StreamingKey = Key(
    'windows-stt-engine-offline-kroko64-streaming',
  );
  static const Key offlineKrokoStreamingKey = Key(
    'windows-stt-engine-offline-kroko-streaming',
  );
  static const Key offlineZipformerFastKey = Key(
    'windows-stt-engine-offline-zipformer-fast',
  );
  static const Key offlineZipformerPrecisionKey = Key(
    'windows-stt-engine-offline-zipformer-precision',
  );
  static const Key offlineParakeetV3Key = Key(
    'windows-stt-engine-offline-parakeet-v3',
  );
  static const Key offlineParakeetV2Key = Key(
    'windows-stt-engine-offline-parakeet-v2',
  );
  static const Key scriptBoostSwitchKey = Key(
    'windows-stt-offline-script-boost-switch',
  );

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

  static Key _keyForOfflineEngine(String engineId) {
    switch (engineId) {
      case AppSettings.sttEngineOfflineNemo80Streaming:
        return offlineNemo80StreamingKey;
      case AppSettings.sttEngineOfflineNemo480Streaming:
        return offlineNemo480StreamingKey;
      case AppSettings.sttEngineOfflineKroko64Streaming:
        return offlineKroko64StreamingKey;
      case AppSettings.sttEngineOfflineKrokoStreaming:
        return offlineKrokoStreamingKey;
      case AppSettings.sttEngineOfflineZipformerFast:
        return offlineZipformerFastKey;
      case AppSettings.sttEngineOfflineZipformerPrecision:
        return offlineZipformerPrecisionKey;
      case AppSettings.sttEngineOfflineParakeetV3:
        return offlineParakeetV3Key;
      case AppSettings.sttEngineOfflineParakeetV2:
        return offlineParakeetV2Key;
      default:
        return ValueKey('windows-stt-engine-$engineId');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = AppSettings.normalizeSttEngine(value);
    final selectedOfflineSpec = OfflineSttModelCatalog.engineById(selected);
    final modelsState = ref.watch(offlineSttModelsProvider);
    final modelsNotifier = ref.read(offlineSttModelsProvider.notifier);
    final scriptBoostEnabled = ref.watch(
      settingsProvider.select((s) => s.sttOfflineScriptBoostEnabled),
    );

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
                Icon(
                  selectedOfflineSpec == null
                      ? Icons.language_rounded
                      : Icons.memory_rounded,
                  color: accentColor,
                  size: 20,
                ),
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
                        _subtitleForSelection(selectedOfflineSpec, enabled),
                        style: const TextStyle(
                          color: Colors.white54,
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
                  label: 'Hidden in-app speech (online)',
                  selected:
                      selected ==
                      AppSettings.sttEngineBrowserSmartCompatibility,
                  enabled: enabled,
                  accentColor: accentColor,
                  onSelected:
                      () => onChanged(
                        AppSettings.sttEngineBrowserSmartCompatibility,
                      ),
                ),
                for (final spec in OfflineSttModelCatalog.engines)
                  _EngineChoiceChip(
                    key: _keyForOfflineEngine(spec.engineId),
                    label: spec.chipLabel,
                    selected: selected == spec.engineId,
                    enabled: enabled,
                    accentColor: accentColor,
                    onSelected: () => onChanged(spec.engineId),
                  ),
              ],
            ),
            if (selectedOfflineSpec != null) ...[
              const SizedBox(height: 12),
              _OfflineModelPacksCard(
                spec: selectedOfflineSpec,
                modelsState: modelsState,
                accentColor: accentColor,
                enabled: enabled,
                scriptBoostEnabled: scriptBoostEnabled,
                onScriptBoostChanged:
                    (v) => unawaited(
                      ref
                          .read(settingsProvider.notifier)
                          .setSttOfflineScriptBoostEnabled(v),
                    ),
                onDownloadPack:
                    (packId) => unawaited(modelsNotifier.downloadPack(packId)),
                onCancelPack: modelsNotifier.cancelDownload,
                onDeletePack:
                    (packId) => unawaited(modelsNotifier.deletePack(packId)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _subtitleForSelection(OfflineSttEngineSpec? spec, bool isEnabled) {
    if (!isEnabled) {
      return 'Stop listening before switching speech recognition engines.';
    }
    if (spec == null) {
      return 'Speech stays inside AutoTeleprompter in a hidden embedded WebView (uses internet).';
    }
    return spec.description;
  }
}

class _OfflineModelPacksCard extends StatelessWidget {
  final OfflineSttEngineSpec spec;
  final OfflineSttModelsState modelsState;
  final Color accentColor;
  final bool enabled;
  final bool scriptBoostEnabled;
  final ValueChanged<bool> onScriptBoostChanged;
  final ValueChanged<String> onDownloadPack;
  final ValueChanged<String> onCancelPack;
  final ValueChanged<String> onDeletePack;

  const _OfflineModelPacksCard({
    required this.spec,
    required this.modelsState,
    required this.accentColor,
    required this.enabled,
    required this.scriptBoostEnabled,
    required this.onScriptBoostChanged,
    required this.onDownloadPack,
    required this.onCancelPack,
    required this.onDeletePack,
  });

  @override
  Widget build(BuildContext context) {
    final hePack = spec.hebrewPack;
    final enPack = spec.englishPack;
    final heState = modelsState.packState(hePack.packId);
    final enState = modelsState.packState(enPack.packId);
    final bothReady =
        heState.status == OfflineSttPackStatus.installed &&
        enState.status == OfflineSttPackStatus.installed;
    final anyDownloading =
        heState.status == OfflineSttPackStatus.downloading ||
        enState.status == OfflineSttPackStatus.downloading;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                spec.isStreaming ? Icons.bolt_rounded : Icons.auto_awesome,
                size: 16,
                color: accentColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${spec.shortLabel} • ${spec.isStreaming ? "Real-time streaming" : "High-accuracy chunked"}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!bothReady && !anyDownloading)
                TextButton.icon(
                  onPressed:
                      enabled
                          ? () {
                            if (heState.status !=
                                OfflineSttPackStatus.installed) {
                              onDownloadPack(hePack.packId);
                            }
                            if (enState.status !=
                                OfflineSttPackStatus.installed) {
                              onDownloadPack(enPack.packId);
                            }
                          }
                          : null,
                  style: TextButton.styleFrom(
                    foregroundColor: accentColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text(
                    'Download HE + EN',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _ModelPackRow(
            pack: hePack,
            state: heState,
            accentColor: accentColor,
            enabled: enabled,
            onDownload: () => onDownloadPack(hePack.packId),
            onCancel: () => onCancelPack(hePack.packId),
            onDelete: () => onDeletePack(hePack.packId),
          ),
          const Divider(height: 14, color: Colors.white10),
          _ModelPackRow(
            pack: enPack,
            state: enState,
            accentColor: accentColor,
            enabled: enabled,
            onDownload: () => onDownloadPack(enPack.packId),
            onCancel: () => onCancelPack(enPack.packId),
            onDelete: () => onDeletePack(enPack.packId),
          ),
          const Divider(height: 16, color: Colors.white12),
          Row(
            children: [
              Icon(
                Icons.auto_fix_high_rounded,
                size: 16,
                color: scriptBoostEnabled ? accentColor : Colors.white38,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Script-Guided Accuracy (Beam + Hotwords)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scriptBoostEnabled
                          ? 'ON: Uses beam search + upcoming script words to improve tricky/accented words.'
                          : 'OFF: Raw greedy decoding (no script bias) for A/B baseline testing.',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Switch.adaptive(
                key: WindowsSttEngineSelector.scriptBoostSwitchKey,
                value: scriptBoostEnabled,
                thumbColor: WidgetStatePropertyAll<Color>(accentColor),
                onChanged: enabled ? onScriptBoostChanged : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            bothReady
                ? 'Both languages ready. Auto-switches Hebrew and English per paragraph completely offline.'
                : 'Download Hebrew, English, or both. Downloaded models are saved locally in app data.',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelPackRow extends StatelessWidget {
  final OfflineSttModelPack pack;
  final OfflineSttPackUiState state;
  final Color accentColor;
  final bool enabled;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _ModelPackRow({
    required this.pack,
    required this.state,
    required this.accentColor,
    required this.enabled,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isInstalled = state.status == OfflineSttPackStatus.installed;
    final isDownloading = state.status == OfflineSttPackStatus.downloading;
    final hasError = state.status == OfflineSttPackStatus.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color:
                    isInstalled
                        ? Colors.green.withValues(alpha: 0.22)
                        : Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                pack.languageCode.toUpperCase(),
                style: TextStyle(
                  color: isInstalled ? Colors.greenAccent : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    isInstalled
                        ? 'Ready offline • ${pack.approxSizeLabel}'
                        : isDownloading
                        ? _downloadProgressLabel(state)
                        : 'Not downloaded • ${pack.approxSizeLabel}',
                    style: TextStyle(
                      color:
                          isInstalled
                              ? Colors.greenAccent.withValues(alpha: 0.85)
                              : Colors.white54,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (isDownloading)
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orangeAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 11)),
              )
            else if (isInstalled)
              IconButton(
                tooltip: 'Delete ${pack.languageLabel} model',
                onPressed: enabled ? onDelete : null,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: Colors.white54,
                ),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              )
            else
              OutlinedButton.icon(
                onPressed: enabled ? onDownload : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor,
                  side: BorderSide(color: accentColor.withValues(alpha: 0.65)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.download_rounded, size: 13),
                label: Text(
                  hasError ? 'Retry' : 'Download',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
        if (isDownloading) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: state.progress > 0 ? state.progress : null,
              minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ],
        if (hasError && (state.errorMessage ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            state.errorMessage!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.redAccent, fontSize: 10.5),
          ),
        ],
      ],
    );
  }

  String _downloadProgressLabel(OfflineSttPackUiState state) {
    final pct = (state.progress * 100).round();
    final receivedMb = (state.receivedBytes / (1024 * 1024)).toStringAsFixed(1);
    final totalMb = (state.totalBytes / (1024 * 1024)).toStringAsFixed(0);
    return 'Downloading $pct% ($receivedMb / $totalMb MB)';
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
      side: BorderSide(color: selected ? Colors.transparent : Colors.white54),
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white70,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      onSelected: enabled ? (_) => onSelected() : null,
    );
  }
}
