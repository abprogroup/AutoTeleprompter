import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class MobileAudioRecorderException implements Exception {
  final String message;

  const MobileAudioRecorderException(this.message);

  @override
  String toString() => message;
}

class MobileAudioRecorderService {
  final AudioRecorder _recorder;
  String? _activePath;

  MobileAudioRecorderService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  bool get isRecording => _activePath != null;

  Future<String> start({DateTime? createdAt}) async {
    if (isRecording) {
      throw const MobileAudioRecorderException(
        'Audio recording is already active.',
      );
    }
    if (!await _recorder.hasPermission()) {
      throw const MobileAudioRecorderException(
        'Microphone permission is required for audio recording.',
      );
    }

    final directory = await _recordingDirectory();
    await directory.create(recursive: true);
    final path = _joinPath(
      directory.path,
      '${_recordingBaseName(createdAt ?? DateTime.now())}.m4a',
    );
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          numChannels: 1,
          bitRate: 128000,
        ),
        path: path,
      );
      _activePath = path;
      return path;
    } catch (error) {
      throw MobileAudioRecorderException(
        'Audio recording could not start: $error',
      );
    }
  }

  Future<String> stop() async {
    final fallbackPath = _activePath;
    if (fallbackPath == null) {
      throw const MobileAudioRecorderException(
          'Audio recording is not active.');
    }
    try {
      final stoppedPath = await _recorder.stop();
      return stoppedPath == null || stoppedPath.trim().isEmpty
          ? fallbackPath
          : stoppedPath;
    } catch (error) {
      throw MobileAudioRecorderException(
        'Audio recording could not stop: $error',
      );
    } finally {
      _activePath = null;
    }
  }

  Future<void> cancel() async {
    if (_activePath == null) return;
    try {
      await _recorder.cancel();
    } finally {
      _activePath = null;
    }
  }

  Future<void> dispose() => _recorder.dispose();

  static Future<Directory> _recordingDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory(_joinPath(root.path, 'AutoTeleprompter Recordings'));
  }

  static String _recordingBaseName(DateTime now) {
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    return 'AutoTeleprompter_Audio_$date-$time';
  }

  static String _joinPath(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) return '$left$right';
    return '$left${Platform.pathSeparator}$right';
  }
}
