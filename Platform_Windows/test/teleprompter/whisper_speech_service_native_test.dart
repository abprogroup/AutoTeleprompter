import 'package:autoteleprompter/features/teleprompter/services/whisper_speech_service_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Whisper model selection', () {
    test('uses multilingual Tiny as the default', () {
      expect(whisperModelFromEngine('unknown'), WhisperModel.tiny);
      expect(whisperModelFromEngine(''), WhisperModel.tiny);
      expect(whisperModelFromEngine('whisper_tiny'), WhisperModel.tiny);
      expect(WhisperModel.tiny.modelName, 'tiny');
    });

    test('maps every supported engine explicitly', () {
      expect(whisperModelFromEngine('whisper_base'), WhisperModel.base);
      expect(whisperModelFromEngine('whisper_small'), WhisperModel.small);
      expect(whisperModelFromEngine('whisper_medium'), WhisperModel.medium);
    });

    test('uses whisper_ggml compatible cache filenames', () {
      expect(whisperModelFileName(WhisperModel.tiny), 'ggml-tiny.bin');
      expect(whisperModelFileName(WhisperModel.base), 'ggml-base.bin');
    });
  });

  group('Whisper language selection', () {
    test('maps modern and legacy Hebrew locale identifiers', () {
      expect(whisperLanguageForLocale('he-IL'), 'he');
      expect(whisperLanguageForLocale('he_IL'), 'he');
      expect(whisperLanguageForLocale('iw_IL'), 'he');
    });

    test('maps English locales and auto-detects other input', () {
      expect(whisperLanguageForLocale('en-US'), 'en');
      expect(whisperLanguageForLocale('EN_gb'), 'en');
      expect(whisperLanguageForLocale(null), 'auto');
      expect(whisperLanguageForLocale(''), 'auto');
      expect(whisperLanguageForLocale('fr-FR'), 'auto');
    });
  });
}
