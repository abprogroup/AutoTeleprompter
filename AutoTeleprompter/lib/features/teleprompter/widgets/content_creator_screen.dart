import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../providers/teleprompter_provider.dart';
import '../../script/providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../script/models/script.dart';
import 'teleprompter_screen.dart';

class ContentCreatorScreen extends ConsumerStatefulWidget {
  const ContentCreatorScreen({super.key});

  @override
  ConsumerState<ContentCreatorScreen> createState() => _ContentCreatorScreenState();
}

class _ContentCreatorScreenState extends ConsumerState<ContentCreatorScreen> {
  CameraController? _cameraController;
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _wordKeys = [];
  bool _isInit = false;
  bool _isRecording = false;
  int _countdown = 0;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    
    // Find front camera
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    
    final settings = ref.read(settingsProvider);
    ResolutionPreset preset = ResolutionPreset.medium; // 720p
    if (settings.videoResolution.contains('1080')) preset = ResolutionPreset.high;
    else if (settings.videoResolution.contains('480')) preset = ResolutionPreset.low;

    _cameraController = CameraController(front, preset, enableAudio: true);
    try {
      await _cameraController!.initialize();
      if (mounted) setState(() => _isInit = true);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _cameraController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    if (_isRecording) {
      final file = await _cameraController!.stopVideoRecording();
      _recordTimer?.cancel();
      setState(() {
        _isRecording = false;
        _recordSeconds = 0;
      });
      try {
        await Gal.putVideo(file.path);
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Video saved to gallery!'), backgroundColor: Colors.green),
           );
        }
      } catch (e) {
        debugPrint('Save error: $e');
      }
    } else {
      // Professional Countdown
      for (int i = 3; i > 0; i--) {
        if (!mounted) return;
        setState(() => _countdown = i);
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() => _countdown = 0);

      await _cameraController!.startVideoRecording();
      _recordSeconds = 0;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _recordSeconds = t.tick);
      });
      ref.read(settingsProvider.notifier).setScrollSpeed(100);
      setState(() => _isRecording = true);
    }
  }

  String _formatTimer(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return "${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final script = ref.watch(scriptProvider);
    final settings = ref.watch(settingsProvider);
    final tState = ref.watch(teleprompterProvider);

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
                  child: _isInit 
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRect(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _cameraController!.value.previewSize!.height,
                                height: _cameraController!.value.previewSize!.width,
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
                                  Colors.black.withOpacity(0.5),
                                  Colors.black.withOpacity(0.9),
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
                              top: 20, right: 20,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.circle, color: Colors.white, size: 8),
                                    const SizedBox(width: 6),
                                    Text(_formatTimer(_recordSeconds), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          // V3 Pro: Countdown Overlay
                          if (_countdown > 0)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(40),
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle),
                                child: Text('$_countdown', style: const TextStyle(color: Color(0xFFFFBF00), fontSize: 80, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      )
                    : const Center(child: CircularProgressIndicator()),
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
                  onTap: _toggleRecording,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording ? Colors.red : Colors.red.withOpacity(0.5),
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.videocam,
                        color: Colors.white,
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
                        onPressed: () => Navigator.pop(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune, color: Colors.white70),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const TeleprompterSettingsPanel(),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.replay, color: Colors.white70),
                        onPressed: () => _scrollController.jumpTo(0),
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

  Widget _buildPrompterContent(Script? script, AppSettings settings, dynamic tState) {
    if (script == null || script.isEmpty) {
      return const Center(child: Text('No script loaded.', style: TextStyle(color: Colors.white)));
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
            key: para[0].index < _wordKeys.length ? _wordKeys[para[0].index] : null,
            height: settings.fontSize * 1.5 + (settings.lineSpacing * 4),
          );
        }

        final firstWord = para.first;
        final paraDir = firstWord.effectiveRtl ? TextDirection.rtl : TextDirection.ltr;
        final paraAlign = firstWord.alignment;

        return Padding(
          padding: EdgeInsetsDirectional.only(bottom: settings.lineSpacing * 6),
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
                  final displayText = word.raw.replaceAll(RegExp(r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg)(?:=[^\]]+)?\]|\*\*'), '');

                  Color wordColor;
                  final futureColor = word.textColor ?? Color(settings.futureWordColor);
                  if (isCurrent) {
                    wordColor = Color(settings.currentWordColor);
                  } else if (isPast) {
                    wordColor = futureColor.withOpacity(settings.pastWordOpacity);
                  } else {
                    wordColor = futureColor;
                  }

                  final effectiveFontSize = word.fontSize != null
                      ? settings.fontSize * (word.fontSize! / 17.0)
                      : settings.fontSize;

                  return Directionality(
                    textDirection: word.effectiveRtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Container(
                      key: i < _wordKeys.length ? _wordKeys[i] : null,
                      padding: EdgeInsets.only(right: settings.wordSpacing),
                      child: Text(
                        '$displayText ',
                        style: TextStyle(
                          fontSize: effectiveFontSize,
                          fontWeight: word.isBold ? FontWeight.bold : FontWeight.w500,
                          fontStyle: word.isItalic ? FontStyle.italic : FontStyle.normal,
                          letterSpacing: settings.letterSpacing,
                          color: wordColor,
                          decoration: word.isUnderline ? TextDecoration.underline : null,
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
    ),);
  }

  // Helper methods duplicated from TeleprompterScreen for isolation
  Alignment _toAlignment(TextAlign? paraAlign, AppSettings settings) {
    if (paraAlign == TextAlign.center || (paraAlign == null && settings.textAlign == 'center')) return Alignment.center;
    if (paraAlign == TextAlign.right || (paraAlign == null && settings.textAlign == 'right')) return Alignment.centerRight;
    return Alignment.centerLeft;
  }

  WrapAlignment _toWrapAlignment(TextAlign? paraAlign, AppSettings settings) {
    if (paraAlign == TextAlign.center || (paraAlign == null && settings.textAlign == 'center')) return WrapAlignment.center;
    if (paraAlign == TextAlign.right || (paraAlign == null && settings.textAlign == 'right')) return WrapAlignment.end;
    return WrapAlignment.start;
  }
}

class _LensHUDPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFBF00).withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const radius = 60.0;
    const bracketSize = 12.0;

    // Drawing 4 corners of a focus square
    // Top-Left
    canvas.drawLine(Offset(centerX - radius, centerY - radius), Offset(centerX - radius + bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY - radius), Offset(centerX - radius, centerY - radius + bracketSize), paint);
    
    // Top-Right
    canvas.drawLine(Offset(centerX + radius, centerY - radius), Offset(centerX + radius - bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY - radius), Offset(centerX + radius, centerY - radius + bracketSize), paint);
    
    // Bottom-Left
    canvas.drawLine(Offset(centerX - radius, centerY + radius), Offset(centerX - radius + bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY + radius), Offset(centerX - radius, centerY + radius - bracketSize), paint);
    
    // Bottom-Right
    canvas.drawLine(Offset(centerX + radius, centerY + radius), Offset(centerX + radius - bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY + radius), Offset(centerX + radius, centerY + radius - bracketSize), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
