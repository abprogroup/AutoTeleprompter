import 'dart:io';

import 'package:autoteleprompter/features/settings/models/app_settings.dart';
import 'package:autoteleprompter/platform/stt/offline_stt_model_catalog.dart';
import 'package:autoteleprompter/platform/stt/offline_stt_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('OfflineSttModelCatalog', () {
    test('defines all 8 offline engines with valid HE and EN packs', () {
      expect(OfflineSttModelCatalog.engines.length, 8);
      for (final engine in OfflineSttModelCatalog.engines) {
        expect(AppSettings.isOfflineSherpaEngine(engine.engineId), isTrue);
        expect(engine.hebrewPack.languageCode, 'he');
        expect(engine.englishPack.languageCode, 'en');
        expect(engine.packForLocale('he_IL').packId, engine.hebrewPackId);
        expect(engine.packForLocale('en_US').packId, engine.englishPackId);
      }
    });

    test('Parakeet v3 and v2 share the same Hebrew pack on disk', () {
      final v3 = OfflineSttModelCatalog.engineById(
        AppSettings.sttEngineOfflineParakeetV3,
      )!;
      final v2 = OfflineSttModelCatalog.engineById(
        AppSettings.sttEngineOfflineParakeetV2,
      )!;
      expect(v3.hebrewPackId, v2.hebrewPackId);
      expect(v3.englishPackId, isNot(v2.englishPackId));
    });

    test('all model files use HTTPS Hugging Face URLs with positive sizes', () {
      for (final pack in OfflineSttModelCatalog.packs) {
        expect(
          pack.files.length,
          pack.recognizerKind == OfflineSttRecognizerKind.onlineNemoCtc ? 2 : 4,
        );
        for (final file in pack.files) {
          expect(file.downloadUrl.startsWith('https://huggingface.co/'), isTrue);
          expect(file.expectedBytes, greaterThan(0));
        }
      }
    });
  });

  group('OfflineSttModelManager', () {
    late Directory tempDir;
    late OfflineSttModelManager manager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('atp_offline_stt_mgr_');
      manager = OfflineSttModelManager(
        rootDirectoryResolver: () async => tempDir,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('detects missing, partial, complete, and deleted packs accurately', () async {
      const pack = OfflineSttModelPack(
        packId: 'test_small_pack',
        languageCode: 'he',
        languageLabel: 'Hebrew',
        displayName: 'Test Small Pack',
        sourceRepo: 'test/repo',
        recognizerKind: OfflineSttRecognizerKind.onlineZipformer2,
        encoderFileName: 'encoder.onnx',
        decoderFileName: 'decoder.onnx',
        joinerFileName: 'joiner.onnx',
        tokensFileName: 'tokens.txt',
        files: [
          OfflineSttModelFileSpec(
            localName: 'encoder.onnx',
            downloadUrl: 'https://huggingface.co/test/encoder.onnx',
            expectedBytes: 12,
          ),
          OfflineSttModelFileSpec(
            localName: 'decoder.onnx',
            downloadUrl: 'https://huggingface.co/test/decoder.onnx',
            expectedBytes: 8,
          ),
          OfflineSttModelFileSpec(
            localName: 'joiner.onnx',
            downloadUrl: 'https://huggingface.co/test/joiner.onnx',
            expectedBytes: 6,
          ),
          OfflineSttModelFileSpec(
            localName: 'tokens.txt',
            downloadUrl: 'https://huggingface.co/test/tokens.txt',
            expectedBytes: 4,
          ),
        ],
      );

      expect(await manager.isPackInstalled(pack), isFalse);

      final dir = await manager.packDirectory(pack.packId);
      await dir.create(recursive: true);

      // Partial install (wrong size on encoder) -> must not be considered installed.
      await File(p.join(dir.path, 'encoder.onnx')).writeAsBytes(List.filled(5, 1));
      await File(p.join(dir.path, 'decoder.onnx')).writeAsBytes(List.filled(8, 2));
      await File(p.join(dir.path, 'joiner.onnx')).writeAsBytes(List.filled(6, 3));
      await File(p.join(dir.path, 'tokens.txt')).writeAsBytes(List.filled(4, 4));
      expect(await manager.isPackInstalled(pack), isFalse);

      // Exact sizes -> installed & paths resolve properly.
      await File(p.join(dir.path, 'encoder.onnx')).writeAsBytes(List.filled(12, 1));
      final resolved = await manager.resolveInstalledPack(pack);
      expect(resolved, isNotNull);
      expect(resolved!.encoderPath, p.join(dir.path, 'encoder.onnx'));
      expect(resolved.tokensPath, p.join(dir.path, 'tokens.txt'));

      // Delete removes directory cleanly.
      await manager.deletePack(pack.packId);
      expect(await manager.isPackInstalled(pack), isFalse);
      expect(await dir.exists(), isFalse);
    });
  });
}
