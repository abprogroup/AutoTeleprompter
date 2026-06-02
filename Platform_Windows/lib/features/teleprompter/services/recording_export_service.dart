import 'dart:io';

import '../../feedback/services/lightweight_diagnostics.dart';

class RecordingExportUnsupportedException implements Exception {
  final String message;

  const RecordingExportUnsupportedException(this.message);

  @override
  String toString() => message;
}

class RecordingExportResult {
  final String outputPath;
  final int bytesWritten;
  final bool sourceDeleted;
  final String format;

  const RecordingExportResult({
    required this.outputPath,
    required this.bytesWritten,
    required this.sourceDeleted,
    required this.format,
  });
}

class RecordingExportService {
  const RecordingExportService();

  Future<bool> canExport(String format) async =>
      _normalizeFormat(format) == 'mp4';

  Future<File> reserveTargetFile({
    required Directory destinationDirectory,
    required String format,
    DateTime? createdAt,
  }) async {
    if (!await destinationDirectory.exists()) {
      await destinationDirectory.create(recursive: true);
    }
    final normalized = _normalizeFormat(format);
    return _nonCollidingTarget(
      destinationDirectory,
      _fileNameForFormat(createdAt ?? DateTime.now(), normalized),
    );
  }

  Future<RecordingExportResult> export({
    required File sourceFile,
    required Directory destinationDirectory,
    required String format,
    DateTime? createdAt,
    void Function(double progress)? onProgress,
  }) async {
    final normalized = _normalizeFormat(format);
    if (normalized == 'mp4') {
      return exportMp4(
        sourceFile: sourceFile,
        destinationDirectory: destinationDirectory,
        createdAt: createdAt,
        onProgress: onProgress,
      );
    }

    throw const RecordingExportUnsupportedException(
      'This beta exports camera recordings as MP4 directly. Extra video '
      'file types are planned for v6 after platform-specific recording '
      'research.',
    );
  }

  Future<RecordingExportResult> exportMp4({
    required File sourceFile,
    required Directory destinationDirectory,
    DateTime? createdAt,
    void Function(double progress)? onProgress,
  }) async {
    if (!await sourceFile.exists()) {
      throw const FileSystemException('Recording source file is missing.');
    }
    final target = await reserveTargetFile(
      destinationDirectory: destinationDirectory,
      format: 'mp4',
      createdAt: createdAt,
    );
    final bytesWritten = await _copyToTargetOrCleanup(
      sourceFile: sourceFile,
      target: target,
      format: 'mp4',
      onProgress: onProgress,
    );

    var sourceDeleted = false;
    try {
      await sourceFile.delete();
      sourceDeleted = true;
    } catch (e, stack) {
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'recordingExport.sourceDelete',
        data: {'path': sourceFile.path, 'format': 'mp4'},
      );
    }

    return RecordingExportResult(
      outputPath: target.path,
      bytesWritten: bytesWritten,
      sourceDeleted: sourceDeleted,
      format: 'mp4',
    );
  }

  String _fileNameForFormat(DateTime date, String format) {
    String two(int value) => value.toString().padLeft(2, '0');
    final extension = _extensionForFormat(format);
    return 'AutoTeleprompter_${date.year}-${two(date.month)}-${two(date.day)}_'
        '${two(date.hour)}-${two(date.minute)}-${two(date.second)}'
        '.$extension';
  }

  Future<File> _nonCollidingTarget(
    Directory directory,
    String fileName,
  ) async {
    final dot = fileName.lastIndexOf('.');
    final base = dot <= 0 ? fileName : fileName.substring(0, dot);
    final extension = dot <= 0 ? '' : fileName.substring(dot);
    var candidate = File('${directory.path}${Platform.pathSeparator}$fileName');
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = File(
        '${directory.path}${Platform.pathSeparator}$base-$suffix$extension',
      );
      suffix++;
    }
    return candidate;
  }

  Future<int> _copyWithProgress(
    File source,
    File target, {
    void Function(double progress)? onProgress,
  }) async {
    final totalBytes = await source.length();
    var copiedBytes = 0;
    final input = source.openRead();
    final output = target.openWrite();
    try {
      await for (final chunk in input) {
        copiedBytes += chunk.length;
        output.add(chunk);
        if (totalBytes > 0) {
          onProgress?.call((copiedBytes / totalBytes).clamp(0.0, 1.0));
        }
      }
    } finally {
      await output.close();
    }
    onProgress?.call(1.0);
    return copiedBytes;
  }

  Future<int> _copyToTargetOrCleanup({
    required File sourceFile,
    required File target,
    required String format,
    void Function(double progress)? onProgress,
  }) async {
    try {
      return await _copyWithProgress(
        sourceFile,
        target,
        onProgress: onProgress,
      );
    } catch (e, stack) {
      if (await target.exists()) {
        try {
          await target.delete();
        } catch (deleteError, deleteStack) {
          LightweightDiagnostics.instance.recordError(
            deleteError,
            deleteStack,
            source: 'recordingExport.partialTargetDelete',
            data: {'path': target.path, 'format': format},
          );
        }
      }
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'recordingExport.copyFailed',
        data: {'path': target.path, 'format': format},
      );
      rethrow;
    }
  }

  String _normalizeFormat(String format) {
    return switch (format) {
      'mp4' => 'mp4',
      'wav' => 'wav',
      _ => format,
    };
  }

  String _extensionForFormat(String format) {
    return switch (format) {
      'wav' => 'wav',
      _ => 'mp4',
    };
  }
}
