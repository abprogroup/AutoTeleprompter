import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'abstract_stt_service.dart';

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

class _WaveInputBuffer {
  final Pointer<Uint8> data;
  final Pointer<_WaveHdr> header;

  const _WaveInputBuffer({required this.data, required this.header});
}

class WindowsWaveInException implements Exception {
  final String message;

  const WindowsWaveInException(this.message);

  @override
  String toString() => message;
}

/// Captures 16 kHz, 16-bit mono PCM audio on Windows via `winmm.dll` FFI
/// without requiring any extra native microphone plugins.
class WindowsWaveInPcmStream {
  WindowsWaveInPcmStream();

  static const int sampleRate = 16000;
  static const int _waveMapper = 0xFFFFFFFF;
  static const int _waveFormatPcm = 1;
  static const int _callbackNull = 0;
  static const int _mmSysErrNoError = 0;
  static const int _whdrDone = 0x00000001;
  static const int _channels = 1;
  static const int _bitsPerSample = 16;
  static const int _bufferMilliseconds = 50;
  static const int _bufferCount = 8;
  static const int _waveInCapsWSize = 80;
  static const int _waveInCapsNameOffset = 8;
  static const int _waveInCapsMaxNameChars = 32;

  DynamicLibrary? _winmm;
  int Function()? _waveInGetNumDevs;
  int Function(int, Pointer<Uint8>, int)? _waveInGetDevCapsW;
  int Function(
    Pointer<IntPtr>,
    int,
    Pointer<_WaveFormatEx>,
    int,
    int,
    int,
  )? _waveInOpen;
  int Function(int, Pointer<_WaveHdr>, int)? _waveInPrepareHeader;
  int Function(int, Pointer<_WaveHdr>, int)? _waveInUnprepareHeader;
  int Function(int, Pointer<_WaveHdr>, int)? _waveInAddBuffer;
  int Function(int)? _waveInStart;
  int Function(int)? _waveInStop;
  int Function(int)? _waveInReset;
  int Function(int)? _waveInClose;

  final List<_WaveInputBuffer> _buffers = [];
  Timer? _pollTimer;
  int? _handle;
  bool _capturing = false;
  void Function(Float32List samples, double rmsLevel)? _onSamples;

  bool get isCapturing => _capturing;

  void _ensureBindings() {
    if (_winmm != null) return;
    if (!Platform.isWindows) {
      throw const WindowsWaveInException(
        'Windows WaveIn capture is available on Windows only.',
      );
    }
    final lib = DynamicLibrary.open('winmm.dll');
    _winmm = lib;
    _waveInGetNumDevs = lib.lookupFunction<Uint32 Function(), int Function()>(
      'waveInGetNumDevs',
    );
    _waveInGetDevCapsW = lib.lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int)
    >('waveInGetDevCapsW');
    _waveInOpen = lib.lookupFunction<
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
      )
    >('waveInOpen');
    _waveInPrepareHeader = lib.lookupFunction<
      Uint32 Function(IntPtr, Pointer<_WaveHdr>, Uint32),
      int Function(int, Pointer<_WaveHdr>, int)
    >('waveInPrepareHeader');
    _waveInUnprepareHeader = lib.lookupFunction<
      Uint32 Function(IntPtr, Pointer<_WaveHdr>, Uint32),
      int Function(int, Pointer<_WaveHdr>, int)
    >('waveInUnprepareHeader');
    _waveInAddBuffer = lib.lookupFunction<
      Uint32 Function(IntPtr, Pointer<_WaveHdr>, Uint32),
      int Function(int, Pointer<_WaveHdr>, int)
    >('waveInAddBuffer');
    _waveInStart = lib.lookupFunction<
      Uint32 Function(IntPtr),
      int Function(int)
    >('waveInStart');
    _waveInStop = lib.lookupFunction<
      Uint32 Function(IntPtr),
      int Function(int)
    >('waveInStop');
    _waveInReset = lib.lookupFunction<
      Uint32 Function(IntPtr),
      int Function(int)
    >('waveInReset');
    _waveInClose = lib.lookupFunction<
      Uint32 Function(IntPtr),
      int Function(int)
    >('waveInClose');
  }

  List<SttAudioInputDevice> listInputDevices() {
    if (!Platform.isWindows) return const [];
    _ensureBindings();
    final count = _waveInGetNumDevs!();
    if (count <= 0) return const [];

    final caps = calloc<Uint8>(_waveInCapsWSize);
    final devices = <SttAudioInputDevice>[];
    try {
      for (var index = 0; index < count; index++) {
        final rc = _waveInGetDevCapsW!(index, caps, _waveInCapsWSize);
        if (rc != _mmSysErrNoError) continue;
        final label = _readUtf16Name(caps);
        devices.add(
          SttAudioInputDevice(
            id: 'winmm:$index',
            label: label.isEmpty ? 'Microphone ${index + 1}' : label,
          ),
        );
      }
    } finally {
      calloc.free(caps);
    }
    return devices;
  }

  int resolveDeviceIndex({String? preferredDeviceId, String? preferredLabel}) {
    final devices = listInputDevices();
    if (devices.isEmpty) return _waveMapper;

    final id = (preferredDeviceId ?? '').trim();
    if (id.startsWith('winmm:')) {
      final parsed = int.tryParse(id.substring('winmm:'.length));
      if (parsed != null && parsed >= 0 && parsed < devices.length) {
        return parsed;
      }
    }

    final wanted = _normalizeLabel(preferredLabel ?? '');
    if (wanted.isNotEmpty && wanted != 'system default microphone') {
      for (var i = 0; i < devices.length; i++) {
        final candidate = _normalizeLabel(devices[i].label);
        if (candidate == wanted) return i;
      }
      if (wanted.length >= 6) {
        for (var i = 0; i < devices.length; i++) {
          final candidate = _normalizeLabel(devices[i].label);
          if (candidate.length >= 6 &&
              (wanted.contains(candidate) || candidate.contains(wanted))) {
            return i;
          }
        }
      }
    }

    return _waveMapper;
  }

  void start({
    required void Function(Float32List samples, double rmsLevel) onSamples,
    String? preferredDeviceId,
    String? preferredLabel,
  }) {
    _ensureBindings();
    if (_capturing) stop();

    if (_waveInGetNumDevs!() <= 0) {
      throw const WindowsWaveInException('No Windows microphone was found.');
    }

    _onSamples = onSamples;
    final deviceIndex = resolveDeviceIndex(
      preferredDeviceId: preferredDeviceId,
      preferredLabel: preferredLabel,
    );

    try {
      _openWaveInput(deviceIndex);
      _prepareBuffers();
      _check(_waveInStart!(_handle!), 'start microphone capture');
      _capturing = true;
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => _collectDoneBuffers(requeue: true),
      );
    } catch (_) {
      stop();
      rethrow;
    }
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _onSamples = null;
    if (_handle != null) {
      _waveInStop!(_handle!);
      _waveInReset!(_handle!);
    }
    _capturing = false;
    _cleanupNative();
  }

  void _openWaveInput(int deviceIndex) {
    final format = calloc<_WaveFormatEx>();
    final handle = calloc<IntPtr>();
    try {
      const blockAlign = _channels * _bitsPerSample ~/ 8;
      format.ref
        ..wFormatTag = _waveFormatPcm
        ..nChannels = _channels
        ..nSamplesPerSec = sampleRate
        ..nAvgBytesPerSec = sampleRate * blockAlign
        ..nBlockAlign = blockAlign
        ..wBitsPerSample = _bitsPerSample
        ..cbSize = 0;
      _check(
        _waveInOpen!(
          handle,
          deviceIndex,
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
        (sampleRate * blockAlign * _bufferMilliseconds / 1000).round();
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
        _waveInPrepareHeader!(_handle!, header, headerSize),
        'prepare microphone buffer',
      );
      _check(
        _waveInAddBuffer!(_handle!, header, headerSize),
        'queue microphone buffer',
      );
      _buffers.add(_WaveInputBuffer(data: data, header: header));
    }
  }

  void _collectDoneBuffers({required bool requeue}) {
    final handle = _handle;
    final callback = _onSamples;
    if (handle == null || callback == null) return;

    final headerSize = sizeOf<_WaveHdr>();
    for (final buffer in _buffers) {
      final header = buffer.header.ref;
      if ((header.dwFlags & _whdrDone) == 0) continue;
      final recordedBytes = header.dwBytesRecorded;
      if (recordedBytes >= 2) {
        final sampleCount = recordedBytes ~/ 2;
        final rawBytes = buffer.data.asTypedList(sampleCount * 2);
        final byteData = ByteData.sublistView(rawBytes);
        final samples = Float32List(sampleCount);
        var sumSquares = 0.0;
        for (var i = 0; i < sampleCount; i++) {
          final normalized = byteData.getInt16(i * 2, Endian.little) / 32768.0;
          samples[i] = normalized;
          sumSquares += normalized * normalized;
        }
        final rms = math.sqrt(sumSquares / sampleCount);
        // Logarithmic-like boost so normal conversational speech on laptop mics
        // registers visibly on the 0..1 Mic Signal Meter.
        final level = (math.sqrt(rms) * 2.2).clamp(0.0, 1.0);
        header.dwBytesRecorded = 0;
        callback(samples, level);
      }
      if (requeue && _handle != null) {
        header.dwFlags = header.dwFlags & ~_whdrDone;
        _waveInAddBuffer!(handle, buffer.header, headerSize);
      }
    }
  }

  void _cleanupNative() {
    final handle = _handle;
    if (handle != null) {
      final headerSize = sizeOf<_WaveHdr>();
      for (final buffer in _buffers) {
        _waveInUnprepareHeader!(handle, buffer.header, headerSize);
      }
      _waveInClose!(handle);
      _handle = null;
    }
    for (final buffer in _buffers) {
      calloc.free(buffer.data);
      calloc.free(buffer.header);
    }
    _buffers.clear();
  }

  String _readUtf16Name(Pointer<Uint8> caps) {
    final codeUnits = <int>[];
    final bytes = caps.asTypedList(_waveInCapsWSize);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < _waveInCapsMaxNameChars; i++) {
      final unit = view.getUint16(
        _waveInCapsNameOffset + (i * 2),
        Endian.little,
      );
      if (unit == 0) break;
      codeUnits.add(unit);
    }
    return String.fromCharCodes(codeUnits).trim();
  }

  String _normalizeLabel(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  void _check(int result, String action) {
    if (result != _mmSysErrNoError) {
      throw WindowsWaveInException(
        'Could not $action. Windows audio error $result.',
      );
    }
  }
}
