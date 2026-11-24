import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'offline_stt_model_catalog.dart';

class OfflineSttResolvedPackPaths {
  final OfflineSttModelPack pack;
  final String directoryPath;
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;

  const OfflineSttResolvedPackPaths({
    required this.pack,
    required this.directoryPath,
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
    required this.tokensPath,
  });
}

class OfflineSttDownloadProgress {
  final String packId;
  final int receivedBytes;
  final int totalBytes;
  final String currentFile;

  const OfflineSttDownloadProgress({
    required this.packId,
    required this.receivedBytes,
    required this.totalBytes,
    required this.currentFile,
  });

  double get fraction =>
      totalBytes <= 0 ? 0.0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

class OfflineSttDownloadCancelled implements Exception {
  const OfflineSttDownloadCancelled();
}

class _ActiveDownload {
  bool cancelled = false;
  HttpClient? client;

  void cancel() {
    cancelled = true;
    try {
      client?.close(force: true);
    } catch (_) {}
  }
}

class OfflineSttModelManager {
  OfflineSttModelManager({Future<Directory> Function()? rootDirectoryResolver})
    : _rootDirectoryResolver = rootDirectoryResolver;

  static final OfflineSttModelManager instance = OfflineSttModelManager();

  static const String _modelsFolderName = 'offline_stt_models';
  static const String _manifestFileName = 'pack_manifest.json';

  final Future<Directory> Function()? _rootDirectoryResolver;
  final Map<String, _ActiveDownload> _activeDownloads = {};

  Future<Directory> modelsRootDirectory() async {
    if (_rootDirectoryResolver != null) {
      final root = await _rootDirectoryResolver();
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      return root;
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, _modelsFolderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> packDirectory(String packId) async {
    final root = await modelsRootDirectory();
    return Directory(p.join(root.path, packId));
  }

  Future<bool> isPackInstalled(OfflineSttModelPack pack) async {
    return (await resolveInstalledPack(pack)) != null;
  }

  Future<OfflineSttResolvedPackPaths?> resolveInstalledPack(
    OfflineSttModelPack pack,
  ) async {
    final dir = await packDirectory(pack.packId);
    if (!await dir.exists()) return null;

    for (final fileSpec in pack.files) {
      final file = File(p.join(dir.path, fileSpec.localName));
      if (!await file.exists()) return null;
      final size = await file.length();
      if (size <= 0) return null;
      if (fileSpec.expectedBytes > 0 && size != fileSpec.expectedBytes) {
        return null;
      }
    }

    return OfflineSttResolvedPackPaths(
      pack: pack,
      directoryPath: dir.path,
      encoderPath: p.join(dir.path, pack.encoderFileName),
      decoderPath:
          pack.decoderFileName.isEmpty
              ? ''
              : p.join(dir.path, pack.decoderFileName),
      joinerPath:
          pack.joinerFileName.isEmpty
              ? ''
              : p.join(dir.path, pack.joinerFileName),
      tokensPath: p.join(dir.path, pack.tokensFileName),
    );
  }

  Future<Set<String>> listInstalledPackIds() async {
    final installed = <String>{};
    for (final pack in OfflineSttModelCatalog.packs) {
      if (await isPackInstalled(pack)) {
        installed.add(pack.packId);
      }
    }
    return installed;
  }

  Future<void> downloadPack(
    OfflineSttModelPack pack, {
    void Function(OfflineSttDownloadProgress progress)? onProgress,
  }) async {
    if (_activeDownloads.containsKey(pack.packId)) {
      throw StateError('Download already in progress for ${pack.displayName}.');
    }

    final active = _ActiveDownload();
    _activeDownloads[pack.packId] = active;
    final dir = await packDirectory(pack.packId);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final totalBytes = pack.totalBytes;
    var completedBytes = 0;

    try {
      for (final fileSpec in pack.files) {
        if (active.cancelled) throw const OfflineSttDownloadCancelled();

        final targetFile = File(p.join(dir.path, fileSpec.localName));
        if (await targetFile.exists() &&
            await targetFile.length() == fileSpec.expectedBytes) {
          completedBytes += fileSpec.expectedBytes;
          onProgress?.call(
            OfflineSttDownloadProgress(
              packId: pack.packId,
              receivedBytes: completedBytes,
              totalBytes: totalBytes,
              currentFile: fileSpec.localName,
            ),
          );
          continue;
        }

        await _downloadSingleFile(
          packId: pack.packId,
          fileSpec: fileSpec,
          targetFile: targetFile,
          baseCompletedBytes: completedBytes,
          totalPackBytes: totalBytes,
          active: active,
          onProgress: onProgress,
        );
        completedBytes += fileSpec.expectedBytes;
      }

      if (active.cancelled) throw const OfflineSttDownloadCancelled();

      final manifestFile = File(p.join(dir.path, _manifestFileName));
      await manifestFile.writeAsString(
        jsonEncode({
          'packId': pack.packId,
          'sourceRepo': pack.sourceRepo,
          'installedAt': DateTime.now().toUtc().toIso8601String(),
          'totalBytes': totalBytes,
        }),
      );

      final verified = await resolveInstalledPack(pack);
      if (verified == null) {
        throw const FileSystemException(
          'Downloaded model files failed completeness verification.',
        );
      }
    } finally {
      active.client?.close(force: true);
      _activeDownloads.remove(pack.packId);
    }
  }

  void cancelDownload(String packId) {
    _activeDownloads[packId]?.cancel();
  }

  Future<void> deletePack(String packId) async {
    cancelDownload(packId);
    final dir = await packDirectory(packId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _downloadSingleFile({
    required String packId,
    required OfflineSttModelFileSpec fileSpec,
    required File targetFile,
    required int baseCompletedBytes,
    required int totalPackBytes,
    required _ActiveDownload active,
    void Function(OfflineSttDownloadProgress progress)? onProgress,
  }) async {
    final partFile = File('${targetFile.path}.part');
    if (await partFile.exists()) {
      await partFile.delete();
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    active.client = client;

    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(fileSpec.downloadUrl));
      request.followRedirects = true;
      request.maxRedirects = 8;
      request.headers.set(HttpHeaders.userAgentHeader, 'AutoTeleprompter/5.2');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'HTTP ${response.statusCode} downloading ${fileSpec.localName}',
          uri: Uri.parse(fileSpec.downloadUrl),
        );
      }

      sink = partFile.openWrite();
      Digest? computedDigest;
      final digestSink =
          fileSpec.expectedSha256 == null
              ? null
              : sha256.startChunkedConversion(
                _SingleDigestSink((digest) => computedDigest = digest),
              );

      var fileReceived = 0;
      var lastEmitMs = 0;
      await for (final chunk in response) {
        if (active.cancelled) {
          throw const OfflineSttDownloadCancelled();
        }
        sink.add(chunk);
        digestSink?.add(chunk);
        fileReceived += chunk.length;

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - lastEmitMs >= 100 ||
            fileReceived >= fileSpec.expectedBytes) {
          lastEmitMs = nowMs;
          onProgress?.call(
            OfflineSttDownloadProgress(
              packId: packId,
              receivedBytes: baseCompletedBytes + fileReceived,
              totalBytes: totalPackBytes,
              currentFile: fileSpec.localName,
            ),
          );
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;
      digestSink?.close();

      if (active.cancelled) throw const OfflineSttDownloadCancelled();

      final actualBytes = await partFile.length();
      if (fileSpec.expectedBytes > 0 && actualBytes != fileSpec.expectedBytes) {
        throw FileSystemException(
          'Size mismatch for ${fileSpec.localName}: '
          'got $actualBytes bytes, expected ${fileSpec.expectedBytes}.',
          partFile.path,
        );
      }

      if (fileSpec.expectedSha256 != null) {
        final actualHex = computedDigest?.toString().toLowerCase() ?? '';
        if (actualHex != fileSpec.expectedSha256!.toLowerCase()) {
          throw FileSystemException(
            'Checksum mismatch for ${fileSpec.localName}.',
            partFile.path,
          );
        }
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetFile.path);
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await partFile.exists()) {
          await partFile.delete();
        }
      } catch (_) {}
      rethrow;
    } finally {
      client.close(force: true);
      if (identical(active.client, client)) {
        active.client = null;
      }
    }
  }
}

class _SingleDigestSink implements Sink<Digest> {
  _SingleDigestSink(this._onDigest);

  final void Function(Digest digest) _onDigest;

  @override
  void add(Digest data) => _onDigest(data);

  @override
  void close() {}
}
