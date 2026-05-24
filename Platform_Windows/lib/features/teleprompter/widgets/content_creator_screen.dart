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

part 'content_creator_screen.widgets.dart';

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
                    child: _buildPrompterContent(
                        script, settings, activeWordIndex),
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
}
