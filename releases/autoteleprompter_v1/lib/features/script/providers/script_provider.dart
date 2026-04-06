import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/script.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/extensions/string_extensions.dart';
import '../../../features/teleprompter/services/word_aligner.dart';

class ScriptNotifier extends Notifier<Script?> {
  @override
  Script? build() {
    // Load last saved script on startup
    final lastText = ref.read(settingsProvider).lastScript;
    if (lastText.isNotEmpty) {
      return _buildScript(lastText);
    }
    return null;
  }

  Script _buildScript(String text) {
    final words = WordAligner.tokenize(text);
    final isRtl = text.isHebrew;
    return Script(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: text.split('\n').first.trim().isNotEmpty
          ? text.split('\n').first.trim().substring(0, text.split('\n').first.trim().length.clamp(0, 40))
          : 'Script',
      rawText: text,
      words: words,
      isRtl: isRtl,
    );
  }

  void loadText(String text) {
    state = _buildScript(text);
    ref.read(settingsProvider.notifier).saveScript(text);
  }

  void clear() {
    state = null;
    ref.read(settingsProvider.notifier).saveScript('');
  }
}

final scriptProvider = NotifierProvider<ScriptNotifier, Script?>(ScriptNotifier.new);
