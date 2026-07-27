import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../../platform/permissions/platform_permissions.dart';
import '../../../platform/webview2/webview2_runtime_config.dart';
import '../models/alignment_result.dart';
import '../services/content_camera_device_classifier.dart';
import '../services/presenter_input_lock_service.dart';
import '../services/presenter_reading_position_service.dart';
import '../services/recording_media_probe_service.dart';
import '../services/recording_export_service.dart';
import '../../script/services/script_color_inversion_service.dart';
import '../services/wav_audio_recorder_service.dart';
import '../providers/teleprompter_provider.dart';
import '../services/approximate_spoken_search_service.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../../core/window/presenter_fullscreen_service.dart';
import '../../script/providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/services/cloud_app_folder_sync_service.dart';
import '../../settings/services/cloud_oauth_service.dart';
import '../../script/models/script_word.dart';
import '../../script/models/script.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../script/services/markup_decoration_service.dart';
import '../../script/services/highlight_band_painter.dart';
import 'presenter_bookmark_marker_layer.dart';
import 'teleprompter_screen.dart';

part 'content_creator_screen.widgets.dart';
part 'content_creator_screen.controls.dart';
part 'content_creator_screen.presenter_tools.dart';
part 'content_creator_screen.presenter_view.dart';
part 'content_creator_screen.session.dart';
part 'content_creator_screen.debug.dart';
part 'content_creator_screen.camera.dart';
part 'content_creator_screen.recording_flow.dart';
part 'content_creator_screen.camera_webview.dart';
part 'content_creator_screen.scroll_state.dart';
part 'content_creator_screen.camera_settings.dart';
part 'content_creator_screen.camera_settings_controls.dart';
part 'content_creator_screen.camera_widgets.dart';

final _contentCreatorTagStripRe = RegExp(
    r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg|font|align)(?:=[^\]]+)?\]|\*\*');

enum _ContentCameraSourceMode { native, usb, virtual, all }

class ContentCreatorScreen extends ConsumerStatefulWidget {
  final bool audioOnlyEntry;

  const ContentCreatorScreen({super.key, this.audioOnlyEntry = false});

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
  final WavAudioRecorderService _wavAudioRecorder = WavAudioRecorderService();
  final List<GlobalKey> _wordKeys = [];
  bool _isInit = false;
  bool _isCameraInitializing = true;
  bool _cameraWasChosenByUser = false;
  bool _cameraAudioEnabled = false;
  _ContentCameraSourceMode _cameraSourceMode = _ContentCameraSourceMode.native;
  int _cameraInitGeneration = 0;
  bool _isRecording = false;
  bool _isAudioOnlyRecording = false;
  String? _cameraError;
  int _countdown = 0;
  int _recordSeconds = 0;
  int _activeWordIndex = 0;
  bool _recordStartInFlight = false;
  bool _recordingStartedSpeechSession = false;
  double? _recordExportProgress;
  String? _activeScriptSeedKey;
  Timer? _recordTimer;
  Timer? _autoScrollTimer;
  Timer? _wordTrackTimer;
  Timer? _positionCommitTimer;
  WebviewController? _contentWebviewController;
  String? _loadedContentWebViewUrl;
  int? _pendingPositionCommit;
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
  bool _resumeDialogShown = false;
  bool _contentControlsVisible = true;
  bool _contentControlsHovering = false;
  bool _contentManualScrolling = false;
  bool _contentDebugConsoleMinimized = false;
  bool _contentDebugConsolePinned = false;
  bool _contentFrameConfirmed = false;
  bool _contentFullscreen = false;
  bool _contentResumeDecisionPending = false;
  int _lastContentRotation = 0;
  int _contentEntryResumeIndex = 0;
  Timer? _hideContentControlsTimer;
  final List<String> _contentDebugLogs = [];
  DateTime? _contentRotationRecenterUntil;
  DateTime? _contentProgrammaticScrollCommitBlockedUntil;

  @override
  void initState() {
    super.initState();
    _cameraSourceMode = _cameraSourceModeFromSettings(
      ref.read(settingsProvider).contentCreatorCameraSourceMode,
    );
    _contentEntryResumeIndex =
        ref.read(teleprompterProvider).confirmedWordIndex;
    _activeWordIndex = 0;
    _resumeDialogShown = _contentEntryResumeIndex <= 0;
    _scrollController.addListener(_handleContentScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.listenManual(teleprompterProvider.select((s) => s.sttWebViewUrl),
          (prev, next) {
        if (next == null) {
          _loadedContentWebViewUrl = null;
        } else if (next != _loadedContentWebViewUrl) {
          _loadContentSttWebView(next);
        }
      });
      ref.listenManual(
          teleprompterProvider.select((s) => s.isListening || s.isStarting),
          (prev, next) {
        if (mounted) _syncContentControlsForActiveSession(next || _isRecording);
      });
      ref.listenManual(teleprompterProvider.select((s) => s.confirmedWordIndex),
          (prev, next) {
        if (!mounted) return;
        final live = ref.read(teleprompterProvider);
        if (!live.isListening || next <= 0) return;
        _updateContentCreatorState(() => _activeWordIndex = next);
        _scrollToContentWordIndex(next);
      });
      _initContentWebViewController();
      final script = ref.read(scriptProvider);
      if (_contentFrameConfirmed && script != null) {
        _maybeShowContentResumePrompt(script);
      }
    });
    final settings = ref.read(settingsProvider);
    if (widget.audioOnlyEntry &&
        settings.contentCreatorRecordingFormat !=
            AppSettings.contentCreatorRecordingFormatWav) {
      unawaited(
        ref.read(settingsProvider.notifier).setContentCreatorRecordingFormat(
              AppSettings.contentCreatorRecordingFormatWav,
            ),
      );
      unawaited(
        ref.read(settingsProvider.notifier).setContentCreatorRecordingAudioMode(
              AppSettings.contentCreatorRecordingAudioCamera,
            ),
      );
    }
    if (widget.audioOnlyEntry || _contentAudioOnlyMode(settings)) {
      _contentFrameConfirmed = true;
      _isCameraInitializing = false;
      _logContentDebug('audio-only content creator entry');
    } else {
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _autoScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
    _positionCommitTimer?.cancel();
    _hideContentControlsTimer?.cancel();
    unawaited(_setContentFullscreen(false));
    _cameraController?.dispose();
    unawaited(_wavAudioRecorder.cancel());
    unawaited(_stopContentSpeechSessionIfOwnedByRecording());
    try {
      ref.read(teleprompterProvider.notifier).setVisibleWordWindow(null, null);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.disposeVisibleWindow',
      );
    }
    _contentWebviewController?.dispose();
    _scrollController.removeListener(_handleContentScroll);
    _scrollController.dispose();
    super.dispose();
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

  bool _contentSessionActive(TeleprompterState tState) {
    return _isRecording ||
        _recordStartInFlight ||
        _contentManualScrolling ||
        tState.isListening ||
        tState.isStarting;
  }

  bool _contentAudioOnlyMode(AppSettings settings) {
    return settings.contentCreatorRecordingFormat ==
        AppSettings.contentCreatorRecordingFormatWav;
  }

  void _scheduleHideContentControls() {
    _hideContentControlsTimer?.cancel();
    if (!_contentSessionActive(ref.read(teleprompterProvider))) {
      if (mounted && !_contentControlsVisible) {
        _updateContentCreatorState(() => _contentControlsVisible = true);
      }
      return;
    }
    _hideContentControlsTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted || _contentControlsHovering) return;
      _updateContentCreatorState(() => _contentControlsVisible = false);
    });
  }

  void _showContentControls() {
    final active = _contentSessionActive(ref.read(teleprompterProvider));
    if (active && !_contentControlsHovering) return;
    _updateContentCreatorState(() => _contentControlsVisible = true);
    if (active) _scheduleHideContentControls();
  }

  void _showContentControlsFromHotZone() {
    _hideContentControlsTimer?.cancel();
    if (mounted && !_contentControlsVisible) {
      _updateContentCreatorState(() => _contentControlsVisible = true);
    }
  }

  void _syncContentControlsForActiveSession(bool active) {
    if (!mounted) return;
    _hideContentControlsTimer?.cancel();
    _contentControlsHovering = false;
    _updateContentCreatorState(
      () => _contentControlsVisible = _recordStartInFlight || !active,
    );
  }

  @override
  Widget build(BuildContext context) {
    final script = ref.watch(scriptProvider);
    final settings = ref.watch(settingsProvider);
    final tState = ref.watch(teleprompterProvider);
    final audioOnlyMode = _contentAudioOnlyMode(settings);

    if (!audioOnlyMode && !_contentFrameConfirmed) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildCameraPreviewEntry(settings),
      );
    }

    final normalizedRotation = ((settings.flipRotation % 360) + 360) % 360;
    if (_lastContentRotation != normalizedRotation) {
      final preservedOffset =
          _scrollController.hasClients ? _scrollController.offset : null;
      final preservedIndex = _activeContentIndex();
      _lastContentRotation = normalizedRotation;
      _contentRotationRecenterUntil =
          DateTime.now().add(const Duration(milliseconds: 650));
      _scheduleContentRotationRestore(
        preservedOffset: preservedOffset,
        fallbackIndex: preservedIndex,
      );
    }

    if (script != null) {
      final seedKey =
          '${script.sessionId}|${script.title}|${script.words.length}';
      if (_activeScriptSeedKey != seedKey) {
        _activeScriptSeedKey = seedKey;
        final pendingResume = _contentEntryResumeIndex > 0 &&
            !_resumeDialogShown &&
            !tState.isListening &&
            !tState.isStarting;
        _activeWordIndex = pendingResume
            ? 0
            : tState.confirmedWordIndex
                .clamp(0, script.words.isEmpty ? 0 : script.words.length - 1)
                .toInt();
        _pendingPositionCommit = null;
        _positionCommitTimer?.cancel();
      }
      while (_wordKeys.length < script.words.length) {
        _wordKeys.add(GlobalKey());
      }
      if (_wordKeys.length > script.words.length) {
        _wordKeys.removeRange(script.words.length, _wordKeys.length);
      }
      unawaited(_loadBookmarksForScript(script));
    }
    final activeWordIndex = script == null || script.words.isEmpty
        ? 0
        : _activeWordIndex.clamp(0, script.words.length - 1).toInt();

    final paragraphs =
        script == null ? <List<ScriptWord>>[] : _paragraphsForScript(script);
    final presentationFontSize = settings.fontSize * 2.0;
    final presenterWordGap = _contentWordGap(presentationFontSize, settings);
    final activeStt = tState.isListening || tState.isStarting;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncContentVisibleWordWindow();
    });
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
            allowWordJump: !activeStt && !_contentResumeDecisionPending,
          );

    final contentSessionActive = _contentSessionActive(tState);
    const controlsReservedHeight = 104.0;
    final debugConsoleExpanded = settings.debugMode &&
        !_contentDebugConsoleMinimized &&
        (_contentControlsVisible || _contentDebugConsolePinned);
    final debugConsoleHeight =
        settings.debugMode ? (debugConsoleExpanded ? 220.0 : 38.0) : 0.0;
    final debugConsoleBottom = settings.debugMode
        ? (debugConsoleExpanded
            ? (_contentDebugConsolePinned && !_contentControlsVisible
                ? 10.0
                : controlsReservedHeight)
            : (_contentControlsVisible ? controlsReservedHeight : 10.0))
        : 10.0;
    final allowActiveManualScroll =
        PresenterInputLockService.allowActiveManualScroll(
      settingEnabled: settings.allowScrollDuringActiveSession,
      isListening: tState.isListening,
      isStarting: tState.isStarting,
    );
    final activeInputLocked = PresenterInputLockService.inputLocked(
      isWindows: Platform.isWindows,
      isListening: tState.isListening,
      isStarting: tState.isStarting,
      allowActiveManualScroll: allowActiveManualScroll,
    );
    final inputLocked = activeInputLocked || _contentResumeDecisionPending;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: inputLocked ? null : _showContentControls,
        child: Stack(
          children: [
            _buildCameraBackgroundLayer(),
            _buildReadingSurfaceLayer(),
            if (settings.readFadeIntensity > 0)
              _buildContentReadFadeOverlay(settings),
            _buildContentReadingLine(settings),
            _buildContentPresenterStage(
              settings: settings,
              child: SafeArea(
                child: Listener(
                  onPointerSignal: (event) {
                    if (inputLocked && event is PointerScrollEvent) {
                      GestureBinding.instance.pointerSignalResolver
                          .register(event, (_) {});
                    }
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: inputLocked
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                    child: wordList,
                  ),
                ),
              ),
            ),
            if (_contentWebviewController != null &&
                tState.sttWebViewUrl != null)
              Positioned(
                left: 0,
                bottom: 0,
                width: 1,
                height: 1,
                child: IgnorePointer(
                  ignoring: true,
                  child: Opacity(
                    opacity: 0.01,
                    child: Webview(_contentWebviewController!),
                  ),
                ),
              ),
            if (!audioOnlyMode &&
                _isInit &&
                settings.contentCreatorFeedMode ==
                    AppSettings.contentCreatorFeedBubble)
              _buildCameraBubble(settings),
            if (_isRecording) _buildRecordingTimerHud(),
            if (_recordExportProgress != null) _buildRecordingExportHud(),
            if (_countdown > 0) _buildCountdownOverlay(),
            if (_contentResumeDecisionPending) _buildContentResumeBlocker(),
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(child: _buildContentSearchToolbar()),
            ),
            if (contentSessionActive)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 92,
                child: MouseRegion(
                  opaque: false,
                  onEnter: (_) {
                    _contentControlsHovering = true;
                    _showContentControlsFromHotZone();
                  },
                  onExit: (_) {
                    _contentControlsHovering = false;
                    _scheduleHideContentControls();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildContentControlsOverlay(
                settings: settings,
                tState: tState,
              ),
            ),
            if (settings.debugMode)
              _buildContentCreatorDebugConsole(
                context,
                tState,
                bottom: debugConsoleBottom,
                height: debugConsoleHeight,
                expanded: debugConsoleExpanded,
                accentColor: Color(settings.currentWordColor),
                settings: settings,
                wordCount: script?.words.length ?? 0,
              ),
          ],
        ),
      ),
    );
  }
}
