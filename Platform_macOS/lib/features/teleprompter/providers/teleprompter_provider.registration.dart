part of 'teleprompter_provider.dart';

class _SequentialSttProgress {
  final int? targetIndex;
  final String debugInfo;
  final List<String> evidenceWords;
  final double evidenceScore;

  const _SequentialSttProgress(
    this.targetIndex,
    this.debugInfo, {
    this.evidenceWords = const [],
    this.evidenceScore = 0.0,
  });
}

final teleprompterProvider =
    NotifierProvider<TeleprompterNotifier, TeleprompterState>(
        TeleprompterNotifier.new);
