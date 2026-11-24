import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'offline_stt_model_catalog.dart';
import 'sherpa_hotwords_builder.dart';

class LoadedSherpaOnlineModel {
  final String cacheKey;
  final sherpa_onnx.OnlineRecognizer recognizer;
  final String decodingMode;
  sherpa_onnx.OnlineStream stream;
  String activeHotwords;

  LoadedSherpaOnlineModel({
    required this.cacheKey,
    required this.recognizer,
    required this.decodingMode,
    required this.stream,
    required this.activeHotwords,
  });

  /// Recreates the native `OnlineStream` cleanly instead of calling
  /// `recognizer.reset(stream)`, avoiding the sherpa-onnx Zipformer2 state
  /// stall that can suppress output for ~20 s after an endpoint reset.
  void recreateStream({String? hotwords}) {
    if (hotwords != null) {
      activeHotwords = hotwords;
    }
    stream.free();
    if (activeHotwords.isNotEmpty && decodingMode == 'modified_beam_search') {
      try {
        stream = recognizer.createStream(hotwords: activeHotwords);
        return;
      } catch (_) {
        activeHotwords = '';
      }
    }
    stream = recognizer.createStream();
  }

  void dispose() {
    stream.free();
    recognizer.free();
  }
}

class LoadedSherpaOfflineModel {
  final String cacheKey;
  final sherpa_onnx.OfflineRecognizer recognizer;
  final String decodingMode;
  final int hotwordCount;
  final String? hotwordsFilePath;

  LoadedSherpaOfflineModel({
    required this.cacheKey,
    required this.recognizer,
    required this.decodingMode,
    required this.hotwordCount,
    this.hotwordsFilePath,
  });

  void dispose() {
    recognizer.free();
    final filePath = hotwordsFilePath;
    if (filePath != null && filePath.isNotEmpty) {
      try {
        final f = File(filePath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

class SherpaModelFactory {
  static const int sampleRate = 16000;

  static int recommendedThreads(OfflineSttRecognizerKind kind) {
    final cpus = Platform.numberOfProcessors;
    // Cap ONNX CPU threads so the CPU package and integrated GPU always retain
    // ample headroom for VSync-locked 60/120+ fps teleprompter scrolling.
    if (kind == OfflineSttRecognizerKind.offlineNemoTransducer) {
      return math.max(2, math.min(3, cpus ~/ 3));
    }
    return 2;
  }

  static LoadedSherpaOnlineModel createOnlineZipformerModel({
    required String cacheKey,
    required String encoder,
    required String decoder,
    required String joiner,
    required String tokens,
    required bool scriptBoostEnabled,
    required String hotwordsText,
  }) {
    final modelConfig = sherpa_onnx.OnlineModelConfig(
      transducer: sherpa_onnx.OnlineTransducerModelConfig(
        encoder: encoder,
        decoder: decoder,
        joiner: joiner,
      ),
      tokens: tokens,
      numThreads: recommendedThreads(OfflineSttRecognizerKind.onlineZipformer2),
      provider: 'cpu',
      debug: false,
      modelType: 'zipformer2',
    );

    if (scriptBoostEnabled) {
      try {
        final recognizer = sherpa_onnx.OnlineRecognizer(
          sherpa_onnx.OnlineRecognizerConfig(
            feat: const sherpa_onnx.FeatureConfig(
              sampleRate: sampleRate,
              featureDim: 80,
            ),
            model: modelConfig,
            decodingMethod: 'modified_beam_search',
            maxActivePaths: 4,
            hotwordsScore: 1.4,
            enableEndpoint: true,
            rule1MinTrailingSilence: 4.0,
            rule2MinTrailingSilence: 2.5,
            rule3MinUtteranceLength: 45.0,
          ),
        );
        String appliedHotwords = hotwordsText;
        sherpa_onnx.OnlineStream stream;
        if (appliedHotwords.isNotEmpty) {
          try {
            stream = recognizer.createStream(hotwords: appliedHotwords);
          } catch (_) {
            appliedHotwords = '';
            stream = recognizer.createStream();
          }
        } else {
          stream = recognizer.createStream();
        }
        return LoadedSherpaOnlineModel(
          cacheKey: cacheKey,
          recognizer: recognizer,
          decodingMode: 'modified_beam_search',
          stream: stream,
          activeHotwords: appliedHotwords,
        );
      } catch (_) {
        // Fall back cleanly to greedy search if beam search init fails.
      }
    }

    final recognizer = sherpa_onnx.OnlineRecognizer(
      sherpa_onnx.OnlineRecognizerConfig(
        feat: const sherpa_onnx.FeatureConfig(
          sampleRate: sampleRate,
          featureDim: 80,
        ),
        model: modelConfig,
        decodingMethod: 'greedy_search',
        enableEndpoint: true,
        rule1MinTrailingSilence: 4.0,
        rule2MinTrailingSilence: 2.5,
        rule3MinUtteranceLength: 45.0,
      ),
    );
    return LoadedSherpaOnlineModel(
      cacheKey: cacheKey,
      recognizer: recognizer,
      decodingMode: 'greedy_search',
      stream: recognizer.createStream(),
      activeHotwords: '',
    );
  }

  static LoadedSherpaOnlineModel createOnlineNemoCtcModel({
    required String cacheKey,
    required String modelPath,
    required String tokens,
  }) {
    final recognizer = sherpa_onnx.OnlineRecognizer(
      sherpa_onnx.OnlineRecognizerConfig(
        feat: const sherpa_onnx.FeatureConfig(
          sampleRate: sampleRate,
          featureDim: 80,
        ),
        model: sherpa_onnx.OnlineModelConfig(
          nemoCtc: sherpa_onnx.OnlineNemoCtcModelConfig(model: modelPath),
          tokens: tokens,
          numThreads: recommendedThreads(OfflineSttRecognizerKind.onlineNemoCtc),
          provider: 'cpu',
          debug: false,
        ),
        decodingMethod: 'greedy_search',
        enableEndpoint: true,
        rule1MinTrailingSilence: 4.0,
        rule2MinTrailingSilence: 2.5,
        rule3MinUtteranceLength: 45.0,
      ),
    );
    return LoadedSherpaOnlineModel(
      cacheKey: cacheKey,
      recognizer: recognizer,
      decodingMode: 'nemo_ctc_streaming',
      stream: recognizer.createStream(),
      activeHotwords: '',
    );
  }

  static LoadedSherpaOfflineModel createOfflineNemoTransducerModel({
    required String cacheKey,
    required String packId,
    required String encoder,
    required String decoder,
    required String joiner,
    required String tokens,
    required bool scriptBoostEnabled,
    required SherpaHotwordsResult hotwords,
  }) {
    final modelConfig = sherpa_onnx.OfflineModelConfig(
      transducer: sherpa_onnx.OfflineTransducerModelConfig(
        encoder: encoder,
        decoder: decoder,
        joiner: joiner,
      ),
      tokens: tokens,
      numThreads: recommendedThreads(
        OfflineSttRecognizerKind.offlineNemoTransducer,
      ),
      provider: 'cpu',
      debug: false,
      modelType: 'nemo_transducer',
    );

    if (scriptBoostEnabled) {
      String? hotwordsFilePath;
      if (hotwords.wordCount > 0 && hotwords.text.isNotEmpty) {
        try {
          hotwordsFilePath = p.join(
            Directory.systemTemp.path,
            'atp_sherpa_hotwords_$packId.txt',
          );
          File(hotwordsFilePath).writeAsStringSync(hotwords.text);
          final recognizer = sherpa_onnx.OfflineRecognizer(
            sherpa_onnx.OfflineRecognizerConfig(
              feat: const sherpa_onnx.FeatureConfig(
                sampleRate: sampleRate,
                featureDim: 128,
              ),
              model: modelConfig,
              decodingMethod: 'modified_beam_search',
              maxActivePaths: 4,
              hotwordsFile: hotwordsFilePath,
              hotwordsScore: 1.5,
            ),
          );
          return LoadedSherpaOfflineModel(
            cacheKey: cacheKey,
            recognizer: recognizer,
            decodingMode: 'modified_beam_search',
            hotwordCount: hotwords.wordCount,
            hotwordsFilePath: hotwordsFilePath,
          );
        } catch (_) {
          if (hotwordsFilePath != null) {
            try {
              final f = File(hotwordsFilePath);
              if (f.existsSync()) f.deleteSync();
            } catch (_) {}
          }
        }
      }

      // Fallback 1: beam search without hotwords file.
      try {
        final recognizer = sherpa_onnx.OfflineRecognizer(
          sherpa_onnx.OfflineRecognizerConfig(
            feat: const sherpa_onnx.FeatureConfig(
              sampleRate: sampleRate,
              featureDim: 128,
            ),
            model: modelConfig,
            decodingMethod: 'modified_beam_search',
            maxActivePaths: 4,
          ),
        );
        return LoadedSherpaOfflineModel(
          cacheKey: cacheKey,
          recognizer: recognizer,
          decodingMode: 'modified_beam_search',
          hotwordCount: 0,
        );
      } catch (_) {}
    }

    final recognizer = sherpa_onnx.OfflineRecognizer(
      sherpa_onnx.OfflineRecognizerConfig(
        feat: const sherpa_onnx.FeatureConfig(
          sampleRate: sampleRate,
          featureDim: 128,
        ),
        model: modelConfig,
        decodingMethod: 'greedy_search',
      ),
    );
    return LoadedSherpaOfflineModel(
      cacheKey: cacheKey,
      recognizer: recognizer,
      decodingMode: 'greedy_search',
      hotwordCount: 0,
    );
  }
}
