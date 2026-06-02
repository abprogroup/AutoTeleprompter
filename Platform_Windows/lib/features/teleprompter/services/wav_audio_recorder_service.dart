import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'recording_export_service.dart';

final class _WaveFormatEx extends Struct {
  @Uint16()
  external int wFormatTag;

  @Uint16()
  external int nChannels;

  @Uint32()
  external int nSamplesPerSec;

  @Uint32()
  external int nAvgBytesPerSec;

  @Uint16()
  external int nBlockAlign;

  @Uint16()
  external int wBitsPerSample;

  @Uint16()
  external int cbSize;
}

final class _WaveHdr extends Struct {
  external Pointer<Uint8> lpData;

  @Uint32()
  external int dwBufferLength;

  @Uint32()
  external int dwBytesRecorded;

  @IntPtr()
  external int dwUser;

  @Uint32()
  external int dwFlags;

  @Uint32()
  external int dwLoops;

  external Pointer<_WaveHdr> lpNext;

  @IntPtr()
  external int reserved;
}

class WavAudioRecorderException implements Exception {
  final String message;

  const WavAudioRecorderException(this.message);

  @override
  String toString() => message;
}

class _WaveInputBuffer {
  final Pointer<Uint8> data;
  final Pointer<_WaveHdr> header;

  const _WaveInputBuffer({required this.data, required this.header});
}

class WavAudioRecorderService {
  WavAudioRecorderService();

  static const int _waveMapper = 0xFFFFFFFF;
  static const int _waveFormatPcm = 1;
  static const int _callbackNull = 0;
  static const int _mmSysErrNoError = 0;
  static const int _whdrDone = 0x00000001;
  static const int _sampleRate = 44100;
  static const int _channels = 1;
  static const int _bitsPerSample = 16;
  static const int _bufferMilliseconds = 100;
  static const int _bufferCount = 4;

  final DynamicLibrary _winmm = DynamicLibrary.open('winmm.dll');
  late final int Function() _waveInGetNumDevs = _winmm
      .lookupFunction<Uint32 Function(), int Function()>('waveInGetNumDevs');
  late final int Function(
    Pointer<IntPtr>,
    int,
    Pointer<_WaveFormatEx>,
    int,
    int,
    int,
  ) _waveInOpen = _winmm.lookupFunction<
      Uint32 Function(
        Pointer<IntPtr>,
        Uint32,
        Pointer<_WaveFormatEx>,
        IntPtr,
        IntPtr,
        Uint32,
      ),
      int Function(
        Pointer<IntPtr>,
        int,
        Pointer<_WaveFormatEx>,
        int,
        int,
        int,
      )>('waveInOpen');
  late final int Function(int, Pointer<_WaveHdr>, int) _waveInPrepareHeader =
      _winmm.lookupFunction<Uint32 Function(IntPtr, Pointer<_WaveHdr>, Uint32),
          int Function(int, Pointer<_WaveHdr>, int)>('waveInPrepareHeader');
  late final int Function(int, Pointer<_WaveHdr>, int) _waveInUnprepareHeader =
      _winmm.lookupFunction<Uint32 Function(IntPtr, Pointer<_WaveHdr>, Uint32),
          int Function(int, Pointer<_WaveHdr>, int)>('waveInUnprepareHeader');
  late final int Function(int, Pointer<_WaveHdr>, int) _waveInAddBuffer =
      _winmm.lookupFunction<Uint32 Function(IntPtr, Pointer<_WaveHdr>, Uint32),
          int Function(int, Pointer<_WaveHdr>, int)>('waveInAddBuffer');
  late final int Function(int) _waveInStart =
      _winmm.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
          'waveInStart');
  late final int Function(int) _waveInStop = _winmm
      .lookupFunction<Uint32 Function(IntPtr), int Function(int)>('waveInStop');
  late final int Function(int) _waveInReset =
      _winmm.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
          'waveInReset');
  late final int Function(int) _waveInClose =
      _winmm.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
          'waveInClose');

  final List<_WaveInputBuffer> _buffers = [];
  Timer? _pollTimer;
  IOSink? _pcmSink;
  File? _pcmFile;
  File? _outputFile;
  int? _handle;
  int _pcmBytes = 0;
  bool _recording = false;

  bool get isRecording => _recording;

  Future<String> start({
    required Directory destinationDirectory,
    DateTime? createdAt,
  }) async {
    if (!Platform.isWindows) {
      throw const WavAudioRecorderException(
        'WAV audio recording is currently available on Windows only.',
      );
    }
    if (_recording) {
      throw const WavAudioRecorderException(
          'Audio recording is already active.');
    }
    if (_waveInGetNumDevs() <= 0) {
      throw const WavAudioRecorderException('No Windows microphone was found.');
    }

    _outputFile = await const RecordingExportService().reserveTargetFile(
      destinationDirectory: destinationDirectory,
      format: 'wav',
      createdAt: createdAt,
    );
    _pcmFile = File('${_outputFile!.path}.pcm.tmp');
    _pcmSink = _pcmFile!.openWrite();
    _pcmBytes = 0;

    try {
      _openWaveInput();
      _prepareBuffers();
      _check(_waveInStart(_handle!), 'start microphone capture');
      _recording = true;
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 25),
        (_) => _collectDoneBuffers(requeue: true),
      );
      return _outputFile!.path;
    } catch (error, stack) {
      await cancel();
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<String> stop() async {
    if (!_recording && _handle == null) {
      throw const WavAudioRecorderException('Audio recording is not active.');
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_handle != null) {
      _waveInStop(_handle!);
      _waveInReset(_handle!);
      _collectDoneBuffers(requeue: false);
    }
    _recording = false;
    await _pcmSink?.close();
    _pcmSink = null;
    _cleanupNative();
    return _finishWavFile();
  }

  Future<void> cancel() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_handle != null) {
      _waveInStop(_handle!);
      _waveInReset(_handle!);
    }
    _recording = false;
    await _pcmSink?.close();
    _pcmSink = null;
    _cleanupNative();
    await _deleteIfExists(_pcmFile);
    await _deleteIfExists(_outputFile);
    _pcmFile = null;
    _outputFile = null;
    _pcmBytes = 0;
  }

  void _openWaveInput() {
    final format = calloc<_WaveFormatEx>();
    final handle = calloc<IntPtr>();
    try {
      const blockAlign = _channels * _bitsPerSample ~/ 8;
      format.ref
        ..wFormatTag = _waveFormatPcm
        ..nChannels = _channels
        ..nSamplesPerSec = _sampleRate
        ..nAvgBytesPerSec = _sampleRate * blockAlign
        ..nBlockAlign = blockAlign
        ..wBitsPerSample = _bitsPerSample
        ..cbSize = 0;
      _check(
        _waveInOpen(
          handle,
          _waveMapper,
          format,
          0,
          0,
          _callbackNull,
        ),
        'open the Windows microphone',
      );
      _handle = handle.value;
    } finally {
      calloc.free(handle);
      calloc.free(format);
    }
  }

  void _prepareBuffers() {
    const blockAlign = _channels * _bitsPerSample ~/ 8;
    final bytesPerBuffer =
        (_sampleRate * blockAlign * _bufferMilliseconds / 1000).round();
    final headerSize = sizeOf<_WaveHdr>();
    for (var i = 0; i < _bufferCount; i++) {
      final data = calloc<Uint8>(bytesPerBuffer);
      final header = calloc<_WaveHdr>();
      header.ref
        ..lpData = data
        ..dwBufferLength = bytesPerBuffer
        ..dwBytesRecorded = 0
        ..dwUser = 0
        ..dwFlags = 0
        ..dwLoops = 0
        ..lpNext = nullptr
        ..reserved = 0;
      _check(
        _waveInPrepareHeader(_handle!, header, headerSize),
        'prepare microphone buffer',
      );
      _check(
        _waveInAddBuffer(_handle!, header, headerSize),
        'queue microphone buffer',
      );
      _buffers.add(_WaveInputBuffer(data: data, header: header));
    }
  }

  void _collectDoneBuffers({required bool requeue}) {
    if (_pcmSink == null || _handle == null) return;
    final headerSize = sizeOf<_WaveHdr>();
    for (final buffer in _buffers) {
      final header = buffer.header.ref;
      if ((header.dwFlags & _whdrDone) == 0) continue;
      final recorded = header.dwBytesRecorded;
      if (recorded > 0) {
        _pcmSink!.add(buffer.data.asTypedList(recorded));
        _pcmBytes += recorded;
        header.dwBytesRecorded = 0;
      }
      if (requeue) {
        _check(
          _waveInAddBuffer(_handle!, buffer.header, headerSize),
          'requeue microphone buffer',
        );
      }
    }
  }

  Future<String> _finishWavFile() async {
    final pcmFile = _pcmFile;
    final outputFile = _outputFile;
    if (pcmFile == null || outputFile == null) {
      throw const WavAudioRecorderException('Audio recording file is missing.');
    }
    final output = outputFile.openWrite();
    try {
      output.add(_buildHeader(dataBytes: _pcmBytes));
      await output.addStream(pcmFile.openRead());
    } finally {
      await output.close();
    }
    await _deleteIfExists(pcmFile);
    _pcmFile = null;
    _outputFile = null;
    return outputFile.path;
  }

  Uint8List _buildHeader({required int dataBytes}) {
    final bytes = Uint8List(44);
    final data = ByteData.sublistView(bytes);
    void writeAscii(int offset, String value) {
      bytes.setRange(offset, offset + value.length, ascii.encode(value));
    }

    const blockAlign = _channels * _bitsPerSample ~/ 8;
    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + dataBytes, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, _waveFormatPcm, Endian.little);
    data.setUint16(22, _channels, Endian.little);
    data.setUint32(24, _sampleRate, Endian.little);
    data.setUint32(28, _sampleRate * blockAlign, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, _bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, dataBytes, Endian.little);
    return bytes;
  }

  void _cleanupNative() {
    final handle = _handle;
    if (handle != null) {
      final headerSize = sizeOf<_WaveHdr>();
      for (final buffer in _buffers) {
        _waveInUnprepareHeader(handle, buffer.header, headerSize);
      }
      _waveInClose(handle);
      _handle = null;
    }
    for (final buffer in _buffers) {
      calloc.free(buffer.data);
      calloc.free(buffer.header);
    }
    _buffers.clear();
  }

  void _check(int result, String action) {
    if (result != _mmSysErrNoError) {
      throw WavAudioRecorderException(
        'Could not $action. Windows audio error $result.',
      );
    }
  }

  Future<void> _deleteIfExists(File? file) async {
    if (file == null || !await file.exists()) return;
    await file.delete();
  }
}
