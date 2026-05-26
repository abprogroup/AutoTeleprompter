import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import '../providers/teleprompter_provider.dart';
import '../../script/providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../script/models/script.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../script/services/markup_decoration_service.dart';
import 'teleprompter_screen.dart';

part 'content_creator_screen.widgets.dart';
part 'content_creator_screen.presenter_tools.dart';
part 'content_creator_screen.presenter_view.dart';

final _contentCreatorTagStripRe = RegExp(
    r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg|font|align)(?:=[^\]]+)?\]|\*\*');

enum _ContentCameraSourceMode { native, usb, virtual, all }

class ContentCreatorScreen extends ConsumerStatefulWidget {
  const ContentCreatorScreen({super.key});

  @override
  ConsumerState<ContentCreatorScreen> createState() =>
      _ContentCreatorScreenState();
}

class _ContentCreatorScreenState extends ConsumerState<ContentCreatorScreen> {
  CameraController? _cameraController;
  final GlobalKey _creatorContentKey = GlobalKey();
  List<CameraDescription> _availableCameras = const [];
  String? _selectedCameraName;
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _wordKeys = [];
  bool _isInit = false;
  bool _isCameraInitializing = true;
  bool _cameraWasChosenByUser = false;
  _ContentCameraSourceMode _cameraSourceMode = _ContentCameraSourceMode.native;
  bool _isRecording = false;
  String? _cameraError;
  int _countdown = 0;
  int _recordSeconds = 0;
  int _activeWordIndex = 0;
  Timer? _recordTimer;
  Timer? _autoScrollTimer;
  Timer? _wordTrackTimer;
  String? _bookmarkScopeKey;
  String? _bookmarkLoadingKey;
  bool _bookmarksLoaded = false;
  List<ScriptBookmark> _bookmarks = const [];
  String _lastSearchQuery = '';
  bool _searchDialogOpen = false;
  bool _searchWholeWord = false;
  List<_ContentSearchMatch> _contentSearchMatches = const [];
  int _contentSearchMatchIndex = -1;
  bool _contentSearchToolbarVisible = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera({CameraDescription? preferredCamera}) async {
    try {
      setState(() {
        _isInit = false;
        _isCameraInitializing = true;
        _cameraError = null;
      });
      final discoveredCameras = await availableCameras().timeout(
        const Duration(seconds: 8),
      );
      final cameras = _orderedCameras(discoveredCameras);
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _availableCameras = const [];
            _selectedCameraName = null;
            _cameraWasChosenByUser = false;
            _isInit = false;
            _isCameraInitializing = false;
            _cameraError = 'No camera was found on this Windows device.';
          });
        }
        return;
      }

      final selectedCamera = _resolveCamera(cameras, preferredCamera);
      if (mounted) {
        setState(() {
          _availableCameras = cameras;
          _selectedCameraName = selectedCamera.name;
        });
      }

      final settings = ref.read(settingsProvider);
      ResolutionPreset preset = ResolutionPreset.medium; // 720p
      if (settings.videoResolution.contains('1080')) {
        preset = ResolutionPreset.high;
      } else if (settings.videoResolution.contains('480')) {
        preset = ResolutionPreset.low;
      }

      await _cameraController?.dispose();
      _cameraController =
          CameraController(selectedCamera, preset, enableAudio: true);
      await _cameraController!.initialize().timeout(
            const Duration(seconds: 10),
          );
      if (mounted) {
        setState(() {
          _isInit = true;
          _isCameraInitializing = false;
          _cameraError = null;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Camera error: $e');
      if (mounted) {
        setState(() {
          if (_availableCameras.isEmpty && _selectedCameraName == null) {
            _selectedCameraName = preferredCamera?.name;
          }
          _isInit = false;
          _isCameraInitializing = false;
          _cameraError =
              'Camera could not start. Check Windows camera and microphone permissions.';
        });
      }
    }
  }

  CameraDescription _resolveCamera(
    List<CameraDescription> cameras,
    CameraDescription? preferredCamera,
  ) {
    final preferredName = preferredCamera?.name ??
        (_cameraWasChosenByUser ? _selectedCameraName : null);
    if (preferredName != null) {
      for (final camera in cameras) {
        if (camera.name == preferredName) return camera;
      }
    }
    final sourceCameras = _camerasForSourceMode(cameras, _cameraSourceMode);
    return sourceCameras.isNotEmpty ? sourceCameras.first : cameras.first;
  }

  List<CameraDescription> _camerasForSourceMode(
    List<CameraDescription> cameras,
    _ContentCameraSourceMode mode,
  ) {
    if (mode == _ContentCameraSourceMode.all) return cameras;
    return cameras.where((camera) {
      final name = camera.name.toLowerCase();
      return switch (mode) {
        _ContentCameraSourceMode.native => !_isVirtualCameraName(name) &&
            !_isIrOrDepthCameraName(name) &&
            _isIntegratedCameraName(name),
        _ContentCameraSourceMode.usb => !_isVirtualCameraName(name) &&
            !_isIrOrDepthCameraName(name) &&
            _isUsbCameraName(name),
        _ContentCameraSourceMode.virtual => _isVirtualCameraName(name),
        _ContentCameraSourceMode.all => true,
      };
    }).toList();
  }

  List<CameraDescription> _orderedCameras(List<CameraDescription> cameras) {
    final ordered = List<CameraDescription>.of(cameras);
    ordered.sort((a, b) {
      final priority = _cameraPriority(a).compareTo(_cameraPriority(b));
      if (priority != 0) return priority;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return ordered;
  }

  int _cameraPriority(CameraDescription camera) {
    final name = camera.name.toLowerCase();
    var score = 0;
    if (_isVirtualCameraName(name)) score += 1000;
    if (_isIrOrDepthCameraName(name)) score += 320;
    if (_isIntegratedCameraName(name)) score -= 320;
    if (name.contains('webcam') || name.contains('web camera')) score -= 220;
    if (_isUsbCameraName(name)) score -= 120;
    if (camera.lensDirection == CameraLensDirection.front) score -= 40;
    if (camera.lensDirection == CameraLensDirection.back) score += 40;
    return score;
  }

  bool _isIntegratedCameraName(String name) {
    return name.contains('integrated') ||
        name.contains('built-in') ||
        name.contains('builtin') ||
        name.contains('internal') ||
        name.contains('asus fhd') ||
        name.contains('fhd webcam') ||
        name.contains('hd webcam');
  }

  bool _isIrOrDepthCameraName(String name) {
    return name.contains(' ir ') ||
        name.startsWith('ir ') ||
        name.endsWith(' ir') ||
        name.contains('infrared') ||
        name.contains('depth');
  }

  bool _isUsbCameraName(String name) {
    return name.contains('usb') ||
        name.contains('uvc') ||
        name.contains('external');
  }

  bool _isVirtualCameraName(String name) {
    return name.contains('ndi') ||
        name.contains('obs') ||
        name.contains('virtual') ||
        name.contains('droidcam') ||
        name.contains('iriun') ||
        name.contains('epoccam') ||
        name.contains('camo') ||
        name.contains('snap camera') ||
        name.contains('ip camera') ||
        name.contains('lightform') ||
        name.contains('screen capture');
  }

  String _cameraSourceType(CameraDescription camera) {
    final name = camera.name.toLowerCase();
    if (_isVirtualCameraName(name)) return 'Wi-Fi / virtual camera';
    if (_isIrOrDepthCameraName(name)) return 'IR / depth camera';
    if (_isUsbCameraName(name)) return 'USB camera';
    if (_isIntegratedCameraName(name)) return 'Native camera';
    return 'Camera';
  }

  String _cameraSourceModeLabel(_ContentCameraSourceMode mode) {
    return switch (mode) {
      _ContentCameraSourceMode.native => 'Native',
      _ContentCameraSourceMode.usb => 'USB',
      _ContentCameraSourceMode.virtual => 'Wi-Fi / virtual',
      _ContentCameraSourceMode.all => 'All',
    };
  }

  String _cameraSourceModeHelp(_ContentCameraSourceMode mode) {
    return switch (mode) {
      _ContentCameraSourceMode.native => 'Built-in laptop/webcam first.',
      _ContentCameraSourceMode.usb => 'USB cameras exposed by Windows.',
      _ContentCameraSourceMode.virtual =>
        'NDI, OBS, phone bridges, or Wi-Fi virtual cameras.',
      _ContentCameraSourceMode.all => 'Every Windows camera device.',
    };
  }

  Future<void> _setCameraSourceMode(_ContentCameraSourceMode mode) async {
    if (_isRecording) {
      _showSnack('Stop recording before changing camera source.');
      return;
    }
    final matching = _camerasForSourceMode(_availableCameras, mode);
    final preferred = matching.isEmpty ? null : matching.first;
    setState(() {
      _cameraSourceMode = mode;
      _selectedCameraName = preferred?.name;
      _cameraWasChosenByUser = preferred != null;
    });
    await _initializeCamera(preferredCamera: preferred);
  }

  Future<void> _selectCamera(CameraDescription camera) async {
    if (_isRecording) {
      _showSnack('Stop recording before changing camera.');
      return;
    }
    setState(() {
      _selectedCameraName = camera.name;
      _cameraWasChosenByUser = true;
    });
    await _initializeCamera(preferredCamera: camera);
  }

  String _cameraLabel(CameraDescription camera, int index) {
    final rawDirection = camera.lensDirection.name;
    final direction = rawDirection.isEmpty
        ? 'Camera'
        : '${rawDirection[0].toUpperCase()}${rawDirection.substring(1)}';
    final trimmed = camera.name.trim();
    final name = trimmed.isEmpty ? 'Camera ${index + 1}' : trimmed;
    return '$name - ${_cameraSourceType(camera)} - $direction';
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
        if (kDebugMode) debugPrint('Save error: $e');
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

  void _updateContentCreatorState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
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
      unawaited(_loadBookmarksForScript(script));
    }

    final paragraphs =
        script == null ? <List<ScriptWord>>[] : _paragraphsForScript(script);
    final presentationFontSize = settings.fontSize * 2.0;
    final presenterWordGap = _contentWordGap(presentationFontSize, settings);
    final bookmarkWordIndexes = script == null
        ? <int>{}
        : _bookmarks
            .map(
              (bookmark) => ScriptBookmarkService.nearestBookmarkableWordIndex(
                script.words,
                bookmark.wordIndex,
              ),
            )
            .whereType<int>()
            .toSet();
    final wordList = script == null || script.isEmpty
        ? const Center(
            child: Text(
              'No script loaded.',
              style: TextStyle(color: Colors.white),
            ),
          )
        : _buildContentPresenterWordList(
            context: context,
            script: script,
            paragraphs: paragraphs,
            activeWordIndex: activeWordIndex,
            settings: settings,
            bookmarkWordIndexes: bookmarkWordIndexes,
            presentationFontSize: presentationFontSize,
            presenterWordGap: presenterWordGap,
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildCameraBackgroundLayer(),
          _buildReadingSurfaceLayer(),

          // 2. Eye-Contact Prompter (Top 60%)
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: wordList,
                  ),
                ),
                const Spacer(flex: 4),
              ],
            ),
          ),

          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(child: _buildContentSearchToolbar()),
          ),

          // 3. Recording Controls & Floating Buttons
          Positioned(
            bottom: 16,
            left: 32,
            right: 32,
            child: _buildContentControlBar(settings),
          ),
        ],
      ),
    );
  }
}
