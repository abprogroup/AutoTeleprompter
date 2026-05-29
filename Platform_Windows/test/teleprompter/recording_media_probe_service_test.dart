import 'dart:io';

import 'package:autoteleprompter/features/teleprompter/services/recording_media_probe_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recording media probe detects video and audio track markers', () async {
    final temp = await Directory.systemTemp.createTemp('media_probe_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final file = File('${temp.path}${Platform.pathSeparator}sample.mp4');
    await file.writeAsBytes([
      ...'ftyp'.codeUnits,
      ...List<int>.filled(8, 0),
      ...'vide'.codeUnits,
      ...List<int>.filled(8, 1),
      ...'soun'.codeUnits,
    ]);

    final result = await const RecordingMediaProbeService().inspect(file);

    expect(result.hasVideoTrack, isTrue);
    expect(result.hasAudioTrack, isTrue);
    expect(result.bytesScanned, greaterThan(0));
  });

  test('recording media probe detects markers across chunk boundaries',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('media_probe_boundary_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final file = File('${temp.path}${Platform.pathSeparator}sample.mp4');
    await file.writeAsBytes(
        'xxxv'.codeUnits + 'ideyyyso'.codeUnits + 'unzzz'.codeUnits);

    final result =
        await const RecordingMediaProbeService().inspect(file, chunkSize: 4);

    expect(result.hasVideoTrack, isTrue);
    expect(result.hasAudioTrack, isTrue);
  });

  test('recording media probe reports missing audio marker', () async {
    final temp =
        await Directory.systemTemp.createTemp('media_probe_silent_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final file = File('${temp.path}${Platform.pathSeparator}sample.mp4');
    await file.writeAsBytes('ftyp....vide....'.codeUnits);

    final result = await const RecordingMediaProbeService().inspect(file);

    expect(result.hasVideoTrack, isTrue);
    expect(result.hasAudioTrack, isFalse);
  });

  test('recording media probe detects WebM video and audio codec markers',
      () async {
    final temp = await Directory.systemTemp.createTemp('media_probe_webm_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final file = File('${temp.path}${Platform.pathSeparator}sample.webm');
    await file.writeAsBytes('matroska....V_VP9....A_OPUS'.codeUnits);

    final result =
        await const RecordingMediaProbeService().inspect(file, chunkSize: 5);

    expect(result.hasVideoTrack, isTrue);
    expect(result.hasAudioTrack, isTrue);
  });

  test('recording media probe detects WAV audio marker', () async {
    final temp = await Directory.systemTemp.createTemp('media_probe_wav_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final file = File('${temp.path}${Platform.pathSeparator}sample.wav');
    await file.writeAsBytes('RIFF....WAVEfmt data'.codeUnits);

    final result =
        await const RecordingMediaProbeService().inspect(file, chunkSize: 6);

    expect(result.hasVideoTrack, isFalse);
    expect(result.hasAudioTrack, isTrue);
  });

  test('recording media policy accepts audio-only WAV expectations', () {
    final assessment = const RecordingMediaProbePolicy().assess(
      probe: const RecordingMediaProbeResult(
        hasVideoTrack: false,
        hasAudioTrack: true,
        bytesScanned: 128,
      ),
      savedPath: r'C:\Videos\AutoTeleprompter\sample.wav',
      expectVideo: false,
      expectAudio: true,
    );

    expect(assessment.hasWarning, isFalse);
    expect(assessment.message, contains('Recording saved:'));
  });

  test('recording media policy warns when video format has no video track', () {
    final assessment = const RecordingMediaProbePolicy().assess(
      probe: const RecordingMediaProbeResult(
        hasVideoTrack: false,
        hasAudioTrack: true,
        bytesScanned: 128,
      ),
      savedPath: r'C:\Videos\AutoTeleprompter\sample.mp4',
      expectVideo: true,
      expectAudio: true,
    );

    expect(assessment.hasWarning, isTrue);
    expect(assessment.missingVideoTrack, isTrue);
    expect(assessment.message, contains('no video track'));
  });
}
