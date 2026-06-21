import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../platform/permissions/platform_permissions.dart';
import '../providers/teleprompter_provider.dart';
import '../services/mobile_audio_recorder_service.dart';
import '../../script/providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../script/models/script.dart';
import 'teleprompter_screen.dart';

part 'content_creator_screen.recording.dart';
part 'content_creator_screen.settings.dart';

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
  final List<GlobalKey> _wordKeys = [];
  List<CameraDescription> _availableCameras = const [];
  int _selectedCameraIndex = 0;
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

  @override
  void initState() {
    super.initState();
    _teleprompterNotifier = ref.read(teleprompterProvider.notifier);
    if (_contentAudioOnlyMode(ref.read(settingsProvider))) {
      _isInit = true;
    } else {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (!mounted) return;
    setState(() {
      _isCameraInitializing = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
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
      final nextController = CameraController(
        cameras[_selectedCameraIndex],
        preset,
        enableAudio: true,
      );
      _cameraController = nextController;
      await previousController?.dispose();
      await nextController.initialize();
      if (!mounted) return;
      setState(() {
        _isInit = true;
        _isCameraInitializing = false;
        _cameraError = null;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Camera error: $e');
      if (mounted) {
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
    _recordTimer?.cancel();
    unawaited(_audioRecorder.cancel());
    unawaited(_audioRecorder.dispose());
    _cameraController?.dispose();
    _scrollController.dispose();
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

          // 3. Recording Controls & Floating Buttons
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Red Trigger Button
                GestureDetector(
                  onTap: _recordStartInFlight ? null : _toggleRecording,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording
                            ? Colors.red
                            : _recordStartInFlight
                                ? const Color(0xFFFFBF00)
                                : Colors.red.withValues(alpha: 0.5),
                      ),
                      child: Icon(
                        _isRecording
                            ? Icons.stop
                            : _recordStartInFlight
                                ? Icons.hourglass_top_rounded
                                : (audioOnly ? Icons.mic : Icons.videocam),
                        color:
                            _recordStartInFlight ? Colors.black : Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Standard Controls Bar (Close, Settings, Replay)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: _exitContentCreator,
                      ),
                      if (!settings.contentCreatorRecordingControlsSpeech)
                        IconButton(
                          icon: Icon(
                            tState.isListening || tState.isStarting
                                ? Icons.mic
                                : Icons.mic_none_outlined,
                            color: tState.isListening || tState.isStarting
                                ? const Color(0xFFFFBF00)
                                : Colors.white70,
                          ),
                          onPressed: _toggleSpeechSession,
                        ),
                      IconButton(
                        icon: const Icon(Icons.tune, color: Colors.white70),
                        onPressed: _showCreatorSettings,
                      ),
                      IconButton(
                        icon: const Icon(Icons.replay, color: Colors.white70),
                        onPressed: _resetCreatorPosition,
                      ),
                    ],
                  ),
                ),
              ],
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
