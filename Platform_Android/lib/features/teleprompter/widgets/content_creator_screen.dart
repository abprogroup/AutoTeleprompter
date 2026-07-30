import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../providers/teleprompter_provider.dart';
import '../services/mobile_audio_recorder_service.dart';
import '../services/recording_export_service.dart';
import '../services/recording_media_probe_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../script/providers/script_provider.dart';
import '../../script/providers/pending_editor_cursor_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../script/models/script.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../../core/widgets/stable_walkthrough_overlay.dart';
import 'teleprompter_screen.dart';

part 'content_creator_screen.session.dart';
part 'content_creator_screen.recording.dart';
part 'content_creator_screen.feed.dart';
part 'content_creator_screen.controls.dart';
part 'content_creator_screen.search.dart';
part 'content_creator_screen.settings.dart';
part 'content_creator_screen.walkthrough.dart';

class ContentCreatorScreen extends ConsumerStatefulWidget {
  final bool audioOnlyEntry;

  const ContentCreatorScreen({super.key, this.audioOnlyEntry = false});

  @override
  ConsumerState<ContentCreatorScreen> createState() =>
      _ContentCreatorScreenState();
}

class _ContentCreatorScreenState extends ConsumerState<ContentCreatorScreen> {
  CameraController? _cameraController;
  final MobileAudioRecorderService _audioRecorder =
      MobileAudioRecorderService();
  final ScrollController _scrollController = ScrollController();
  // Upper (draggable) overflow control row — horizontally scrollable.
  final ScrollController _overflowBarController = ScrollController();
  final List<GlobalKey> _wordKeys = [];
  List<CameraDescription> _availableCameras = const [];
  // -1 until the first init resolves it to the front camera (selfie teleprompter
  // default); user/camera-flip then sets an explicit index.
  int _selectedCameraIndex = -1;

  // Bookmarks (Pro) — scoped to the active script, same model as present mode.
  String? _bookmarkScopeKey;
  String? _bookmarkLoadingKey;
  bool _bookmarksLoaded = false;
  List<ScriptBookmark> _bookmarks = const [];

  // In-script search while presenting/recording.
  String _lastSearchQuery = '';
  bool _searchWholeWord = false;
  bool _searchDialogOpen = false;
  bool _creatorSearchToolbarVisible = false;
  List<_CreatorSearchMatch> _creatorSearchMatches = const [];
  int _creatorSearchMatchIndex = -1;

  // Controls auto-hide while a session (recording/STT) is active; a tap on the
  // screen reveals them again.
  bool _controlsVisible = true;
  Timer? _controlsHideTimer;

  // Smooth auto-scroll that follows the spoken word to the reading line —
  // ported from present mode so the creator actually advances the script.
  bool _smoothScrollActive = false;
  Timer? _smoothScrollTimer;
  double _scrollTarget = 0;
  int _lastFollowedWordIndex = -1;

  // Draggable self-view bubble position (null until the user drags it).
  Offset? _bubbleOffset;
  int _cameraInitGeneration = 0;
  bool _isInit = false;
  bool _isCameraInitializing = false;
  bool _isRecording = false;
  bool _isAudioOnlyRecording = false;
  bool _recordStartInFlight = false;
  bool _recordingStartedSpeechSession = false;
  String? _cameraError;
  int _countdown = 0;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  bool _resumeDialogShown = false;
  bool _creatorWalkthroughVisible = false;
  int _creatorWalkthroughStep = 0;
  final GlobalKey _creatorSurfaceKey = GlobalKey();
  final GlobalKey _creatorRecordKey = GlobalKey();
  final GlobalKey _creatorSpeechKey = GlobalKey();
  final GlobalKey _creatorSettingsKey = GlobalKey();

  bool _contentAudioOnlyMode(AppSettings settings) {
    return widget.audioOnlyEntry ||
        settings.contentCreatorRecordingFormat ==
            AppSettings.contentCreatorRecordingFormatAudio;
  }

  @override
  void initState() {
    super.initState();
    if (_contentAudioOnlyMode(ref.read(settingsProvider))) {
      _isInit = true;
    } else {
      _initializeCamera();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final script = ref.read(scriptProvider);
      if (script != null) _maybeShowContentResumePrompt(script);
      _scheduleCreatorWalkthroughIfNeeded();
    });
  }

  Future<void> _initializeCamera() async {
    final initGeneration = ++_cameraInitGeneration;
    if (!mounted) return;
    setState(() {
      _isCameraInitializing = true;
      _cameraError = null;
    });
    CameraController? nextController;
    try {
      final cameras = await availableCameras();
      if (!mounted || initGeneration != _cameraInitGeneration) return;
      _availableCameras = cameras;
      if (cameras.isEmpty) {
        setState(() {
          _isInit = false;
          _isCameraInitializing = false;
          _cameraError = 'No camera is available on this device.';
        });
        return;
      }

      if (_selectedCameraIndex < 0 || _selectedCameraIndex >= cameras.length) {
        final frontIndex = cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
        _selectedCameraIndex = frontIndex >= 0 ? frontIndex : 0;
      }

      final settings = ref.read(settingsProvider);
      ResolutionPreset preset = ResolutionPreset.medium; // 720p
      if (settings.videoResolution.contains('1080')) {
        preset = ResolutionPreset.high;
      } else if (settings.videoResolution.contains('480')) {
        preset = ResolutionPreset.low;
      }

      final previousController = _cameraController;
      nextController = CameraController(
        cameras[_selectedCameraIndex],
        preset,
        enableAudio: true,
      );
      _cameraController = nextController;
      await previousController?.dispose();
      await nextController.initialize();
      if (!mounted) return;
      if (initGeneration != _cameraInitGeneration) {
        if (identical(_cameraController, nextController)) {
          _cameraController = null;
        }
        await nextController.dispose();
        return;
      }
      setState(() {
        _isInit = true;
        _isCameraInitializing = false;
        _cameraError = null;
      });
    } catch (e) {
      if (identical(_cameraController, nextController)) {
        _cameraController = null;
      }
      if (nextController != null) {
        await nextController.dispose();
      }
      if (kDebugMode) debugPrint('Camera error: $e');
      if (mounted && initGeneration == _cameraInitGeneration) {
        setState(() {
          _isInit = false;
          _isCameraInitializing = false;
          _cameraError = 'Camera could not start. Check app permissions.';
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraInitGeneration++;
    unawaited(_stopContentSpeechSessionIfOwnedByRecording());
    unawaited(_audioRecorder.cancel());
    unawaited(_audioRecorder.dispose());
    _recordTimer?.cancel();
    _controlsHideTimer?.cancel();
    _smoothScrollTimer?.cancel();
    _cameraController?.dispose();
    _scrollController.dispose();
    _overflowBarController.dispose();
    super.dispose();
  }

  void _setContentCreatorState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final script = ref.watch(scriptProvider);
    final settings = ref.watch(settingsProvider);
    final tState = ref.watch(teleprompterProvider);
    final audioOnly = _contentAudioOnlyMode(settings);

    // Follow the spoken word: when the engine advances, smooth-scroll the
    // script so the current word sits on the reading line (present-mode parity).
    ref.listen(teleprompterProvider.select((s) => s.confirmedWordIndex),
        (prev, next) {
      if (next == _lastFollowedWordIndex) return;
      _lastFollowedWordIndex = next;
      _scrollToWordIndex(next);
    });

    if (script != null) {
      while (_wordKeys.length < script.words.length) {
        _wordKeys.add(GlobalKey());
      }
    }

    final feedMode = settings.contentCreatorFeedMode;
    final sessionActive = _isRecording ||
        _recordStartInFlight ||
        tState.isListening ||
        tState.isStarting;
    final controlsVisible = _controlsVisible || !sessionActive;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleCreatorTap,
        child: Stack(
          children: [
            // Camera feed behind the prompter (strip / full background). Bubble
            // and audio-only are handled separately below.
            if (!audioOnly && feedMode != AppSettings.contentCreatorFeedBubble)
              _buildCreatorCameraLayer(settings, feedMode),

            // Prompter text.
            _buildCreatorPrompterLayer(
                script, settings, tState, audioOnly, feedMode),

            // Read-fade gradient over already-read text (skip over a live full
            // camera so the video stays visible).
            if (settings.readFadeIntensity > 0 &&
                !(feedMode == AppSettings.contentCreatorFeedFull && !audioOnly))
              _buildCreatorReadFade(settings),

            // Reading line — the word the reader should be on.
            _buildCreatorReadingLine(settings),

            // Floating, draggable self-view bubble (drawn above the prompter).
            if (!audioOnly && feedMode == AppSettings.contentCreatorFeedBubble)
              _buildCreatorBubble(settings),

            // Recording timer + countdown overlays (independent of feed mode).
            if (_isRecording)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 20,
                child: _buildRecordTimerChip(),
              ),
            if (_countdown > 0) Center(child: _buildCountdownBadge()),

            // Controls: draggable overflow row (upper) + record button + fixed
            // most-needed row (lower). Auto-hides while a session is running.
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 240),
                child: IgnorePointer(
                  ignoring: !controlsVisible,
                  child: _buildCreatorControls(settings, tState, audioOnly),
                ),
              ),
            ),
            if (_creatorWalkthroughVisible) _buildCreatorWalkthroughOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildPrompterContent(
      Script? script, AppSettings settings, dynamic tState,
      {bool transparentBg = false}) {
    if (script == null || script.isEmpty) {
      return const Center(
          child:
              Text('No script loaded.', style: TextStyle(color: Colors.white)));
    }
    // Present mode enlarges the editor font for readability; match it here so
    // the creator prompter reads like present mode, not the small editor.
    final basePrompterFontSize = settings.fontSize * 2.0;
    // Over a live camera (full-background feed) drop the page colour and add a
    // shadow so the words stay legible against the video.
    final shadows = transparentBg
        ? const [
            Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 1)),
            Shadow(color: Colors.black87, blurRadius: 12),
          ]
        : null;

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

    return Container(
      color: transparentBg ? Colors.transparent : Color(settings.scriptBgColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: paragraphs.map<Widget>((para) {
          if (para.length == 1 && para[0].isNewline) {
            return SizedBox(
              key: para[0].index < _wordKeys.length
                  ? _wordKeys[para[0].index]
                  : null,
              height: basePrompterFontSize * 0.75 + (settings.lineSpacing * 4),
            );
          }

          final firstWord = para.first;
          final paraDir =
              firstWord.effectiveRtl ? TextDirection.rtl : TextDirection.ltr;
          final paraAlign = firstWord.alignment;

          return Padding(
            padding:
                EdgeInsetsDirectional.only(bottom: settings.lineSpacing * 6),
            child: Align(
              alignment: _toAlignment(paraAlign, settings),
              child: Directionality(
                textDirection: paraDir,
                child: Wrap(
                  textDirection: paraDir,
                  alignment: _toWrapAlignment(paraAlign, settings),
                  children: para.map<Widget>((word) {
                    final i = word.index;
                    final isCurrent = i == tState.confirmedWordIndex;
                    final isPast = i < tState.confirmedWordIndex;
                    final displayText = word.raw.replaceAll(
                        RegExp(
                            r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg)(?:=[^\]]+)?\]|\*\*'),
                        '');

                    Color wordColor;
                    final futureColor =
                        word.textColor ?? Color(settings.futureWordColor);
                    if (isCurrent) {
                      wordColor = Color(settings.currentWordColor);
                    } else if (isPast) {
                      wordColor = futureColor.withValues(
                          alpha: settings.pastWordOpacity);
                    } else {
                      wordColor = futureColor;
                    }

                    final effectiveFontSize = word.fontSize != null
                        ? basePrompterFontSize * (word.fontSize! / 17.0)
                        : basePrompterFontSize;

                    return Directionality(
                      textDirection: word.effectiveRtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: Container(
                        key: i < _wordKeys.length ? _wordKeys[i] : null,
                        padding: EdgeInsets.only(right: settings.wordSpacing),
                        child: Text(
                          '$displayText ',
                          style: TextStyle(
                            fontSize: effectiveFontSize,
                            fontWeight:
                                word.isBold ? FontWeight.bold : FontWeight.w500,
                            fontStyle: word.isItalic
                                ? FontStyle.italic
                                : FontStyle.normal,
                            letterSpacing: settings.letterSpacing,
                            color: wordColor,
                            shadows: shadows,
                            decoration: word.isUnderline
                                ? TextDecoration.underline
                                : null,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Alignment _toAlignment(TextAlign? paraAlign, AppSettings settings) {
    if (paraAlign == TextAlign.center ||
        (paraAlign == null && settings.textAlign == 'center')) {
      return Alignment.center;
    }
    if (paraAlign == TextAlign.right ||
        (paraAlign == null && settings.textAlign == 'right')) {
      return Alignment.centerRight;
    }
    return Alignment.centerLeft;
  }

  WrapAlignment _toWrapAlignment(TextAlign? paraAlign, AppSettings settings) {
    if (paraAlign == TextAlign.center ||
        (paraAlign == null && settings.textAlign == 'center')) {
      return WrapAlignment.center;
    }
    if (paraAlign == TextAlign.right ||
        (paraAlign == null && settings.textAlign == 'right')) {
      return WrapAlignment.end;
    }
    return WrapAlignment.start;
  }
}

class _LensHUDPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFBF00).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const radius = 60.0;
    const bracketSize = 12.0;

    canvas.drawLine(Offset(centerX - radius, centerY - radius),
        Offset(centerX - radius + bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY - radius),
        Offset(centerX - radius, centerY - radius + bracketSize), paint);

    canvas.drawLine(Offset(centerX + radius, centerY - radius),
        Offset(centerX + radius - bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY - radius),
        Offset(centerX + radius, centerY - radius + bracketSize), paint);

    canvas.drawLine(Offset(centerX - radius, centerY + radius),
        Offset(centerX - radius + bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY + radius),
        Offset(centerX - radius, centerY + radius - bracketSize), paint);

    canvas.drawLine(Offset(centerX + radius, centerY + radius),
        Offset(centerX + radius - bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY + radius),
        Offset(centerX + radius, centerY + radius - bracketSize), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
