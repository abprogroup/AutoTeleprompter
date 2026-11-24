import '../../features/settings/models/app_settings.dart';

enum OfflineSttRecognizerKind {
  /// True frame-by-frame streaming transducer (Zipformer2 / Kroko via OnlineRecognizer).
  onlineZipformer2,

  /// Ultra-low-latency streaming NVIDIA NeMo FastConformer CTC (80ms / 480ms).
  onlineNemoCtc,

  /// High-accuracy NeMo TDT transducer (Parakeet 0.6B via OfflineRecognizer
  /// fed with low-latency rolling audio windows).
  offlineNemoTransducer,
}

class OfflineSttModelFileSpec {
  final String localName;
  final String downloadUrl;
  final int expectedBytes;
  final String? expectedSha256;

  const OfflineSttModelFileSpec({
    required this.localName,
    required this.downloadUrl,
    required this.expectedBytes,
    this.expectedSha256,
  });
}

class OfflineSttModelPack {
  final String packId;
  final String languageCode; // 'he' or 'en'
  final String languageLabel;
  final String displayName;
  final String sourceRepo;
  final OfflineSttRecognizerKind recognizerKind;
  final String encoderFileName;
  final String decoderFileName;
  final String joinerFileName;
  final String tokensFileName;
  final List<OfflineSttModelFileSpec> files;

  const OfflineSttModelPack({
    required this.packId,
    required this.languageCode,
    required this.languageLabel,
    required this.displayName,
    required this.sourceRepo,
    required this.recognizerKind,
    required this.encoderFileName,
    required this.decoderFileName,
    required this.joinerFileName,
    required this.tokensFileName,
    required this.files,
  });

  int get totalBytes =>
      files.fold<int>(0, (sum, file) => sum + file.expectedBytes);

  String get approxSizeLabel {
    final mb = totalBytes / (1024 * 1024);
    if (mb >= 100) return '${mb.round()} MB';
    return '${mb.toStringAsFixed(0)} MB';
  }
}

class OfflineSttEngineSpec {
  final String engineId;
  final String chipLabel;
  final String shortLabel;
  final String description;
  final String hebrewPackId;
  final String englishPackId;
  final bool isStreaming;

  const OfflineSttEngineSpec({
    required this.engineId,
    required this.chipLabel,
    required this.shortLabel,
    required this.description,
    required this.hebrewPackId,
    required this.englishPackId,
    required this.isStreaming,
  });

  OfflineSttModelPack get hebrewPack =>
      OfflineSttModelCatalog.packById(hebrewPackId)!;

  OfflineSttModelPack get englishPack =>
      OfflineSttModelCatalog.packById(englishPackId)!;

  OfflineSttModelPack packForLocale(String? localeId) {
    final normalized = (localeId ?? '').toLowerCase();
    if (normalized.startsWith('en')) return englishPack;
    return hebrewPack;
  }

  OfflineSttModelPack alternatePackForLocale(String? localeId) {
    final normalized = (localeId ?? '').toLowerCase();
    if (normalized.startsWith('en')) return hebrewPack;
    return englishPack;
  }
}

class OfflineSttModelCatalog {
  const OfflineSttModelCatalog._();

  static const String packHeZipformerInt8 = 'he_zipformer2_66m_int8';
  static const String packEnNemoCtc80msInt8 = 'en_nemo_ctc_80ms_int8';
  static const String packEnNemoCtc480msInt8 = 'en_nemo_ctc_480ms_int8';
  static const String packEnKroko64lInt8 = 'en_kroko_64l_int8';
  static const String packEnKroko128lInt8 = 'en_kroko_128l_int8';
  static const String packEnZipformerInt8 = 'en_zipformer2_2023_int8';
  static const String packHeZipformerFp32 = 'he_zipformer2_66m_fp32';
  static const String packEnZipformerFp32 = 'en_zipformer2_2023_fp32';
  static const String packHeParakeetV3Int8 = 'he_parakeet_tdt_06b_v3_int8';
  static const String packEnParakeetV3Int8 = 'en_parakeet_tdt_06b_v3_int8';
  static const String packEnParakeetV2Int8 = 'en_parakeet_tdt_06b_v2_int8';

  static String _hf(String repo, String path) =>
      'https://huggingface.co/$repo/resolve/main/$path?download=true';

  static final List<OfflineSttModelPack> packs = List.unmodifiable([
    OfflineSttModelPack(
      packId: packHeZipformerInt8,
      languageCode: 'he',
      languageLabel: 'Hebrew',
      displayName: 'ivrit.ai Zipformer2 66M Streaming (INT8)',
      sourceRepo: 'ivrit-ai/zipformer2-66m-streaming-he',
      recognizerKind: OfflineSttRecognizerKind.onlineZipformer2,
      encoderFileName: 'encoder.int8.onnx',
      decoderFileName: 'decoder.int8.onnx',
      joinerFileName: 'joiner.int8.onnx',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'encoder.int8.onnx',
          downloadUrl: _hf(
            'ivrit-ai/zipformer2-66m-streaming-he',
            'sherpa-onnx/encoder.int8.onnx',
          ),
          expectedBytes: 70478964,
        ),
        OfflineSttModelFileSpec(
          localName: 'decoder.int8.onnx',
          downloadUrl: _hf(
            'ivrit-ai/zipformer2-66m-streaming-he',
            'sherpa-onnx/decoder.int8.onnx',
          ),
          expectedBytes: 1049105,
        ),
        OfflineSttModelFileSpec(
          localName: 'joiner.int8.onnx',
          downloadUrl: _hf(
            'ivrit-ai/zipformer2-66m-streaming-he',
            'sherpa-onnx/joiner.int8.onnx',
          ),
          expectedBytes: 771805,
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf(
            'ivrit-ai/zipformer2-66m-streaming-he',
            'sherpa-onnx/tokens.txt',
          ),
          expectedBytes: 17086,
        ),
      ],
    ),
    OfflineSttModelPack(
      packId: packEnNemoCtc80msInt8,
      languageCode: 'en',
      languageLabel: 'English',
      displayName: 'NVIDIA NeMo FastConformer 80ms English (INT8)',
      sourceRepo: 'hudaiapa88/sherpa-stt-onnx',
      recognizerKind: OfflineSttRecognizerKind.onlineNemoCtc,
      encoderFileName: 'model.int8.onnx',
      decoderFileName: '',
      joinerFileName: '',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'model.int8.onnx',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/nemo_ctc_80ms/model.int8.onnx',
          ),
          expectedBytes: 132048406,
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/nemo_ctc_80ms/tokens.txt',
          ),
          expectedBytes: 11896,
        ),
      ],
    ),
    OfflineSttModelPack(
      packId: packEnNemoCtc480msInt8,
      languageCode: 'en',
      languageLabel: 'English',
      displayName: 'NVIDIA NeMo FastConformer 480ms Reading English (INT8)',
      sourceRepo: 'hudaiapa88/sherpa-stt-onnx',
      recognizerKind: OfflineSttRecognizerKind.onlineNemoCtc,
      encoderFileName: 'model.int8.onnx',
      decoderFileName: '',
      joinerFileName: '',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'model.int8.onnx',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/nemo_ctc_480ms/model.int8.onnx',
          ),
          expectedBytes: 132048430,
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/nemo_ctc_480ms/tokens.txt',
          ),
          expectedBytes: 11896,
        ),
      ],
    ),
    OfflineSttModelPack(
      packId: packEnKroko64lInt8,
      languageCode: 'en',
      languageLabel: 'English',
      displayName: 'Kroko 64L Streaming English (INT8, 1.28s chunks)',
      sourceRepo: 'hudaiapa88/sherpa-stt-onnx',
      recognizerKind: OfflineSttRecognizerKind.onlineZipformer2,
      encoderFileName: 'encoder.int8.onnx',
      decoderFileName: 'decoder.int8.onnx',
      joinerFileName: 'joiner.int8.onnx',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'encoder.int8.onnx',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/kroko_64l/encoder.int8.onnx',
          ),
          expectedBytes: 153185990,
        ),
        OfflineSttModelFileSpec(
          localName: 'decoder.int8.onnx',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/kroko_64l/decoder.int8.onnx',
          ),
          expectedBytes: 606496,
        ),
        OfflineSttModelFileSpec(
          localName: 'joiner.int8.onnx',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/kroko_64l/joiner.int8.onnx',
          ),
          expectedBytes: 337105,
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/kroko_64l/tokens.txt',
          ),
          expectedBytes: 6868,
        ),
      ],
    ),
    OfflineSttModelPack(
      packId: packEnKroko128lInt8,
      languageCode: 'en',
      languageLabel: 'English',
      displayName: 'Kroko 128L Multi-Accent Streaming English (INT8)',
      sourceRepo: 'hudaiapa88/sherpa-stt-onnx',
      recognizerKind: OfflineSttRecognizerKind.onlineZipformer2,
      encoderFileName: 'encoder.int8.onnx',
      decoderFileName: 'decoder.int8.onnx',
      joinerFileName: 'joiner.int8.onnx',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'encoder.int8.onnx',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/kroko_128l/encoder.int8.onnx',
          ),
          expectedBytes: 153182957,
        ),
        OfflineSttModelFileSpec(
          localName: 'decoder.int8.onnx',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/kroko_128l/decoder.int8.onnx',
          ),
          expectedBytes: 606497,
        ),
        OfflineSttModelFileSpec(
          localName: 'joiner.int8.onnx',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/kroko_128l/joiner.int8.onnx',
          ),
          expectedBytes: 337105,
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf(
            'hudaiapa88/sherpa-stt-onnx',
            'en/kroko_128l/tokens.txt',
          ),
          expectedBytes: 6868,
        ),
      ],
    ),
    OfflineSttModelPack(
      packId: packEnZipformerInt8,
      languageCode: 'en',
      languageLabel: 'English',
      displayName: 'Zipformer2 Streaming English (INT8)',
      sourceRepo: 'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
      recognizerKind: OfflineSttRecognizerKind.onlineZipformer2,
      encoderFileName: 'encoder.int8.onnx',
      decoderFileName: 'decoder.int8.onnx',
      joinerFileName: 'joiner.int8.onnx',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'encoder.int8.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
            'encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
          ),
          expectedBytes: 71083163,
        ),
        OfflineSttModelFileSpec(
          localName: 'decoder.int8.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
            'decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
          ),
          expectedBytes: 1307236,
        ),
        OfflineSttModelFileSpec(
          localName: 'joiner.int8.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
            'joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
          ),
          expectedBytes: 259335,
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
            'tokens.txt',
          ),
          expectedBytes: 5048,
        ),
      ],
    ),
    OfflineSttModelPack(
      packId: packHeZipformerFp32,
      languageCode: 'he',
      languageLabel: 'Hebrew',
      displayName: 'ivrit.ai Zipformer2 66M Streaming (FP32)',
      sourceRepo: 'ivrit-ai/zipformer2-66m-streaming-he',
      recognizerKind: OfflineSttRecognizerKind.onlineZipformer2,
      encoderFileName: 'encoder.onnx',
      decoderFileName: 'decoder.onnx',
      joinerFileName: 'joiner.onnx',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'encoder.onnx',
          downloadUrl: _hf(
            'ivrit-ai/zipformer2-66m-streaming-he',
            'onnx/encoder.onnx',
          ),
          expectedBytes: 261016892,
        ),
        OfflineSttModelFileSpec(
          localName: 'decoder.onnx',
          downloadUrl: _hf(
            'ivrit-ai/zipformer2-66m-streaming-he',
            'onnx/decoder.onnx',
          ),
          expectedBytes: 4126748,
        ),
        OfflineSttModelFileSpec(
          localName: 'joiner.onnx',
          downloadUrl: _hf(
            'ivrit-ai/zipformer2-66m-streaming-he',
            'onnx/joiner.onnx',
          ),
          expectedBytes: 3064101,
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf(
            'ivrit-ai/zipformer2-66m-streaming-he',
            'onnx/tokens.txt',
          ),
          expectedBytes: 17086,
        ),
      ],
    ),
    OfflineSttModelPack(
      packId: packEnZipformerFp32,
      languageCode: 'en',
      languageLabel: 'English',
      displayName: 'Zipformer2 Streaming English (FP32)',
      sourceRepo: 'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
      recognizerKind: OfflineSttRecognizerKind.onlineZipformer2,
      encoderFileName: 'encoder.onnx',
      decoderFileName: 'decoder.onnx',
      joinerFileName: 'joiner.onnx',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'encoder.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
            'encoder-epoch-99-avg-1-chunk-16-left-128.onnx',
          ),
          expectedBytes: 262127043,
        ),
        OfflineSttModelFileSpec(
          localName: 'decoder.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
            'decoder-epoch-99-avg-1-chunk-16-left-128.onnx',
          ),
          expectedBytes: 2092621,
        ),
        OfflineSttModelFileSpec(
          localName: 'joiner.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
            'joiner-epoch-99-avg-1-chunk-16-left-128.onnx',
          ),
          expectedBytes: 1026405,
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
            'tokens.txt',
          ),
          expectedBytes: 5048,
        ),
      ],
    ),
    OfflineSttModelPack(
      packId: packHeParakeetV3Int8,
      languageCode: 'he',
      languageLabel: 'Hebrew',
      displayName: 'Parakeet TDT 0.6B v3 Hebrew (INT8)',
      sourceRepo: 'krut42/voice-parakeet-he-int8',
      recognizerKind: OfflineSttRecognizerKind.offlineNemoTransducer,
      encoderFileName: 'encoder.int8.onnx',
      decoderFileName: 'decoder.int8.onnx',
      joinerFileName: 'joiner.int8.onnx',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'encoder.int8.onnx',
          downloadUrl: _hf('krut42/voice-parakeet-he-int8', 'encoder.int8.onnx'),
          expectedBytes: 653215173,
          expectedSha256:
              '7eaf80bc88fccd579a7d3950c25e50e4c7935e5b037ec2aa1eee29bca5ca3981',
        ),
        OfflineSttModelFileSpec(
          localName: 'decoder.int8.onnx',
          downloadUrl: _hf('krut42/voice-parakeet-he-int8', 'decoder.int8.onnx'),
          expectedBytes: 12494234,
          expectedSha256:
              '3a1d0bbf3e393909095f826b7719fdaef42cd2e0b8b95c54518034ecc4b7d246',
        ),
        OfflineSttModelFileSpec(
          localName: 'joiner.int8.onnx',
          downloadUrl: _hf('krut42/voice-parakeet-he-int8', 'joiner.int8.onnx'),
          expectedBytes: 7008293,
          expectedSha256:
              '056c5464464b38a9cbacdccb6a9ff2114919780badb5c48e0f0260af7f91ccf2',
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf('krut42/voice-parakeet-he-int8', 'tokens.txt'),
          expectedBytes: 107590,
          expectedSha256:
              '55a91c862d0a63e8b9587a3264ced4fc76943e66098468b4638e6a6c5642e364',
        ),
      ],
    ),
    OfflineSttModelPack(
      packId: packEnParakeetV3Int8,
      languageCode: 'en',
      languageLabel: 'English',
      displayName: 'Parakeet TDT 0.6B v3 Multilingual (INT8)',
      sourceRepo: 'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8',
      recognizerKind: OfflineSttRecognizerKind.offlineNemoTransducer,
      encoderFileName: 'encoder.int8.onnx',
      decoderFileName: 'decoder.int8.onnx',
      joinerFileName: 'joiner.int8.onnx',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'encoder.int8.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8',
            'encoder.int8.onnx',
          ),
          expectedBytes: 652282294,
        ),
        OfflineSttModelFileSpec(
          localName: 'decoder.int8.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8',
            'decoder.int8.onnx',
          ),
          expectedBytes: 11845274,
        ),
        OfflineSttModelFileSpec(
          localName: 'joiner.int8.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8',
            'joiner.int8.onnx',
          ),
          expectedBytes: 6355277,
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8',
            'tokens.txt',
          ),
          expectedBytes: 93939,
        ),
      ],
    ),
    OfflineSttModelPack(
      packId: packEnParakeetV2Int8,
      languageCode: 'en',
      languageLabel: 'English',
      displayName: 'Parakeet TDT 0.6B v2 English (INT8)',
      sourceRepo: 'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8',
      recognizerKind: OfflineSttRecognizerKind.offlineNemoTransducer,
      encoderFileName: 'encoder.int8.onnx',
      decoderFileName: 'decoder.int8.onnx',
      joinerFileName: 'joiner.int8.onnx',
      tokensFileName: 'tokens.txt',
      files: [
        OfflineSttModelFileSpec(
          localName: 'encoder.int8.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8',
            'encoder.int8.onnx',
          ),
          expectedBytes: 652282309,
        ),
        OfflineSttModelFileSpec(
          localName: 'decoder.int8.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8',
            'decoder.int8.onnx',
          ),
          expectedBytes: 7257753,
        ),
        OfflineSttModelFileSpec(
          localName: 'joiner.int8.onnx',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8',
            'joiner.int8.onnx',
          ),
          expectedBytes: 1739080,
        ),
        OfflineSttModelFileSpec(
          localName: 'tokens.txt',
          downloadUrl: _hf(
            'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8',
            'tokens.txt',
          ),
          expectedBytes: 9384,
        ),
      ],
    ),
  ]);

  static const List<OfflineSttEngineSpec> engines = [
    OfflineSttEngineSpec(
      engineId: AppSettings.sttEngineOfflineNemo80Streaming,
      chipLabel: 'Offline: NeMo 80ms EN + ivrit.ai HE (Instant)',
      shortLabel: 'NeMo 80ms + ivrit.ai',
      description:
          'Ultra-instant English streaming (80 ms chunks, NVIDIA FastConformer 126 MB) + ivrit.ai streaming Hebrew (69 MB, shared).',
      hebrewPackId: packHeZipformerInt8,
      englishPackId: packEnNemoCtc80msInt8,
      isStreaming: true,
    ),
    OfflineSttEngineSpec(
      engineId: AppSettings.sttEngineOfflineNemo480Streaming,
      chipLabel: 'Offline: NeMo 480ms EN + ivrit.ai HE (Reading)',
      shortLabel: 'NeMo 480ms + ivrit.ai',
      description:
          'Balanced English reading streaming (480 ms chunks, NVIDIA FastConformer 126 MB, ~6% WER) + ivrit.ai streaming Hebrew (69 MB, shared).',
      hebrewPackId: packHeZipformerInt8,
      englishPackId: packEnNemoCtc480msInt8,
      isStreaming: true,
    ),
    OfflineSttEngineSpec(
      engineId: AppSettings.sttEngineOfflineKroko64Streaming,
      chipLabel: 'Offline: Kroko 64L EN + ivrit.ai HE (Balanced)',
      shortLabel: 'Kroko 64L + ivrit.ai',
      description:
          '2x faster than Kroko 128L (1.28 s chunks, 147 MB INT8, ~5% WER) + ivrit.ai streaming Hebrew (69 MB, shared).',
      hebrewPackId: packHeZipformerInt8,
      englishPackId: packEnKroko64lInt8,
      isStreaming: true,
    ),
    OfflineSttEngineSpec(
      engineId: AppSettings.sttEngineOfflineKrokoStreaming,
      chipLabel: 'Offline: Kroko 128L EN + ivrit.ai HE (Max EN Acc)',
      shortLabel: 'Kroko 128L + ivrit.ai',
      description:
          'Highest streaming English accuracy (~4% WER, 2.56 s chunks, 147 MB INT8) + ivrit.ai streaming Hebrew (69 MB, shared).',
      hebrewPackId: packHeZipformerInt8,
      englishPackId: packEnKroko128lInt8,
      isStreaming: true,
    ),
    OfflineSttEngineSpec(
      engineId: AppSettings.sttEngineOfflineZipformerFast,
      chipLabel: 'Offline: Zipformer2 Fast (INT8)',
      shortLabel: 'Zipformer2 INT8',
      description:
          'True real-time streaming on CPU (~69 MB/lang). Lowest latency; auto-switches Hebrew and English when both packs are downloaded.',
      hebrewPackId: packHeZipformerInt8,
      englishPackId: packEnZipformerInt8,
      isStreaming: true,
    ),
    OfflineSttEngineSpec(
      engineId: AppSettings.sttEngineOfflineZipformerPrecision,
      chipLabel: 'Offline: Zipformer2 Precision (FP32)',
      shortLabel: 'Zipformer2 FP32',
      description:
          'Full-precision streaming Zipformer2 (~255 MB/lang). Same ultra-low latency as INT8 with unquantized weights for accuracy comparison.',
      hebrewPackId: packHeZipformerFp32,
      englishPackId: packEnZipformerFp32,
      isStreaming: true,
    ),
    OfflineSttEngineSpec(
      engineId: AppSettings.sttEngineOfflineParakeetV3,
      chipLabel: 'Offline: Parakeet TDT v3 (0.6B)',
      shortLabel: 'Parakeet v3',
      description:
          'High-accuracy 600M-parameter NeMo Parakeet TDT (~640 MB/lang). Runs rolling offline windows on CPU for comparing accuracy vs streaming speed.',
      hebrewPackId: packHeParakeetV3Int8,
      englishPackId: packEnParakeetV3Int8,
      isStreaming: false,
    ),
    OfflineSttEngineSpec(
      engineId: AppSettings.sttEngineOfflineParakeetV2,
      chipLabel: 'Offline: Parakeet TDT EN v2 + HE v3',
      shortLabel: 'Parakeet EN v2',
      description:
          'Pairs English-dedicated Parakeet TDT v2 (~631 MB) with Hebrew Parakeet v3 (shared download). Useful for comparing English v2 vs v3.',
      hebrewPackId: packHeParakeetV3Int8,
      englishPackId: packEnParakeetV2Int8,
      isStreaming: false,
    ),
  ];

  static OfflineSttModelPack? packById(String packId) {
    for (final pack in packs) {
      if (pack.packId == packId) return pack;
    }
    return null;
  }

  static OfflineSttEngineSpec? engineById(String? engineId) {
    for (final spec in engines) {
      if (spec.engineId == engineId) return spec;
    }
    return null;
  }
}
