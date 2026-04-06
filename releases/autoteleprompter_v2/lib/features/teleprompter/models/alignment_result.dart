class TeleprompterState {
  final int confirmedWordIndex;
  final bool isListening;
  final String statusMessage;
  final bool hasError;
  final List<String> debugLogs;

  const TeleprompterState({
    this.confirmedWordIndex = 0,
    this.isListening = false,
    this.statusMessage = '',
    this.hasError = false,
    this.debugLogs = const [],
  });

  TeleprompterState copyWith({
    int? confirmedWordIndex,
    bool? isListening,
    String? statusMessage,
    bool? hasError,
    List<String>? debugLogs,
  }) {
    return TeleprompterState(
      confirmedWordIndex: confirmedWordIndex ?? this.confirmedWordIndex,
      isListening: isListening ?? this.isListening,
      statusMessage: statusMessage ?? this.statusMessage,
      hasError: hasError ?? this.hasError,
      debugLogs: debugLogs ?? this.debugLogs,
    );
  }
}
