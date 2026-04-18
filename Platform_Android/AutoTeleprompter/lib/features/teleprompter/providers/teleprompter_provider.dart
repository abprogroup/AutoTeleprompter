import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alignment_result.dart';
import '../services/speech_service.dart';
import '../services/word_aligner.dart';
import '../../script/models/script.dart';
import '../../settings/providers/settings_provider.dart';

import '../../remote/services/remote_control_service.dart';

class TeleprompterNotifier extends Notifier<TeleprompterState> {
  late final SpeechService _speechService;
  late final RemoteControlService _remoteControlService;
  Script? _currentScript;
  String _accumulatedTranscript = '';
  bool _disposed = false;
  int _noProgressCount = 0;
  Timer? _heartbeatTimer;

  // ── Tuning: how patient we are before force-skipping ───────────────────────
  // At ~3 partial results/sec, 25 means ~8 seconds of no progress before skip.
  // This is generous — gives the user time to improvise without losing position.
  static const int _skipAfterStuck = 25;
  // Max words to advance per STT update — prevents jarring jumps
  static const int _maxAdvancePerUpdate = 3;

  @override
  TeleprompterState build() {
    _disposed = false;
    _speechService = SpeechService();
    _remoteControlService = ref.read(remoteControlProvider);
    _setupRemoteCallbacks();
    _setupSpeechCallbacks();
    ref.onDispose(() {
      _disposed = true;
      _heartbeatTimer?.cancel();
      _speechService.stop();
      _remoteControlService.stop();
    });
    return const TeleprompterState();
  }

  void _setupRemoteCallbacks() {
    _remoteControlService.onCommand.listen((cmd) {
      if (_disposed) return;
      final settings = ref.read(settingsProvider.notifier);
      final sData = ref.read(settingsProvider);
      
      switch (cmd) {
        case 'TOGGLE':
          if (sData.scrollSpeed == 0) {
            settings.setScrollSpeed(100);
          } else {
            settings.setScrollSpeed(0);
          }
          break;
        case 'FASTER':
          settings.setScrollSpeed((sData.scrollSpeed + 25).clamp(-300, 300));
          break;
        case 'SLOWER':
          settings.setScrollSpeed((sData.scrollSpeed - 25).clamp(-300, 300));
          break;
        case 'RESET':
          resetPosition();
          break;
      }
    });

    // Start remote server automatically
    _remoteControlService.start();
  }

  void _safeSetState(TeleprompterState Function(TeleprompterState) updater) {
    if (_disposed) return;
    try {
      state = updater(state);
    } catch (_) {}
  }

  void _addDebugLog(String log) {
    final settings = ref.read(settingsProvider);
    if (!settings.debugMode) return;
    final now = DateTime.now();
    final ts = "${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${(now.millisecond ~/ 100)}";
    final entry = "[$ts] $log";
    final logs = [...state.debugLogs, entry];
    if (logs.length > 80) logs.removeRange(0, logs.length - 80);
    _safeSetState((s) => s.copyWith(debugLogs: logs));
  }

  void _setupSpeechCallbacks() {
    _speechService.onResult = (result) {
      if (_currentScript == null || _disposed) return;

      final words = result.words.toLowerCase();
      final settings = ref.read(settingsProvider);

      // V3 Professional: Voice Commands
      // Only check for commands if they appear in the partial result
      if (words.contains('stop prompt') || words.contains('עצור') || words.contains('עצירה')) {
        _addDebugLog('🗣️ VOICE COMMAND: STOP');
        ref.read(settingsProvider.notifier).setScrollSpeed(0);
        return;
      } else if (words.contains('start prompt') || words.contains('בוא')) {
        _addDebugLog('🗣️ VOICE COMMAND: START');
        if (settings.scrollSpeed == 0) ref.read(settingsProvider.notifier).setScrollSpeed(100);
        return;
      } else if (words.contains('speed up') || words.contains('מהר')) {
        _addDebugLog('🗣️ VOICE COMMAND: FASTER');
        ref.read(settingsProvider.notifier).setScrollSpeed((settings.scrollSpeed + 25).clamp(-300, 300));
        return;
      } else if (words.contains('slow down') || words.contains('לאט')) {
        _addDebugLog('🗣️ VOICE COMMAND: SLOWER');
        ref.read(settingsProvider.notifier).setScrollSpeed((settings.scrollSpeed - 25).clamp(-300, 300));
        return;
      }

      _accumulatedTranscript = result.words;
      final script = _currentScript!;

      final aligned = WordAligner.align(
        script: script.words,
        transcript: _accumulatedTranscript,
        lastConfirmedIndex: state.confirmedWordIndex,
      );

      // Build debug info
      final currentIdx = state.confirmedWordIndex;
      final nextExpected = (currentIdx + 1 < script.words.length)
          ? script.words.skip(currentIdx + 1).where((w) => !w.isNewline).take(3).map((w) => w.raw).join(' ')
          : '<END>';

      if (aligned.confirmedWordIndex > state.confirmedWordIndex) {
        // ── MATCH: advance the position ──────────────────────────────────────
        _noProgressCount = 0;
        final capped = aligned.confirmedWordIndex.clamp(
          state.confirmedWordIndex,
          state.confirmedWordIndex + _maxAdvancePerUpdate,
        );
        final advancedWord = capped < script.words.length ? script.words[capped].raw : '?';
        _addDebugLog('✅ ADVANCE → #$capped "$advancedWord" (conf=${aligned.confidence.toStringAsFixed(2)}) | heard: "${result.words}"');
        if (aligned.debugInfo.isNotEmpty) {
          _addDebugLog('   ${aligned.debugInfo.split('\n').first}');
        }
        _safeSetState((s) => s.copyWith(confirmedWordIndex: capped));
      } else {
        // ── NO MATCH: user is improvising or word wasn't recognized ──────────
        _noProgressCount++;
        _addDebugLog('⏸ WAIT #$_noProgressCount/$_skipAfterStuck | heard: "${result.words}" | next: "$nextExpected" | ${aligned.debugInfo.split('\n').first}');

        if (_noProgressCount >= _skipAfterStuck) {
          _noProgressCount = 0;
          final next = _nextRealWord(state.confirmedWordIndex, script);
          if (next != null) {
            final skippedWord = script.words[next].raw;
            _addDebugLog('⏭ FORCE SKIP → #$next "$skippedWord" (stuck too long)');
            _safeSetState((s) => s.copyWith(confirmedWordIndex: next));
          }
        }
      }

    };

    _speechService.onStatusChange = (status) {
      _addDebugLog('🎤 STATUS: $status');
      _safeSetState((s) => s.copyWith(
        isListening: status == SpeechStatus.listening,
        statusMessage: '',
        hasError: false,
      ));
    };

    _speechService.onError = (error) {
      _addDebugLog('❌ STT ERROR: $error');
      // Routine errors are part of normal STT operation — suppress from UI
      final isRoutine = error.contains('timeout') ||
          error.contains('no_match') ||
          error.contains('Client') ||
          error.contains('busy') ||
          error.contains('speech_timeout') ||
          error.contains('recognizer_busy') ||
          error.contains('Listen failed');
      _safeSetState((s) => s.copyWith(
        statusMessage: isRoutine ? '' : error,
        hasError: !isRoutine,
        // If it's a routine error, the service will instantly restart it, 
        // so don't flash the UI to "Not Listening" state.
        isListening: isRoutine ? s.isListening : false,
      ));
    };
  }

  /// Find the next non-newline word index after [from]
  int? _nextRealWord(int from, Script script) {
    for (int i = from + 1; i < script.words.length; i++) {
      if (!script.words[i].isNewline) return i;
    }
    return null;
  }

  Future<void> startSession(Script script) async {
    _currentScript = script;
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    state = state.copyWith(
        confirmedWordIndex: 0, isListening: false, hasError: false, 
        statusMessage: '', debugLogs: []);

    _addDebugLog('🚀 SESSION START | ${script.words.where((w) => !w.isNewline).length} words');

    // Auto-detect language from script content
    final realWords = script.words.where((w) => !w.isNewline).toList();
    String? localeId;
    if (realWords.isNotEmpty) {
      final hebrewCount = realWords.where((w) => w.isRtl).length;
      final ratio = hebrewCount / realWords.length;
      localeId = ratio > 0.3 ? 'he_IL' : 'en_US';
      _addDebugLog('🌐 LANG: ${ratio > 0.3 ? "Hebrew" : "English"} (${(ratio * 100).round()}% Hebrew chars)');
    }

    // Start heartbeat timer in debug mode to show STT is alive
    _heartbeatTimer?.cancel();
    final settings = ref.read(settingsProvider);
    if (settings.debugMode) {
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_disposed) return;
        final listening = _speechService.isListening;
        final pos = state.confirmedWordIndex;
        final total = script.words.where((w) => !w.isNewline).length;
        _addDebugLog('💓 HEARTBEAT: ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount');
      });
    }

    await _speechService.start(localeId: localeId);
  }

  Future<void> stopSession() async {
    _heartbeatTimer?.cancel();
    await _speechService.stop();
    _addDebugLog('🛑 SESSION STOP');
    if (!_disposed) state = state.copyWith(isListening: false);
  }

  void resetPosition() {
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _addDebugLog('🔄 POSITION RESET → 0');
    state = state.copyWith(confirmedWordIndex: 0);
  }
}

final teleprompterProvider =
    NotifierProvider<TeleprompterNotifier, TeleprompterState>(TeleprompterNotifier.new);
