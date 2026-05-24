import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import '../providers/teleprompter_provider.dart';
import '../../script/providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../script/models/script.dart';
import 'teleprompter_screen.dart';

class ContentCreatorScreen extends ConsumerStatefulWidget {
  const ContentCreatorScreen({super.key});

  @override
  ConsumerState<ContentCreatorScreen> createState() =>
      _ContentCreatorScreenState();
}

class _ContentCreatorScreenState extends ConsumerState<ContentCreatorScreen> {
  CameraController? _cameraController;
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _wordKeys = [];
  bool _isInit = false;
  bool _isCameraInitializing = true;
  bool _isRecording = false;
  String? _cameraError;
  int _countdown = 0;
  int _recordSeconds = 0;
  int _activeWordIndex = 0;
  Timer? _recordTimer;
  Timer? _autoScrollTimer;
  Timer? _wordTrackTimer;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      setState(() {
        _isCameraInitializing = true;
        _cameraError = null;
      });
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isInit = false;
            _isCameraInitializing = false;
            _cameraError = 'No camera was found on this Windows device.';
          });
        }
        return;
      }

      // Find front camera
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final settings = ref.read(settingsProvider);
      ResolutionPreset preset = ResolutionPreset.medium; // 720p
      if (settings.videoResolution.contains('1080')) {
        preset = ResolutionPreset.high;
      } else if (settings.videoResolution.contains('480')) {
        preset = ResolutionPreset.low;
      }

      await _cameraController?.dispose();
      _cameraController = CameraController(front, preset, enableAudio: true);
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isInit = true;
          _isCameraInitializing = false;
          _cameraError = null;
        });
      }
    } catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        setState(() {
          _isInit = false;
          _isCameraInitializing = false;
          _cameraError =
              'Camera could not start. Check Windows camera and microphone permissions.';
        });
      }
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _autoScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
    _cameraController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _showSnack(
        _cameraError ?? 'Camera is still preparing. Try again in a moment.',
      );
      return;
    }

    if (_isRecording) {
      final file = await _cameraController!.stopVideoRecording();
      _recordTimer?.cancel();
      _stopAutoScroll();
      setState(() {
        _isRecording = false;
        _recordSeconds = 0;
      });
      try {
        await Gal.putVideo(file.path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Video saved to gallery!'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        debugPrint('Save error: $e');
        _showSnack('Recording saved locally, but gallery export failed.');
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
      setState(() {
        _isRecording = true;
        _activeWordIndex = ref.read(teleprompterProvider).confirmedWordIndex;
      });
      _startAutoScroll();
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _setVideoResolution(String resolution) async {
    if (_isRecording) {
      _showSnack('Stop recording before changing video resolution.');
      return;
    }
    await ref.read(settingsProvider.notifier).setVideoResolution(resolution);
    await _initializeCamera();
  }

  void _startAutoScroll() {
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isRecording) _startAutoScroll();
      });
      return;
    }
    _autoScrollTimer?.cancel();
    _wordTrackTimer?.cancel();

    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_isRecording || !_scrollController.hasClients) return;
      final settings = ref.read(settingsProvider);
      final speed = settings.scrollSpeed;
      if (speed == 0) return;

      final pxPerTick = speed.abs() * 3.0 * 16.0 / 1000.0;
      final delta = speed < 0 ? -pxPerTick : pxPerTick;
      final max = _scrollController.position.maxScrollExtent;
      final next = (_scrollController.offset + delta).clamp(0.0, max);
      _scrollController.jumpTo(next);
      if (next == 0.0 || next == max) _stopAutoScroll();
    });

    _wordTrackTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _updateActiveWordFromScroll();
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
  }

  void _updateActiveWordFromScroll() {
    if (!mounted || !_scrollController.hasClients || _wordKeys.isEmpty) return;
    final settings = ref.read(settingsProvider);
    final targetY = MediaQuery.of(context).size.height * settings.scrollLead;
    final start = (_activeWordIndex - 5).clamp(0, _wordKeys.length - 1);
    final end = (_activeWordIndex + 25).clamp(0, _wordKeys.length - 1);

    var bestIndex = _activeWordIndex;
    var bestDistance = double.infinity;
    for (var i = start; i <= end; i++) {
      final ctx = _wordKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final distance = (box.localToGlobal(Offset.zero).dy - targetY).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    if (bestIndex != _activeWordIndex) {
      setState(() => _activeWordIndex = bestIndex);
    }
  }

  String _formatTimer(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return "$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final script = ref.watch(scriptProvider);
    final settings = ref.watch(settingsProvider);
    final tState = ref.watch(teleprompterProvider);
    final activeWordIndex =
        _isRecording ? _activeWordIndex : tState.confirmedWordIndex;

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
                                      borderRadius: BorderRadius.circular(6)),
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
                                      color:
                                          Colors.black.withValues(alpha: 0.4),
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
                    child:
                        _buildPrompterContent(script, settings, activeWordIndex),
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
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording
                            ? Colors.red
                            : Colors.red.withValues(alpha: 0.5),
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
                        onPressed: _showContentCreatorSettings,
                      ),
                      IconButton(
                        icon: const Icon(Icons.replay, color: Colors.white70),
                        onPressed: () {
                          _scrollController.jumpTo(0);
                          setState(() => _activeWordIndex = 0);
                        },
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

  Widget _buildCameraFallback() {
    if (_isCameraInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFBF00)),
      );
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white54, size: 34),
            const SizedBox(height: 10),
            Text(
              _cameraError ?? 'Camera is unavailable.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry camera'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFBF00),
                side: const BorderSide(color: Color(0xFFFFBF00)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContentCreatorSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).padding.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Recording',
                  style: TextStyle(
                    color: Color(0xFFFFBF00),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['480p', '720p', '1080p'].map((resolution) {
                    final selected = settings.videoResolution == resolution;
                    return ChoiceChip(
                      label: Text(resolution),
                      selected: selected,
                      onSelected: (_) => _setVideoResolution(resolution),
                      selectedColor: const Color(0xFFFFBF00),
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white70,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      backgroundColor: const Color(0xFF1E1E1E),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: this.context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const TeleprompterSettingsPanel(),
                    );
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Teleprompter settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPrompterContent(
      Script? script, AppSettings settings, int activeWordIndex) {
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
                    final isCurrent = i == activeWordIndex;
                    final isPast = i < activeWordIndex;
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
