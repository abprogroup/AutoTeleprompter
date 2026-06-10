import 'dart:io';

class RecordingMediaProbeResult {
  final bool hasVideoTrack;
  final bool hasAudioTrack;
  final int bytesScanned;

  const RecordingMediaProbeResult({
    required this.hasVideoTrack,
    required this.hasAudioTrack,
    required this.bytesScanned,
  });
}

class RecordingMediaSaveAssessment {
  final String message;
  final bool missingVideoTrack;
  final bool missingAudioTrack;

  const RecordingMediaSaveAssessment({
    required this.message,
    required this.missingVideoTrack,
    required this.missingAudioTrack,
  });

  bool get hasWarning => missingVideoTrack || missingAudioTrack;
}

class RecordingMediaProbePolicy {
  const RecordingMediaProbePolicy();

  RecordingMediaSaveAssessment assess({
    required RecordingMediaProbeResult probe,
    required String savedPath,
    required bool expectVideo,
    required bool expectAudio,
  }) {
    final missingVideo = expectVideo && !probe.hasVideoTrack;
    final missingAudio = expectAudio && !probe.hasAudioTrack;
    if (missingVideo) {
      return RecordingMediaSaveAssessment(
        message: 'Recording saved, but no video track was detected: $savedPath',
        missingVideoTrack: true,
        missingAudioTrack: missingAudio,
      );
    }
    if (missingAudio) {
      return RecordingMediaSaveAssessment(
        message: 'Recording saved, but no audio track was detected: $savedPath',
        missingVideoTrack: false,
        missingAudioTrack: true,
      );
    }
    return RecordingMediaSaveAssessment(
      message: 'Recording saved: $savedPath',
      missingVideoTrack: false,
      missingAudioTrack: false,
    );
  }
}

class RecordingMediaProbeService {
  const RecordingMediaProbeService();

  static const _videoMarkers = [
    'vide',
    'V_VP8',
    'V_VP9',
    'V_AV1',
    'V_MPEG4',
  ];

  static const _audioMarkers = [
    'soun',
    'A_OPUS',
    'A_VORBIS',
    'A_AAC',
    'A_PCM',
    'WAVEfmt',
  ];

  Future<RecordingMediaProbeResult> inspect(
    File file, {
    int chunkSize = 64 * 1024,
  }) async {
    var hasVideo = false;
    var hasAudio = false;
    var bytesScanned = 0;
    var tail = const <int>[];
    final effectiveChunkSize = chunkSize < 4 ? 4 : chunkSize;
    final tailBytes = _maxMarkerLength - 1;

    final raf = await file.open();
    try {
      while (true) {
        final chunk = await raf.read(effectiveChunkSize);
        if (chunk.isEmpty) break;
        bytesScanned += chunk.length;
        final combined = tail.isEmpty ? chunk : <int>[...tail, ...chunk];
        hasVideo = hasVideo || _containsAnyAscii(combined, _videoMarkers);
        hasAudio = hasAudio || _containsAnyAscii(combined, _audioMarkers);
        if (hasVideo && hasAudio) break;
        tail = combined.length <= tailBytes
            ? List<int>.of(combined)
            : combined.sublist(combined.length - tailBytes);
      }
    } finally {
      await raf.close();
    }

    return RecordingMediaProbeResult(
      hasVideoTrack: hasVideo,
      hasAudioTrack: hasAudio,
      bytesScanned: bytesScanned,
    );
  }

  int get _maxMarkerLength {
    final allMarkers = [..._videoMarkers, ..._audioMarkers];
    return allMarkers.fold<int>(0, (max, marker) {
      return marker.length > max ? marker.length : max;
    });
  }

  bool _containsAnyAscii(List<int> bytes, List<String> markers) {
    for (final marker in markers) {
      if (_containsAscii(bytes, marker)) return true;
    }
    return false;
  }

  bool _containsAscii(List<int> bytes, String marker) {
    final pattern = marker.codeUnits;
    if (bytes.length < pattern.length) return false;
    for (var i = 0; i <= bytes.length - pattern.length; i++) {
      var matched = true;
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return true;
    }
    return false;
  }
}
