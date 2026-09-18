import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:whisper_ggml/whisper_ggml.dart';

export 'package:whisper_ggml/whisper_ggml.dart' show WhisperModel;

enum WhisperModelReadiness { missing, incomplete, invalid, ready }

const int _mib = 1024 * 1024;

extension WhisperModelPathExt on WhisperModel {
  String getPath(String directory) =>
      path.join(directory, whisperModelFileName(this));
}

String whisperModelFileName(WhisperModel model) =>
    'ggml-${model.modelName}.bin';

bool isPlausibleWhisperModelSize(WhisperModel model, int bytes) =>
    bytes >= minimumWhisperModelBytes(model) &&
    bytes <= maximumWhisperModelBytes(model);

int minimumWhisperModelBytes(WhisperModel model) {
  switch (model) {
    case WhisperModel.tiny:
    case WhisperModel.tinyEn:
      return 50 * _mib;
    case WhisperModel.base:
    case WhisperModel.baseEn:
      return 100 * _mib;
    case WhisperModel.small:
    case WhisperModel.smallEn:
    case WhisperModel.smallEnTdrz:
      return 300 * _mib;
    case WhisperModel.medium:
    case WhisperModel.mediumEn:
      return 900 * _mib;
    case WhisperModel.large:
      return 2000 * _mib;
  }
}

int maximumWhisperModelBytes(WhisperModel model) {
  switch (model) {
    case WhisperModel.tiny:
    case WhisperModel.tinyEn:
      return 200 * _mib;
    case WhisperModel.base:
    case WhisperModel.baseEn:
      return 400 * _mib;
    case WhisperModel.small:
    case WhisperModel.smallEn:
    case WhisperModel.smallEnTdrz:
      return 1200 * _mib;
    case WhisperModel.medium:
    case WhisperModel.mediumEn:
      return 3500 * _mib;
    case WhisperModel.large:
      return 7000 * _mib;
  }
}

class WhisperModelFiles {
  WhisperModelFiles(String modelPath)
    : model = File(modelPath),
      partial = File('$modelPath.part'),
      marker = File('$modelPath.complete.json'),
      markerTemporary = File('$modelPath.complete.json.part');

  factory WhisperModelFiles.inDirectory(String directory, WhisperModel model) =>
      WhisperModelFiles(path.join(directory, whisperModelFileName(model)));

  final File model;
  final File partial;
  final File marker;
  final File markerTemporary;
}

WhisperModel whisperModelFromEngine(String engine) {
  switch (engine) {
    case 'whisper_base':
      return WhisperModel.base;
    case 'whisper_small':
      return WhisperModel.small;
    case 'whisper_medium':
      return WhisperModel.medium;
    case 'whisper_tiny':
    default:
      return WhisperModel.tiny;
  }
}

String whisperLanguageForLocale(String? localeId) {
  final normalized = localeId?.trim().toLowerCase() ?? '';
  final language =
      normalized.isEmpty ? '' : normalized.split(RegExp(r'[-_]')).first;
  if (language == 'he' || language == 'iw') return 'he';
  if (language == 'en') return 'en';
  return 'auto';
}

class WhisperModelInfo {
  final String engineKey;
  final String label;
  final String size;
  final String description;
  final WhisperModel model;

  const WhisperModelInfo({
    required this.engineKey,
    required this.label,
    required this.size,
    required this.description,
    required this.model,
  });
}

const whisperModels = [
  WhisperModelInfo(
    engineKey: 'whisper_tiny',
    label: 'Whisper Tiny',
    size: '~75MB',
    description: 'Fastest multilingual model. Recommended for live prompting.',
    model: WhisperModel.tiny,
  ),
  WhisperModelInfo(
    engineKey: 'whisper_base',
    label: 'Whisper Base',
    size: '~142MB',
    description: 'Good balance of speed and accuracy.',
    model: WhisperModel.base,
  ),
  WhisperModelInfo(
    engineKey: 'whisper_small',
    label: 'Whisper Small',
    size: '~466MB',
    description: 'More accurate. Needs a capable PC.',
    model: WhisperModel.small,
  ),
  WhisperModelInfo(
    engineKey: 'whisper_medium',
    label: 'Whisper Medium',
    size: '~1.5GB',
    description: 'Most accurate option. Needs a powerful PC.',
    model: WhisperModel.medium,
  ),
];
