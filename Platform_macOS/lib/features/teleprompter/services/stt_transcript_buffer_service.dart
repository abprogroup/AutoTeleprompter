import '../../../core/extensions/string_extensions.dart';

class SttTranscriptBuffer {
  final int transcriptFloor;
  final List<String> spokenWords;
  final List<String> freshWords;
  final String recentTranscript;
  final bool resetFloor;

  const SttTranscriptBuffer({
    required this.transcriptFloor,
    required this.spokenWords,
    required this.freshWords,
    required this.recentTranscript,
    required this.resetFloor,
  });

  bool get hasFreshSpeech => freshWords.isNotEmpty;
}

class SttTranscriptBufferService {
  const SttTranscriptBufferService();

  SttTranscriptBuffer update({
    required String rawTranscript,
    required int transcriptFloor,
    int recentWordWindow = 12,
  }) {
    final spokenWords = rawTranscript
        .split(RegExp(r'\s+'))
        .map((word) => word.trim().normalizeForMatching())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final resetFloor = spokenWords.length < transcriptFloor;
    final safeFloor = resetFloor ? 0 : transcriptFloor;
    final freshWords = safeFloor > 0 && safeFloor <= spokenWords.length
        ? spokenWords.sublist(safeFloor)
        : spokenWords;
    final safeWindow = recentWordWindow.clamp(1, 240).toInt();
    final recentWords = freshWords.length > safeWindow
        ? freshWords.sublist(freshWords.length - safeWindow)
        : freshWords;
    final recentTranscript = recentWords.join(' ');
    return SttTranscriptBuffer(
      transcriptFloor: safeFloor,
      spokenWords: spokenWords,
      freshWords: freshWords,
      recentTranscript: recentTranscript,
      resetFloor: resetFloor,
    );
  }
}
