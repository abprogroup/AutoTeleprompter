import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_windows/webview_windows.dart';
import '../models/alignment_result.dart';
import '../providers/teleprompter_provider.dart';
import '../services/approximate_spoken_search_service.dart';
import '../services/presenter_input_lock_service.dart';
import '../../script/services/script_color_inversion_service.dart';
import '../../script/providers/script_provider.dart';
import '../../script/models/script.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../script/services/markup_decoration_service.dart';
import '../../script/services/highlight_band_painter.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../../core/widgets/global_color_picker.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../remote/services/remote_control_service.dart';
import '../../../core/window/presenter_fullscreen_service.dart';
import '../../../platform/permissions/platform_permissions.dart';
import '../../../platform/stt/abstract_stt_service.dart';
import '../../../platform/webview2/webview2_runtime_config.dart';

part 'teleprompter_screen.session_stt.dart';
part 'teleprompter_screen.manual_scroll.dart';
part 'teleprompter_screen.bookmarks_search.dart';
part 'teleprompter_screen.presenter_search.dart';
part 'teleprompter_screen.smooth_settings.dart';
part 'teleprompter_screen.chrome.dart';
part 'teleprompter_screen.presenter_word_list.dart';
part 'teleprompter_screen.presenter_transform.dart';
part 'teleprompter_screen.build.dart';
part 'teleprompter_screen.debug_console.dart';
part 'teleprompter_screen.decoration_painter.dart';
part 'teleprompter_screen.alignment_helpers.dart';
part 'teleprompter_screen.audio_debug_widgets.dart';
part 'teleprompter_screen.control_bar.dart';
part 'teleprompter_screen.settings_panel.dart';
part 'teleprompter_screen.speech_settings.dart';
part 'teleprompter_screen.settings_widgets.dart';

// Regex to strip any unprocessed markup tags that somehow leaked into word.raw
final _tagStripRe = RegExp(
    r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg|font|align)(?:=[^\]]+)?\]|\*\*');

class _PresentationSearchIntent extends Intent {
  const _PresentationSearchIntent();
}

class TeleprompterScreen extends ConsumerStatefulWidget {
  const TeleprompterScreen({super.key});

  @override
  ConsumerState<TeleprompterScreen> createState() => _TeleprompterScreenState();
}

class _TeleprompterScreenState extends ConsumerState<TeleprompterScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _presenterContentKey = GlobalKey();
  final GlobalKey _presenterReadingLineKey = GlobalKey();
  final List<GlobalKey> _wordKeys = [];
  bool _controlsVisible = true;
  bool _debugConsoleMinimized = false;
  bool _debugConsolePinned = false;
  Timer? _manualScrollTimer;
  Timer? _wordTrackTimer;
  Timer? _hideControlsTimer;
  Timer? _smoothScrollTimer;
  double _scrollTarget = 0.0;
  bool _smoothScrollActive = false;
  int _manualWordIndex = 0;
  bool _manualScrolling = false;
  bool _scrollingBackward = false;
  bool _closingPresentation = false;
  bool _userBrowsingWhileStopped = false;
  StreamSubscription? _remoteCmdSub;
  WebviewController? _webviewController;
  String? _loadedWebViewUrl;
  String _lastSearchQuery = '';
  bool _searchDialogOpen = false;
  bool _resumeDialogShown = false;
  // Presenter search state
  List<_PresenterSearchMatch> _presenterSearchMatches = const [];
  int _presenterSearchMatchIndex = -1;
  bool _presenterSearchToolbarVisible = false;
  bool _searchWholeWord = false;
  String? _bookmarkScopeKey;
  String? _bookmarkLoadingKey;
  bool _bookmarksLoaded = false;
  List<ScriptBookmark> _bookmarks = const [];
  bool _visibleWindowSyncScheduled = false;
  String? _visibleWindowLayoutKey;
  String? _paragraphCacheKey;
  List<List<ScriptWord>> _paragraphCache = const [];
  String? _lastPublishedRemoteScrollMode;
  double? _lastPublishedRemoteScrollSpeed;
  bool? _lastPublishedRemoteScriptActive;
  bool? _lastPublishedRemoteSessionActive;
  bool? _lastPublishedRemoteIsStarting;
  DateTime? _lastVisibleWindowSync;
  DateTime? _lastBrowsingWordSync;
  bool _windowsControlsHovering = false;
  bool _presenterFullscreen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handlePresentationKey);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!Platform.isWindows) _scheduleHideControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initRemoteListener();
        ref.listenManual(teleprompterProvider.select((s) => s.missingLanguage),
            (prev, next) {
          if (next != null && next.isNotEmpty && mounted) {
            _showMissingLanguageDialog(next);
          }
        });
        // Watch for STT Dashboard URL
        ref.listenManual(teleprompterProvider.select((s) => s.sttWebViewUrl),
            (prev, next) {
          if (next == null) {
            _loadedWebViewUrl = null;
          } else if (next != _loadedWebViewUrl) {
            _loadSttWebView(next);
          }
        });
        ref.listenManual(
            teleprompterProvider.select((s) => s.isListening || s.isStarting),
            (prev, next) {
          if (!mounted || !Platform.isWindows) return;
          _syncWindowsControlsForSpeech(next);
        });
        if (Platform.isWindows) _initWebViewController();
        final currentIndex = ref.read(teleprompterProvider).confirmedWordIndex;
        if (currentIndex > 0 && !_resumeDialogShown) {
          _resumeDialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // Jump to the saved position FIRST so the user can see it in the
            // faded background before deciding whether to continue or restart.
            _jumpToWordIndex(currentIndex, immediate: true);
            // Show the dialog after layout settles.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showResumeDialog(currentIndex);
            });
          });
        }
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handlePresentationKey);
    ref.read(teleprompterProvider.notifier).stopSession();
    WakelockPlus.disable();
    if (_presenterFullscreen) {
      unawaited(PresenterFullscreenService.setEnabled(false));
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _manualScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
    _hideControlsTimer?.cancel();
    _smoothScrollTimer?.cancel();
    ref.read(remoteControlProvider).publishPresenterState(
          scriptActive: false,
          sessionActive: false,
          isStarting: false,
          scrollMode: 'auto',
          scrollSpeed: 0,
        );
    _scrollController.dispose();
    _remoteCmdSub?.cancel();
    _webviewController?.dispose();
    super.dispose();
  }

  void _setPresenterDebugPinned(bool value) {
    setState(() {
      _debugConsolePinned = value;
      if (_debugConsolePinned) {
        _debugConsoleMinimized = false;
      }
    });
  }

  void _setPresenterDebugExpanded(bool expanded) {
    setState(() {
      if (expanded) {
        _debugConsoleMinimized = false;
        if (!_controlsVisible) {
          _debugConsolePinned = true;
        }
      } else {
        _debugConsoleMinimized = true;
      }
    });
  }

  void _setTeleprompterState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) => _buildTeleprompterScreen(context);
}
