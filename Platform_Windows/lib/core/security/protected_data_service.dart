import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

abstract class ProtectedDataService {
  const ProtectedDataService();

  Uint8List protect(Uint8List plaintext, {required String kind});

  Uint8List unprotect(Uint8List protectedBytes, {String? expectedKind});
}

class DpapiProtectedDataService extends ProtectedDataService {
  const DpapiProtectedDataService();

  @override
  Uint8List protect(Uint8List plaintext, {required String kind}) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows DPAPI is only available on Windows.');
    }
    return _withDataBlob(plaintext, (dataIn) {
      final dataOut =
          calloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
      final description = 'AutoTeleprompter:$kind'.toNativeUtf16();
      try {
        final ok = CryptProtectData(
          dataIn,
          description,
          nullptr,
          nullptr,
          nullptr,
          0,
          dataOut,
        );
        if (ok == 0) {
          throw StateError('CryptProtectData failed: ${GetLastError()}');
        }
        return _copyBlob(dataOut);
      } finally {
        if (dataOut.ref.pbData != nullptr) {
          LocalFree(dataOut.ref.pbData.cast());
        }
        calloc.free(description);
        calloc.free(dataOut);
      }
    });
  }

  @override
  Uint8List unprotect(Uint8List protectedBytes, {String? expectedKind}) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows DPAPI is only available on Windows.');
    }
    return _withDataBlob(protectedBytes, (dataIn) {
      final dataOut =
          calloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
      try {
        final ok = CryptUnprotectData(
          dataIn,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          0,
          dataOut,
        );
        if (ok == 0) {
          throw StateError('CryptUnprotectData failed: ${GetLastError()}');
        }
        return _copyBlob(dataOut);
      } finally {
        if (dataOut.ref.pbData != nullptr) {
          LocalFree(dataOut.ref.pbData.cast());
        }
        calloc.free(dataOut);
      }
    });
  }

  Uint8List _withDataBlob(
    Uint8List bytes,
    Uint8List Function(Pointer<CRYPT_INTEGER_BLOB> dataIn) action,
  ) {
    final dataIn =
        calloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
    final input = calloc.allocate<Uint8>(bytes.length);
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      dataIn.ref
        ..cbData = bytes.length
        ..pbData = input;
      return action(dataIn);
    } finally {
      calloc.free(input);
      calloc.free(dataIn);
    }
  }

  Uint8List _copyBlob(Pointer<CRYPT_INTEGER_BLOB> blob) {
    final length = blob.ref.cbData;
    if (length <= 0) return Uint8List(0);
    return Uint8List.fromList(blob.ref.pbData.asTypedList(length));
  }
}

class TestProtectedDataService extends ProtectedDataService {
  const TestProtectedDataService();

  @override
  Uint8List protect(Uint8List plaintext, {required String kind}) {
    final prefix = utf8.encode('TEST:$kind:');
    return Uint8List.fromList([...prefix, ...plaintext.reversed]);
  }

  @override
  Uint8List unprotect(Uint8List protectedBytes, {String? expectedKind}) {
    final text = utf8.decode(protectedBytes, allowMalformed: true);
    final prefix = 'TEST:${expectedKind ?? ''}';
    final separator = text.indexOf(':', 'TEST:'.length);
    if (!text.startsWith('TEST:') || separator < 0) {
      throw StateError('Invalid test protected payload.');
    }
    if (expectedKind != null && !text.startsWith('$prefix:')) {
      throw StateError('Protected payload kind mismatch.');
    }
    final prefixLength = separator + 1;
    return Uint8List.fromList(
        protectedBytes.sublist(prefixLength).reversed.toList());
  }
}
