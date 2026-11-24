import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/stt/offline_stt_model_catalog.dart';
import '../../../platform/stt/offline_stt_model_manager.dart';

enum OfflineSttPackStatus { notInstalled, downloading, installed, error }

class OfflineSttPackUiState {
  final OfflineSttPackStatus status;
  final int receivedBytes;
  final int totalBytes;
  final String currentFile;
  final String? errorMessage;

  const OfflineSttPackUiState({
    this.status = OfflineSttPackStatus.notInstalled,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.currentFile = '',
    this.errorMessage,
  });

  double get progress =>
      totalBytes <= 0 ? 0.0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

class OfflineSttModelsState {
  final bool loaded;
  final Map<String, OfflineSttPackUiState> packs;

  const OfflineSttModelsState({
    this.loaded = false,
    this.packs = const {},
  });

  OfflineSttPackUiState packState(String packId) =>
      packs[packId] ?? const OfflineSttPackUiState();

  bool isInstalled(String packId) =>
      packState(packId).status == OfflineSttPackStatus.installed;

  bool isDownloading(String packId) =>
      packState(packId).status == OfflineSttPackStatus.downloading;

  OfflineSttModelsState copyWith({
    bool? loaded,
    Map<String, OfflineSttPackUiState>? packs,
  }) {
    return OfflineSttModelsState(
      loaded: loaded ?? this.loaded,
      packs: packs ?? this.packs,
    );
  }
}

class OfflineSttModelsNotifier extends Notifier<OfflineSttModelsState> {
  OfflineSttModelsNotifier({OfflineSttModelManager? manager})
    : _manager = manager ?? OfflineSttModelManager.instance;

  final OfflineSttModelManager _manager;
  bool _disposed = false;

  @override
  OfflineSttModelsState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
    });
    unawaited(refresh());
    return const OfflineSttModelsState();
  }

  Future<void> refresh() async {
    final installedIds = await _manager.listInstalledPackIds();
    if (_disposed) return;

    final nextPacks = Map<String, OfflineSttPackUiState>.from(state.packs);
    for (final pack in OfflineSttModelCatalog.packs) {
      final current = nextPacks[pack.packId];
      if (current?.status == OfflineSttPackStatus.downloading) {
        continue;
      }
      nextPacks[pack.packId] = OfflineSttPackUiState(
        status:
            installedIds.contains(pack.packId)
                ? OfflineSttPackStatus.installed
                : OfflineSttPackStatus.notInstalled,
        totalBytes: pack.totalBytes,
        receivedBytes: installedIds.contains(pack.packId) ? pack.totalBytes : 0,
      );
    }
    state = state.copyWith(loaded: true, packs: Map.unmodifiable(nextPacks));
  }

  Future<void> downloadPack(String packId) async {
    final pack = OfflineSttModelCatalog.packById(packId);
    if (pack == null) return;
    if (state.isDownloading(packId)) return;

    _updatePack(
      packId,
      OfflineSttPackUiState(
        status: OfflineSttPackStatus.downloading,
        receivedBytes: 0,
        totalBytes: pack.totalBytes,
        currentFile: pack.files.first.localName,
      ),
    );

    try {
      await _manager.downloadPack(
        pack,
        onProgress: (progress) {
          if (_disposed) return;
          _updatePack(
            packId,
            OfflineSttPackUiState(
              status: OfflineSttPackStatus.downloading,
              receivedBytes: progress.receivedBytes,
              totalBytes: progress.totalBytes,
              currentFile: progress.currentFile,
            ),
          );
        },
      );
      if (_disposed) return;
      _updatePack(
        packId,
        OfflineSttPackUiState(
          status: OfflineSttPackStatus.installed,
          receivedBytes: pack.totalBytes,
          totalBytes: pack.totalBytes,
        ),
      );
    } on OfflineSttDownloadCancelled {
      if (_disposed) return;
      _updatePack(
        packId,
        OfflineSttPackUiState(
          status: OfflineSttPackStatus.notInstalled,
          totalBytes: pack.totalBytes,
        ),
      );
    } catch (error) {
      if (_disposed) return;
      _updatePack(
        packId,
        OfflineSttPackUiState(
          status: OfflineSttPackStatus.error,
          totalBytes: pack.totalBytes,
          errorMessage: _friendlyError(error),
        ),
      );
    }
  }

  void cancelDownload(String packId) {
    _manager.cancelDownload(packId);
  }

  Future<void> deletePack(String packId) async {
    await _manager.deletePack(packId);
    if (_disposed) return;
    final pack = OfflineSttModelCatalog.packById(packId);
    _updatePack(
      packId,
      OfflineSttPackUiState(
        status: OfflineSttPackStatus.notInstalled,
        totalBytes: pack?.totalBytes ?? 0,
      ),
    );
  }

  void _updatePack(String packId, OfflineSttPackUiState next) {
    final updated = Map<String, OfflineSttPackUiState>.from(state.packs);
    updated[packId] = next;
    state = state.copyWith(loaded: true, packs: Map.unmodifiable(updated));
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 120) return text;
    return '${text.substring(0, 117)}...';
  }
}

final offlineSttModelsProvider =
    NotifierProvider<OfflineSttModelsNotifier, OfflineSttModelsState>(
      OfflineSttModelsNotifier.new,
    );
