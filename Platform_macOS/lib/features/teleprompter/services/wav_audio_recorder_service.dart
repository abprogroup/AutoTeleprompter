import 'dart:async';
import 'dart:io';

class WavAudioRecorderException implements Exception {
  final String message;

  const WavAudioRecorderException(this.message);

  @override
  String toString() => message;
}

class WavAudioRecorderService {
  WavAudioRecorderService();

  bool get isRecording => false;

  Future<String> start({
    required Directory destinationDirectory,
    DateTime? createdAt,
  }) async {
    throw const WavAudioRecorderException(
      'WAV audio recording is currently available on Windows only.',
    );
  }

  Future<String> stop() async {
    throw const WavAudioRecorderException('Audio recording is not active.');
  }

  Future<void> cancel() async {}
}
