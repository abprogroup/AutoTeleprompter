import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/teleprompter_provider.dart';
import '../../script/providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../script/models/script.dart';
import '../../../core/widgets/global_color_picker.dart';
import '../../remote/services/remote_control_service.dart';

// Regex to strip any unprocessed markup tags that somehow leaked into word.raw
final _tagStripRe = RegExp(r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg)(?:=[^\]]+)?\]|\*\*');

class TeleprompterScreen extends ConsumerStatefulWidget {
  const TeleprompterScreen({super.key});

  @override
  ConsumerState<TeleprompterScreen> createState() => _TeleprompterScreenState();
}

class _TeleprompterScreenState extends ConsumerState<TeleprompterScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _wordKeys = [];
  bool _controlsVisible = true;
  Timer? _manualScrollTimer;
  Timer? _wordTrackTimer;
  Timer? _hideControlsTimer;
  int _manualWordIndex = 0;
  bool _manualScrolling = false;
  bool _scrollingBackward = false;
  StreamSubscription? _remoteCmdSub;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHideControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(teleprompterProvider.notifier).resetPosition();
        _scrollController.jumpTo(0);
        _initRemoteListener();
      }
    });
  }

  void _initRemoteListener() {
    _remoteCmdSub?.cancel();
    _remoteCmdSub = ref.read(remoteControlProvider).onCommand.listen((cmd) {
      if (!mounted) return;
      final settings = ref.read(settingsProvider);
      
      switch (cmd) {
        case 'TOGGLE':
          if (settings.scrollMode == 'manual') {
             _manualScrolling ? _stopManualScroll() : _startManualScroll();
          } else {
             final tState = ref.read(teleprompterProvider);
             tState.isListening ? ref.read(teleprompterProvider.notifier).stopSession() : _requestAndStart();
          }
          break;
        case 'FASTER':
          ref.read(settingsProvider.notifier).setScrollSpeed((settings.scrollSpeed + 15).clamp(-300.0, 300.0));
          break;
        case 'SLOWER':
          ref.read(settingsProvider.notifier).setScrollSpeed((settings.scrollSpeed - 15).clamp(-300.0, 300.0));
          break;
        case 'RESET':
          if (settings.scrollMode == 'manual') {
            _resetManual();
          } else {
            ref.read(teleprompterProvider.notifier).resetPosition();
            _scrollController.jumpTo(0);
          }
          break;
        case 'MODE_AUTO':
          ref.read(settingsProvider.notifier).setScrollMode('auto');
          break;
        case 'MODE_MANUAL':
          ref.read(settingsProvider.notifier).setScrollMode('manual');
          break;
      }
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _manualScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
    _hideControlsTimer?.cancel();
    _scrollController.dispose();
    _remoteCmdSub?.cancel();
    ref.read(teleprompterProvider.notifier).stopSession();
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  Future<void> _requestAndStart() async {
    final micStatus = await Permission.microphone.request();
    final speechStatus = await Permission.speech.request();

    if (micStatus.isDenied || speechStatus.isDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Microphone Permission Required',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'AutoTeleprompter needs microphone access to follow your speech.\n\nGo to Settings → Privacy → Microphone and enable it.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                  onPressed: () { Navigator.pop(context); openAppSettings(); },
                  child: const Text('Open Settings')),
            ],
          ),
        );
      }
      return;
    }

    final script = ref.read(scriptProvider);
    if (script != null) {
      await ref.read(teleprompterProvider.notifier).startSession(script);
    }
  }

  // ── Smooth pixel-based manual scroll ───────────────────────────────────────

  void _startManualScroll({bool backward = false}) {
    if (!_scrollController.hasClients) return;
    _scrollingBackward = backward;
    setState(() => _manualScrolling = true);
    _manualScrollTimer?.cancel();
    _wordTrackTimer?.cancel();

    // 60fps smooth pixel scroll
    _manualScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_scrollController.hasClients) return;
      final settings = ref.read(settingsProvider);
      
      // Speed can be negative for backward scrolling
      final speed = settings.scrollMode == 'manual' ? settings.scrollSpeed : 100.0;
      if (speed == 0) return;

      // pixels per tick: speed(wpm) × 3px × 16ms/1000ms
      final pxPerTick = speed.abs() * 3.0 * 16.0 / 1000.0;
      final isBackward = speed < 0;
      final delta = isBackward ? -pxPerTick : pxPerTick;
      
      final next = _scrollController.offset + delta;
      final max = _scrollController.position.maxScrollExtent;
      
      if (!isBackward && next >= max) {
        _scrollController.jumpTo(max);
        _stopManualScroll();
        return;
      }
      if (isBackward && next <= 0) {
        _scrollController.jumpTo(0);
        _stopManualScroll();
        return;
      }
      _scrollController.jumpTo(next.clamp(0.0, max));
    });

    // Update highlighted word at 5fps (cheap: only scans nearby keys)
    _wordTrackTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _updateManualWordIndex();
    });
  }

  void _updateManualWordIndex() {
    if (!mounted || !_scrollController.hasClients) return;
    final settings = ref.read(settingsProvider);
    final targetScreenY = MediaQuery.of(context).size.height * settings.scrollLead;

    int bestIndex = _manualWordIndex;
    double bestDist = double.infinity;

    final start = (_manualWordIndex - 3).clamp(0, _wordKeys.length - 1);
    final end = (_manualWordIndex + 15).clamp(0, _wordKeys.length - 1);

    for (int i = start; i <= end; i++) {
      final ctx = _wordKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final posY = box.localToGlobal(Offset.zero).dy;
      final dist = (posY - targetScreenY).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
      }
    }

    if (bestIndex != _manualWordIndex) {
      setState(() => _manualWordIndex = bestIndex);
    }
  }

  void _stopManualScroll() {
    _manualScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
    _scrollingBackward = false;
    if (mounted) setState(() => _manualScrolling = false);
  }

  void _resetManual() {
    _stopManualScroll();
    _manualWordIndex = 0;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  // ── Speech-mode scroll ──────────────────────────────────────────────────────

  void _scrollToWordIndex(int index) {
    if (index < 0 || index >= _wordKeys.length) return;
    final key = _wordKeys[index];
    final ctx = key.currentContext;
    if (ctx == null) return;

    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;

    final settings = ref.read(settingsProvider);
    final screenH = MediaQuery.of(context).size.height;
    final targetY = screenH * settings.scrollLead;

    final wordPos = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
    final scrollOffset = _scrollController.offset + wordPos.dy - targetY;

    _scrollController.animateTo(
      scrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _showSettings() {
    _showControls();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => const TeleprompterSettingsPanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final script = ref.watch(scriptProvider);
    final tState = ref.watch(teleprompterProvider);
    final settings = ref.watch(settingsProvider);
    if (script != null) {
      while (_wordKeys.length < script.words.length) {
        _wordKeys.add(GlobalKey());
      }
    }

    // Auto-scroll on speech recognition
    ref.listen(teleprompterProvider.select((s) => s.confirmedWordIndex), (prev, next) {
      if (settings.scrollMode == 'auto' && next > 0) {
        _scrollToWordIndex(next);
      }
    });

    if (script == null || script.isEmpty) {
      return Scaffold(
        backgroundColor: Color(settings.scriptBgColor),
        body: const Center(child: Text('No script loaded.', style: TextStyle(color: Colors.white))),
      );
    }

    final paragraphs = <List<ScriptWord>>[];
    List<ScriptWord> currentParagraph = [];
    for (final word in script.words) {
      if (word.isNewline) {
        if (currentParagraph.isNotEmpty) {
          paragraphs.add(currentParagraph);
          currentParagraph = [];
        }
        paragraphs.add([word]);
      } else {
        currentParagraph.add(word);
      }
    }
    if (currentParagraph.isNotEmpty) paragraphs.add(currentParagraph);

    Widget wordList = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.05,
        vertical: MediaQuery.of(context).size.height * 0.45,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: paragraphs.map<Widget>((para) {
          if (para.length == 1 && para[0].isNewline) {
            return SizedBox(
              key: _wordKeys[para[0].index],
              height: settings.fontSize * 1.5 + (settings.lineSpacing * 4), // Full line height
            );
          }

          final firstWord = para.first;
          final paraDir = firstWord.effectiveRtl ? TextDirection.rtl : TextDirection.ltr;
          // v4.0: Look for alignment tag in any word of the paragraph to handle leading spaces/tags
          TextAlign? paraAlign;
          try {
            paraAlign = para.firstWhere((w) => w.alignment != null).alignment;
          } catch (_) {
            paraAlign = firstWord.alignment;
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: settings.lineSpacing * 60, // Doubled from 25 to 60 for absolute paragraph distinction
            ),
            child: Directionality(
                textDirection: paraDir,
                child: Wrap(
                  textDirection: paraDir,
                  alignment: _toWrapAlignment(paraAlign, settings, firstWord.effectiveRtl),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: para.map<Widget>((wordObj) {
                    final ScriptWord word = wordObj as ScriptWord;
                    final i = word.index;
                    final isCurrent = i == tState.confirmedWordIndex;
                    final isPast = i < tState.confirmedWordIndex;
                    final displayText = word.raw.replaceAll(_tagStripRe, '');

                    Color wordColor;
                    if (isCurrent) {
                      wordColor = Color(settings.currentWordColor);
                    } else if (isPast) {
                      wordColor = (word.textColor ?? Color(settings.futureWordColor)).withOpacity(settings.pastWordOpacity);
                    } else {
                      wordColor = word.textColor ?? Color(settings.futureWordColor);
                    }

                    Color? bgColor;
                    if (word.highlight != null) {
                      bgColor = isCurrent ? null : (isPast ? word.highlight!.withOpacity(0.15) : word.highlight);
                    }

                    final effectiveFontSize = word.fontSize != null
                        ? settings.fontSize * (word.fontSize! / 17.0)
                        : settings.fontSize;

                    // Handle custom color tags in word.raw
                    Color? customTextColor;
                    Color? customBgColor;
                    
                    final colorMatch = RegExp(r'\[color=([^\]]+)\]').firstMatch(word.raw);
                    if (colorMatch != null) {
                      final hex = colorMatch.group(1)!.trim().replaceFirst('#', '');
                      final colorValue = int.tryParse('FF$hex', radix: 16) ?? settings.futureWordColor;
                      customTextColor = Color(colorValue);
                      debugPrint('[V3_PROMPTER_PARSE] hex=$hex -> color=$customTextColor');
                    }
                    
                    final bgMatch = RegExp(r'\[bg=([^\]]+)\]').firstMatch(word.raw);
                    if (bgMatch != null) {
                      final hex = bgMatch.group(1)!.trim().replaceFirst('#', '');
                      customBgColor = Color(int.tryParse('FF$hex', radix: 16) ?? 0x00000000);
                    }

                    return Directionality(
                      textDirection: word.effectiveRtl ? TextDirection.rtl : TextDirection.ltr,
                      child: Container(
                        key: _wordKeys[i],
                        padding: EdgeInsets.only(right: settings.wordSpacing),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 120),
                          style: TextStyle(
                            fontSize: effectiveFontSize,
                            fontWeight: word.isBold ? FontWeight.bold : FontWeight.w500,
                            fontStyle: word.isItalic ? FontStyle.italic : FontStyle.normal,
                            letterSpacing: settings.letterSpacing,
                            color: isCurrent ? (customTextColor ?? Color(settings.currentWordColor)) : 
                                   (isPast ? (customTextColor ?? word.textColor ?? Color(settings.futureWordColor)).withOpacity(settings.pastWordOpacity) : 
                                   (customTextColor ?? word.textColor ?? Color(settings.futureWordColor))),
                            backgroundColor: isCurrent ? null : (isPast ? (customBgColor ?? word.highlight)?.withOpacity(0.15) : (customBgColor ?? word.highlight)),
                            height: 1.3,
                            decoration: word.isUnderline ? TextDecoration.underline : null,
                            decorationColor: isCurrent ? Color(settings.currentWordColor) : (customTextColor ?? word.textColor ?? Color(settings.futureWordColor)),
                          ),
                          child: Text(displayText),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ),
          ).animate(key: ValueKey('para_${para.first.index}'))
           .fadeIn(duration: 300.ms);
        }).toList(),
      ),
    );

    if (settings.mirrorHorizontal || settings.mirrorVertical) {
      wordList = Transform.scale(
        scaleX: settings.mirrorHorizontal ? -1 : 1,
        scaleY: settings.mirrorVertical ? -1 : 1,
        child: wordList,
      );
    }
    if (settings.flipRotation != 0) {
      wordList = RotatedBox(
        quarterTurns: settings.flipRotation ~/ 90,
        child: wordList,
      );
    }

    return Scaffold(
      backgroundColor: Color(settings.scriptBgColor),
      body: GestureDetector(
        onTap: _showControls,
        child: Stack(
          children: [
            // Scrollable script
            SingleChildScrollView(
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              child: wordList,
            ),
            // Technical Debug Overlay
            if (settings.debugMode)
              Positioned(
                bottom: 10,
                left: 6,
                right: 6,
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header bar with current status
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A1A00),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              tState.isListening ? Icons.mic : Icons.mic_off,
                              color: tState.isListening ? Colors.greenAccent : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              tState.isListening ? 'LISTENING' : 'IDLE',
                              style: TextStyle(
                                color: tState.isListening ? Colors.greenAccent : Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'POS: ${tState.confirmedWordIndex}/${script?.words.where((w) => !w.isNewline).length ?? 0}',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              '🔧 DEV',
                              style: TextStyle(color: Colors.orange, fontSize: 10),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.orange, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                final text = tState.debugLogs.reversed.join('\n');
                                Clipboard.setData(ClipboardData(text: text));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Debug logs copied to clipboard', style: TextStyle(color: Colors.black)), backgroundColor: Colors.orange, duration: Duration(seconds: 2)),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      // Log list
                      Expanded(
                        child: ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          itemCount: tState.debugLogs.length,
                          itemBuilder: (context, idx) {
                            final log = tState.debugLogs[tState.debugLogs.length - 1 - idx];
                            Color logColor = Colors.greenAccent;
                            if (log.contains('⏸') || log.contains('WAIT')) {
                              logColor = Colors.yellow.shade200;
                            } else if (log.contains('❌') || log.contains('SKIP') || log.contains('⏭')) {
                              logColor = Colors.redAccent.shade100;
                            } else if (log.contains('🎤') || log.contains('STATUS')) {
                              logColor = Colors.cyan.shade200;
                            } else if (log.contains('💓') || log.contains('HEARTBEAT')) {
                              logColor = Colors.purple.shade200;
                            } else if (log.contains('🚀') || log.contains('🌐')) {
                              logColor = Colors.blue.shade200;
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 1),
                              child: Text(
                                log,
                                style: TextStyle(
                                  color: logColor,
                                  fontSize: 9.5,
                                  fontFamily: 'monospace',
                                  height: 1.3,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
 
            // Reading line
            Positioned(
              top: MediaQuery.of(context).size.height * settings.scrollLead - 2,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                color: Color(settings.currentWordColor).withOpacity(0.35),
              ),
            ),

            // Error banner
            if (tState.hasError && tState.statusMessage.isNotEmpty)
              Positioned(
                top: 60, left: 20, right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(tState.statusMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ),

            // Controls overlay — control bar + speed slider stacked at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Speed slider — sits just above the control bar, always visible in manual mode
                      if (settings.scrollMode == 'manual')
                        Container(
                          color: Colors.black.withOpacity(0.75),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.speed, color: Colors.white54, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Slider(
                                  value: settings.scrollSpeed,
                                  min: -300,
                                  max: 300,
                                  divisions: 120, // 5wpm steps
                                  activeColor: Color(settings.currentWordColor),
                                  inactiveColor: Colors.white24,
                                  onChanged: (v) {
                                    ref.read(settingsProvider.notifier).setScrollSpeed(v);
                                    if (_manualScrolling && v != 0) {
                                      // If already scrolling, update will happen in next tick of timer
                                      // No need to restart timer if we handle speed dynamically
                                    } else if (v != 0 && !_manualScrolling) {
                                      _startManualScroll();
                                    } else if (v == 0) {
                                      _stopManualScroll();
                                    }
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 62,
                                child: Text('${settings.scrollSpeed.round() > 0 ? "+" : ""}${settings.scrollSpeed.round()} wpm',
                                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              ),
                            ],
                          ),
                        ),

                      // Control bar
                      _ControlBar(
                        isListening: tState.isListening,
                        isManualMode: settings.scrollMode == 'manual',
                        isManualScrolling: _manualScrolling,
                        isScrollingBackward: _scrollingBackward,
                        accentColor: Color(settings.currentWordColor),
                        onStart: settings.scrollMode == 'manual' ? _startManualScroll : _requestAndStart,
                        onStartBackward: () => _startManualScroll(backward: true),
                        onStop: settings.scrollMode == 'manual'
                            ? _stopManualScroll
                            : () => ref.read(teleprompterProvider.notifier).stopSession(),
                        onReset: () {
                          if (settings.scrollMode == 'manual') {
                            _resetManual();
                          } else {
                            ref.read(teleprompterProvider.notifier).resetPosition();
                            _scrollController.animateTo(0,
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutCubic);
                          }
                        },
                        onBack: () => Navigator.of(context).pop(),
                        onSettings: _showSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextAlign _toTextAlign(TextAlign? paraAlign, AppSettings settings, bool isRtl) {
    if (paraAlign != null) return paraAlign;
    // v3.8: Source of Truth - If no tag, Hebrew defaults to Right, English to Left
    return isRtl ? TextAlign.right : TextAlign.left;
  }

  Alignment _toAlignment(TextAlign? paraAlign, AppSettings settings, bool isRtl) {
    final textAlign = _toTextAlign(paraAlign, settings, isRtl);
    if (textAlign == TextAlign.center) return Alignment.center;
    
    if (textAlign == TextAlign.right) return Alignment.centerRight;
    if (textAlign == TextAlign.left) return Alignment.centerLeft;
    
    // Default fallback
    return Alignment.center;
  }

  WrapAlignment _toWrapAlignment(TextAlign? paraAlign, AppSettings settings, bool isRtl) {
    final textAlign = _toTextAlign(paraAlign, settings, isRtl);
    if (textAlign == TextAlign.center) return WrapAlignment.center;

    if (isRtl) {
      // In RTL, Start is Right, End is Left.
      if (textAlign == TextAlign.left) return WrapAlignment.end;
      if (textAlign == TextAlign.right) return WrapAlignment.start;
    } else {
      // In LTR, Start is Left, End is Right.
      if (textAlign == TextAlign.left) return WrapAlignment.start;
      if (textAlign == TextAlign.right) return WrapAlignment.end;
    }

    return WrapAlignment.center;
  }

  WrapAlignment _parseWrapAlignment(String align, bool isRtl) {
    if (isRtl) {
      switch (align) {
        case 'right': return WrapAlignment.start;
        case 'left':  return WrapAlignment.end;
        default: return WrapAlignment.center;
      }
    }
    switch (align) {
      case 'left':  return WrapAlignment.start;
      case 'right': return WrapAlignment.end;
      default: return WrapAlignment.center;
    }
  }
}

// ── Control bar ────────────────────────────────────────────────────────────────

class _ControlBar extends ConsumerWidget {
  final bool isListening;
  final bool isManualMode;
  final bool isManualScrolling;
  final bool isScrollingBackward;
  final Color accentColor;
  final VoidCallback onStart;
  final VoidCallback onStartBackward;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  const _ControlBar({
    required this.isListening,
    required this.isManualMode,
    required this.isManualScrolling,
    required this.isScrollingBackward,
    required this.accentColor,
    required this.onStart,
    required this.onStartBackward,
    required this.onStop,
    required this.onReset,
    required this.onBack,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Forward scroll is active when scrolling but NOT backward
    final isActive = isManualMode
        ? (isManualScrolling && settings.scrollSpeed != 0)
        : isListening;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.95), Colors.transparent],
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              onPressed: onBack,
            ),
            IconButton(
              icon: const Text('A', style: TextStyle(color: Colors.white70, fontSize: 16)),
              onPressed: () {
                final newSize = (settings.fontSize - 4).clamp(20.0, 80.0);
                ref.read(settingsProvider.notifier).setFontSize(newSize);
              },
            ),
            // Backward button removed in favor of bidirectional slider
            GestureDetector(
              onTap: isActive ? onStop : onStart,
              child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? Colors.red : accentColor,
                ),
                child: Icon(
                  isManualMode
                      ? (isManualScrolling && settings.scrollSpeed != 0 ? Icons.pause : Icons.play_arrow)
                      : (isListening ? Icons.stop : Icons.mic),
                  color: isActive ? Colors.white : Colors.black,
                  size: 30,
                ),
              ),
            ),
            IconButton(
              icon: const Text('A', style: TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.bold)),
              onPressed: () {
                final newSize = (settings.fontSize + 4).clamp(20.0, 80.0);
                ref.read(settingsProvider.notifier).setFontSize(newSize);
              },
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white70),
              onPressed: onSettings,
            ),
            IconButton(
              icon: const Icon(Icons.replay, color: Colors.white70),
              onPressed: onReset,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Settings panel ─────────────────────────────────────────────────────────────

class TeleprompterSettingsPanel extends ConsumerWidget {
  const TeleprompterSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    const labelStyle = TextStyle(color: Colors.white70, fontSize: 14);
    const sectionStyle = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.80,
      maxChildSize: 0.97,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // ── Scroll mode ─────────────────────────────────────────────────────
          const Text('Scroll Mode', style: sectionStyle),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Speech Auto'), icon: Icon(Icons.mic)),
              ButtonSegment(value: 'manual', label: Text('Manual Speed'), icon: Icon(Icons.speed)),
            ],
            selected: {settings.scrollMode},
            onSelectionChanged: (val) => notifier.setScrollMode(val.first),
            style: _segmentStyle(settings),
          ),
          const SizedBox(height: 16),

          if (settings.scrollMode == 'manual') ...[
            Row(children: [
              const Text('Manual Scroll Speed', style: labelStyle),
              const Spacer(),
              Text('${settings.scrollSpeed.round() > 0 ? "+" : ""}${settings.scrollSpeed.round()} wpm',
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ]),
            Slider(
              value: settings.scrollSpeed, min: -300, max: 300, divisions: 120,
              activeColor: Color(settings.currentWordColor), inactiveColor: Colors.white24,
              onChanged: (v) => notifier.setScrollSpeed(v),
            ),
            const SizedBox(height: 8),
          ],

          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // ── Text ───────────────────────────────────────────────────────────
          const Text('Text Alignment', style: sectionStyle),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'left', icon: Icon(Icons.format_align_left)),
              ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center)),
              ButtonSegment(value: 'right', icon: Icon(Icons.format_align_right)),
            ],
            selected: {settings.textAlign},
            onSelectionChanged: (val) => notifier.setTextAlign(val.first),
            style: _segmentStyle(settings),
          ),
          const SizedBox(height: 16),

          const Text('Layout & Typography', style: sectionStyle),
          const SizedBox(height: 14),

          // V3 Professional: Broadcast Profiles
          const Text('Broadcast Profile', style: labelStyle),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PresetBtn(label: 'Classic', icon: Icons.document_scanner, onTap: () => notifier.applyPreset('Classic')),
                const SizedBox(width: 8),
                _PresetBtn(label: 'High-Contrast', icon: Icons.visibility, onTap: () => notifier.applyPreset('High Contrast')),
                const SizedBox(width: 8),
                _PresetBtn(label: 'Modern Soft', icon: Icons.auto_awesome_mosaic, onTap: () => notifier.applyPreset('Modern Soft')),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Row(children: [
            const Text('Font Size', style: labelStyle),
            const Spacer(),
            Text('${settings.fontSize.round()}px',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.fontSize, min: 20, max: 80, divisions: 30,
            activeColor: Color(settings.currentWordColor), inactiveColor: Colors.white24,
            onChanged: (v) => notifier.setFontSize(v),
          ),

          Row(children: [
            const Text('Line Spacing', style: labelStyle),
            const Spacer(),
            Text(settings.lineSpacing.toStringAsFixed(1),
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.lineSpacing, min: 1.0, max: 3.0, divisions: 20,
            activeColor: Color(settings.currentWordColor), inactiveColor: Colors.white24,
            onChanged: (v) => notifier.setLineSpacing(v),
          ),

          Row(children: [
            const Text('Word Spacing', style: labelStyle),
            const Spacer(),
            Text('${settings.wordSpacing.toStringAsFixed(1)}px',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.wordSpacing, min: 0.0, max: 20.0, divisions: 20,
            activeColor: Color(settings.currentWordColor), inactiveColor: Colors.white24,
            onChanged: (v) => notifier.setWordSpacing(v),
          ),

          Row(children: [
            const Text('Letter Spacing', style: labelStyle),
            const Spacer(),
            Text('${settings.letterSpacing.toStringAsFixed(1)}px',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.letterSpacing, min: -1.0, max: 5.0, divisions: 24,
            activeColor: Color(settings.currentWordColor), inactiveColor: Colors.white24,
            onChanged: (v) => notifier.setLetterSpacing(v),
          ),

          Row(children: [
            const Text('Reading Line Position', style: labelStyle),
            const Spacer(),
            Text('${(settings.scrollLead * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.scrollLead, min: 0.15, max: 0.60, divisions: 18,
            activeColor: Color(settings.currentWordColor), inactiveColor: Colors.white24,
            onChanged: (v) => notifier.setScrollLead(v),
          ),

          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // ── Colors ─────────────────────────────────────────────────────────
          const Text('Colors', style: sectionStyle),
          const SizedBox(height: 14),

          const Text('Script Background', style: labelStyle),
          const SizedBox(height: 8),
          _ColorGrid(
            selected: settings.scriptBgColor,
            onSelected: notifier.setScriptBgColor,
          ),
          const SizedBox(height: 16),

          const Text('Current Word (reading highlight)', style: labelStyle),
          const SizedBox(height: 8),
          _ColorGrid(
            selected: settings.currentWordColor,
            onSelected: notifier.setCurrentWordColor,
          ),
          const SizedBox(height: 16),

          const Text('Upcoming Text Color', style: labelStyle),
          const SizedBox(height: 8),
          _ColorGrid(
            selected: settings.futureWordColor,
            onSelected: notifier.setFutureWordColor,
          ),
          const SizedBox(height: 16),

          Row(children: [
            const Text('Past Words Opacity', style: labelStyle),
            const Spacer(),
            Text('${(settings.pastWordOpacity * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.pastWordOpacity, min: 0.05, max: 0.7, divisions: 13,
            activeColor: Color(settings.currentWordColor), inactiveColor: Colors.white24,
            onChanged: (v) => notifier.setPastWordOpacity(v),
          ),

          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // ── Display ────────────────────────────────────────────────────────
          Row(
            children: [
              const Text('Mirror Horizontal', style: sectionStyle),
              const Spacer(),
              Switch(
                value: settings.mirrorHorizontal,
                activeColor: Color(settings.currentWordColor),
                onChanged: (v) => notifier.setMirrorHorizontal(v),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Mirror Vertical (Flip)', style: sectionStyle),
              const Spacer(),
              Switch(
                value: settings.mirrorVertical,
                activeColor: Color(settings.currentWordColor),
                onChanged: (v) => notifier.setMirrorVertical(v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Screen Rotation', style: sectionStyle),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('None')),
              ButtonSegment(value: 90, label: Text('90°')),
              ButtonSegment(value: 180, label: Text('180°')),
              ButtonSegment(value: 270, label: Text('270°')),
            ],
            selected: {settings.flipRotation},
            onSelectionChanged: (val) => notifier.setFlipRotation(val.first),
            style: _segmentStyle(settings),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  ButtonStyle _segmentStyle(AppSettings settings) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Color(settings.currentWordColor);
        return const Color(0xFF2A2A2A);
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.black;
        return Colors.white70;
      }),
    );
  }
}

class _PresetBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PresetBtn({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFFFBF00), size: 18),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ── Full color palette grid ────────────────────────────────────────────────────

class _ColorGrid extends StatelessWidget {
  final int selected;
  final void Function(int) onSelected;

  const _ColorGrid({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return GlobalColorButton(
      color: selected,
      onColorChanged: onSelected,
      title: 'Select Color',
    );
  }
}

