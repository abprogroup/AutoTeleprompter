/// Sentinel to explicitly clear a nullable field via copyWith
const _clearSentinel = '\x00__CLEAR__';

class TeleprompterState {
  final int confirmedWordIndex;
  final bool isListening;
  final String statusMessage;
  final bool hasError;
  final List<String> debugLogs;
  /// Non-null when the script's language isn't available for Google STT.
  /// The UI should show a dialog prompting the user to download it.
  final String? missingLanguage;

  const TeleprompterState({
    this.confirmedWordIndex = 0,
    this.isListening = false,
    this.statusMessage = '',
    this.hasError = false,
    this.debugLogs = const [],
    this.missingLanguage,
  });

  TeleprompterState copyWith({
    int? confirmedWordIndex,
    bool? isListening,
    String? statusMessage,
    bool? hasError,
    List<String>? debugLogs,
    String? missingLanguage = _clearSentinel,
  }) {
    return TeleprompterState(
      confirmedWordIndex: confirmedWordIndex ?? this.confirmedWordIndex,
      isListening: isListening ?? this.isListening,
      statusMessage: statusMessage ?? this.statusMessage,
      hasError: hasError ?? this.hasError,
      debugLogs: debugLogs ?? this.debugLogs,
      missingLanguage: missingLanguage == _clearSentinel
          ? this.missingLanguage
          : missingLanguage,
    );
  }
}
