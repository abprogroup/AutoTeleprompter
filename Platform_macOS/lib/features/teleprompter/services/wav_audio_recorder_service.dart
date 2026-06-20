import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class WavAudioRecorderException implements Exception {
  final String message;

  const WavAudioRecorderException(this.message);

  @override
  String toString() => message;
}

class WavAudioRecorderService {
  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/audio_recorder');

  String? _activePath;

  WavAudioRecorderService();

  bool get isRecording => _activePath != null;

  Future<String> start({
    required Directory destinationDirectory,
    DateTime? createdAt,
  }) async {
    if (!Platform.isMacOS) {
      throw const WavAudioRecorderException(
        'WAV audio recording is currently available on macOS only.',
      );
    }
    if (isRecording) {
      throw const WavAudioRecorderException(
          'Audio recording is already active.');
    }
    await destinationDirectory.create(recursive: true);
    final path = _joinPath(
      destinationDirectory.path,
      '${_recordingBaseName(createdAt ?? DateTime.now())}.wav',
    );
    try {
      final startedPath =
          await _channel.invokeMethod<String>('start', {'path': path});
      if (startedPath == null || startedPath.trim().isEmpty) {
        throw const WavAudioRecorderException(
          'Audio recorder did not return a file path.',
        );
      }
      _activePath = startedPath;
      return startedPath;
    } on PlatformException catch (error) {
      throw WavAudioRecorderException(
        error.message ?? 'Audio recording could not start.',
      );
    }
  }

  Future<String> stop() async {
    final fallbackPath = _activePath;
    if (fallbackPath == null) {
      throw const WavAudioRecorderException('Audio recording is not active.');
    }
    try {
      final stoppedPath = await _channel.invokeMethod<String>('stop');
      return stoppedPath == null || stoppedPath.trim().isEmpty
          ? fallbackPath
          : stoppedPath;
    } on PlatformException catch (error) {
      throw WavAudioRecorderException(
        error.message ?? 'Audio recording could not stop.',
      );
    } finally {
      _activePath = null;
    }
  }

  Future<void> cancel() async {
    final path = _activePath;
    if (path == null) return;
    try {
      await _channel.invokeMethod<bool>('cancel');
    } catch (_) {
      // Cancellation is best-effort; local state must still unblock the UI.
    } finally {
      _activePath = null;
    }
  }

  static String _recordingBaseName(DateTime now) {
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    return 'AutoTeleprompter_Audio_${date}_$time';
  }

  static String _joinPath(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) return '$left$right';
    return '$left${Platform.pathSeparator}$right';
  }
}
