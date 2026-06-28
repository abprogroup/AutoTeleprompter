import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../platform/permissions/platform_permissions.dart';
import '../providers/teleprompter_provider.dart';
import '../services/mobile_audio_recorder_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../script/providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../script/models/script.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../../core/widgets/stable_walkthrough_overlay.dart';
import 'teleprompter_screen.dart';

part 'content_creator_screen.recording.dart';
part 'content_creator_screen.settings.dart';
part 'content_creator_screen.controls.dart';
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
  late final TeleprompterNotifier _teleprompterNotifier;
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
  bool _creatorWalkthroughVisible = false;
  int _creatorWalkthroughStep = 0;
  final GlobalKey _creatorSurfaceKey = GlobalKey();
  final GlobalKey _creatorRecordKey = GlobalKey();
  final GlobalKey _creatorSpeechKey = GlobalKey();
  final GlobalKey _creatorSettingsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _teleprompterNotifier = ref.read(teleprompterProvider.notifier);
    if (_contentAudioOnlyMode(ref.read(settingsProvider))) {
      _isInit = true;
    } else {
      _initializeCamera();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted ||
          prefs.getBool('iosContentCreatorWalkthroughSeen') == true) {
        return;
      }
      _setContentCreatorState(() {
        _creatorWalkthroughVisible = true;
        _creatorWalkthroughStep = 0;
      });
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
          _cameraError = 'No camera is available on this iPhone.';
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
          _cameraError = 'Camera could not start. Check iOS permissions.';
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraInitGeneration++;
    _recordTimer?.cancel();
    unawaited(_audioRecorder.cancel());
    unawaited(_audioRecorder.dispose());
    _cameraController?.dispose();
    _scrollController.dispose();
    _overflowBarController.dispose();
    unawaited(_teleprompterNotifier.stopSession());
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

    if (script != null) {
      while (_wordKeys.length < script.words.length) {
        _wordKeys.add(GlobalKey());
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Preview (Bottom 40%)
          Positioned.fill(
            child: Column(
              children: [
                const Spacer(flex: 6),
                Expanded(
                  key: _creatorSurfaceKey,
                  flex: 4,
                  child: audioOnly
                      ? _buildAudioOnlySurface()
                      : _isInit
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRect(
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: _cameraController!
                                          .value.previewSize!.height,
                                      height: _cameraController!
                                          .value.previewSize!.width,
                                      child: CameraPreview(_cameraController!),
                                    ),
                                  ),
                                ),
                                // V3 Pro: Enhanced Eye-Contact Radial Vignette
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: Alignment.center,
                                      radius: 0.85,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.5),
                                        Colors.black.withValues(alpha: 0.9),
                                      ],
                                      stops: const [0.4, 0.7, 1.0],
                                    ),
                                  ),
                                ),
                                // V3 Pro: Camera Lens HUD Painter
                                CustomPaint(
                                  painter: _LensHUDPainter(),
                                  child: Container(),
                                ),
                                // V3 Pro: Session Timer HUD
                                if (_isRecording)
                                  Positioned(
                                    top: 20,
                                    right: 20,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(6)),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.circle,
                                              color: Colors.white, size: 8),
                                          const SizedBox(width: 6),
                                          Text(_formatTimer(_recordSeconds),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  ),
                                // V3 Pro: Countdown Overlay
                                if (_countdown > 0)
                                  Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(40),
                                      decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.4),
                                          shape: BoxShape.circle),
                                      child: Text('$_countdown',
                                          style: const TextStyle(
                                              color: Color(0xFFFFBF00),
                                              fontSize: 80,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                              ],
                            )
                          : _buildCameraFallback(),
                ),
              ],
            ),
          ),

          // 2. Eye-Contact Prompter (Top 60%)
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                      top: 40,
                      bottom: MediaQuery.of(context).size.height * 0.3,
                      left: 20,
                      right: 20,
                    ),
                    child: _buildPrompterContent(script, settings, tState),
                  ),
                ),
                const Spacer(flex: 4),
              ],
            ),
          ),

          if (settings.showSoundLevelMeter &&
              !settings.debugMode &&
              (tState.isListening || tState.isStarting))
            Positioned(
              left: 20,
              right: 20,
              bottom: 232,
              child: _buildCreatorListeningMeter(tState),
            ),

          // 3. Recording controls: draggable overflow row (upper) + record
          //    button + fixed most-needed row (lower).
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: _buildCreatorControls(settings, tState, audioOnly),
          ),
          if (_creatorWalkthroughVisible) _buildCreatorWalkthroughOverlay(),
        ],
      ),
    );
  }

  Widget _buildCreatorListeningMeter(dynamic tState) {
    final level = tState.isStarting
        ? 0.0
        : (tState.soundLevel as double).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFFFBF00).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            tState.isStarting
                ? Icons.hourglass_empty_rounded
                : Icons.graphic_eq,
            color: const Color(0xFFFFBF00),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: tState.isStarting ? null : level,
                minHeight: 8,
                backgroundColor: Colors.white12,
                color: const Color(0xFFFFBF00),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            tState.isStarting ? 'STARTING' : 'LISTENING',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrompterContent(
      Script? script, AppSettings settings, dynamic tState) {
    if (script == null || script.isEmpty) {
      return const Center(
          child:
              Text('No script loaded.', style: TextStyle(color: Colors.white)));
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

    return Container(
      color: Color(settings.scriptBgColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: paragraphs.map<Widget>((para) {
          if (para.length == 1 && para[0].isNewline) {
            return SizedBox(
              key: para[0].index < _wordKeys.length
                  ? _wordKeys[para[0].index]
                  : null,
              height: settings.fontSize * 1.5 + (settings.lineSpacing * 4),
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
                        ? settings.fontSize * (word.fontSize! / 17.0)
                        : settings.fontSize;

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

  // Helper methods duplicated from TeleprompterScreen for isolation
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

    // Drawing 4 corners of a focus square
    // Top-Left
    canvas.drawLine(Offset(centerX - radius, centerY - radius),
        Offset(centerX - radius + bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY - radius),
        Offset(centerX - radius, centerY - radius + bracketSize), paint);

    // Top-Right
    canvas.drawLine(Offset(centerX + radius, centerY - radius),
        Offset(centerX + radius - bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY - radius),
        Offset(centerX + radius, centerY - radius + bracketSize), paint);

    // Bottom-Left
    canvas.drawLine(Offset(centerX - radius, centerY + radius),
        Offset(centerX - radius + bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY + radius),
        Offset(centerX - radius, centerY + radius - bracketSize), paint);

    // Bottom-Right
    canvas.drawLine(Offset(centerX + radius, centerY + radius),
        Offset(centerX + radius - bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY + radius),
        Offset(centerX + radius, centerY + radius - bracketSize), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
