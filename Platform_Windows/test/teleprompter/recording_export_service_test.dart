import 'dart:io';

import 'package:autoteleprompter/features/teleprompter/services/recording_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recording export copies mp4 to destination and removes temp source',
      () async {
    final temp = await Directory.systemTemp.createTemp('record_export_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final source = File('${temp.path}${Platform.pathSeparator}camera.tmp');
    await source.writeAsBytes(List<int>.generate(4096, (i) => i % 255));
    final destination =
        Directory('${temp.path}${Platform.pathSeparator}recordings');
    final progress = <double>[];

    final result = await const RecordingExportService().exportMp4(
      sourceFile: source,
      destinationDirectory: destination,
      createdAt: DateTime(2026, 5, 28, 19, 40, 10),
      onProgress: progress.add,
    );

    expect(result.outputPath,
        endsWith('AutoTeleprompter_2026-05-28_19-40-10.mp4'));
    expect(result.bytesWritten, 4096);
    expect(result.sourceDeleted, isTrue);
    expect(result.format, 'mp4');
    expect(await source.exists(), isFalse);
    expect(await File(result.outputPath).exists(), isTrue);
    expect(progress.last, 1.0);
  });

  test('recording export avoids overwriting existing files', () async {
    final temp =
        await Directory.systemTemp.createTemp('record_collision_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final destination =
        Directory('${temp.path}${Platform.pathSeparator}recordings');
    await destination.create(recursive: true);
    final existing = File(
      '${destination.path}${Platform.pathSeparator}'
      'AutoTeleprompter_2026-05-28_19-40-10.mp4',
    );
    await existing.writeAsString('existing');
    final source = File('${temp.path}${Platform.pathSeparator}camera.tmp');
    await source.writeAsString('new');

    final result = await const RecordingExportService().exportMp4(
      sourceFile: source,
      destinationDirectory: destination,
      createdAt: DateTime(2026, 5, 28, 19, 40, 10),
    );

    expect(result.outputPath,
        endsWith('AutoTeleprompter_2026-05-28_19-40-10-1.mp4'));
    expect(await existing.readAsString(), 'existing');
    expect(await File(result.outputPath).readAsString(), 'new');
  });

  test('recording export rejects non-native beta formats without conversion',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('record_unsupported_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final source = File('${temp.path}${Platform.pathSeparator}camera.tmp');
    await source.writeAsString('new');

    expect(
      () => const RecordingExportService().export(
        sourceFile: source,
        destinationDirectory: temp,
        format: 'webm',
      ),
      throwsA(isA<RecordingExportUnsupportedException>()),
    );
    expect(await source.exists(), isTrue);
  });
}
