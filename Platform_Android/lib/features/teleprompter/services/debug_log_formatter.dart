class DebugLogFormatter {
  static String normalize(String log) {
    final cleaned = _stripCorruptPrefix(log);
    return _tagKnownMessage(cleaned);
  }

  static String _stripCorruptPrefix(String value) {
    var current = value.trimLeft();
    for (var attempts = 0; attempts < 4; attempts++) {
      var index = 0;
      while (index < current.length) {
        final code = current.codeUnitAt(index);
        if (code <= 0x7F || current[index] == '[') break;
        index++;
      }
      while (index < current.length && current.codeUnitAt(index) == 0x20) {
        index++;
      }
      if (index <= 0 || index >= current.length) return current;
      final stripped = current.substring(index).trimLeft();
      if (_looksLikeMessage(stripped)) return stripped;
      current = stripped;
    }
    return current;
  }

  static bool _looksLikeMessage(String value) {
    return value.startsWith('[') ||
        value.startsWith('SESSION START') ||
        value.startsWith('LANG:') ||
        value.startsWith('HEARTBEAT') ||
        value.startsWith('SILENT LISTENING') ||
        value.startsWith('FIX:') ||
        value.startsWith('WAIT #') ||
        value.startsWith('STANDBY LOCK') ||
        value.startsWith('ADVANCE') ||
        value.startsWith('IMPROVISING') ||
        value.startsWith('POSITION ') ||
        value.startsWith('Starting Whisper') ||
        value.startsWith('WHISPER ') ||
        value.startsWith('VOICE COMMAND') ||
        value.startsWith('COMMAND:') ||
        value.startsWith('Microphone');
  }

  static String _tagKnownMessage(String value) {
    if (value.startsWith('[')) return value;
    if (value.startsWith('WAIT #')) return '[WAIT] $value';
    if (value.startsWith('STANDBY LOCK') || value.startsWith('IMPROVISING')) {
      return '[STT] $value';
    }
    if (value.startsWith('ADVANCE')) return '[OK] $value';
    if (value.startsWith('SESSION START')) return '[SESSION] $value';
    if (value.startsWith('LANG:')) return '[LANG] $value';
    if (value.startsWith('HEARTBEAT')) return '[HEARTBEAT] $value';
    if (value.startsWith('SILENT LISTENING')) return '[WARN] $value';
    if (value.startsWith('FIX:')) return '[FIX] $value';
    if (value.startsWith('POSITION ')) return '[POS] $value';
    if (value.startsWith('Starting Whisper') || value.startsWith('WHISPER ')) {
      return '[WHISPER] $value';
    }
    if (value.startsWith('VOICE COMMAND') || value.startsWith('COMMAND:')) {
      return '[VOICE] $value';
    }
    if (value.startsWith('Microphone')) return '[MIC] $value';
    final sttStatus = RegExp(
      r'^\[[^\]]+\] (Starting STT|STT FAILED|STT using locale|STATUS|STT ERROR|LANGUAGE UNAVAILABLE|LANG MISSING|ALL STT FAILED)',
    );
    if (sttStatus.hasMatch(value)) return '[STT] $value';
    return value;
  }
}
