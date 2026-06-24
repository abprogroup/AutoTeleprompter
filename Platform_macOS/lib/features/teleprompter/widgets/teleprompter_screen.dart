import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/alignment_result.dart';
import '../providers/teleprompter_provider.dart';
import '../services/approximate_spoken_search_service.dart';
import '../services/presenter_reading_position_service.dart';
import '../services/presenter_input_lock_service.dart';
import '../services/stt_recognition_policy_service.dart';
import '../../script/services/script_color_inversion_service.dart';
import '../../script/providers/script_provider.dart';
import '../../script/models/script.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../script/services/markup_decoration_service.dart';
import '../../script/services/highlight_band_painter.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/login_screen.dart';
import '../../../core/widgets/stable_walkthrough_overlay.dart';
import '../../../core/widgets/global_color_picker.dart';
import '../../remote/services/remote_control_service.dart';
import '../../../core/window/presenter_fullscreen_service.dart';
import '../../../platform/permissions/macos_permissions.dart';
import '../../../platform/permissions/platform_permissions.dart';
import '../../../platform/stt/abstract_stt_service.dart';
import '../../../platform/system/external_url_launcher.dart';
import 'presenter_bookmark_marker_layer.dart';
import '../../feedback/widgets/feedback_report_screen.dart';

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
part 'teleprompter_screen.walkthrough.dart';

// Regex to strip any unprocessed markup tags that somehow leaked into word.raw
final _tagStripRe = RegExp(
    r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg|font|align)(?:=[^\]]+)?\]|\*\*');

const double _presenterControlsHotZoneHeight = 104.0;
const Duration _sttStartAffordanceDuration = Duration(milliseconds: 900);

class _PresentationSearchIntent extends Intent {
  const _PresentationSearchIntent();
}

class TeleprompterScreen extends ConsumerStatefulWidget {
  final bool showWalkthroughGuide;

  const TeleprompterScreen({super.key, this.showWalkthroughGuide = false});

  @override
  ConsumerState<TeleprompterScreen> createState() => _TeleprompterScreenState();
}

class _TeleprompterScreenState extends ConsumerState<TeleprompterScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _presenterContentKey = GlobalKey();
  final GlobalKey _presenterReadingLineKey = GlobalKey();
  final GlobalKey _presenterControlsKey = GlobalKey();
  final GlobalKey _presenterSettingsButtonKey = GlobalKey();
  final List<GlobalKey> _wordKeys = [];
  bool _controlsVisible = true;
  bool _debugConsoleMinimized = false;
  bool _debugConsolePinned = false;
  Timer? _manualScrollTimer;
  Timer? _wordTrackTimer;
  Timer? _hideControlsTimer;
  Timer? _smoothScrollTimer;
  Timer? _activeManualCorrectionTimer;
  Timer? _sttStartAffordanceTimer;
  double _scrollTarget = 0.0;
  bool _smoothScrollActive = false;
  int _manualWordIndex = 0;
  bool _manualScrolling = false;
  bool _scrollingBackward = false;
  bool _sttStartAffordanceVisible = false;
  bool _closingPresentation = false;
  bool _userBrowsingWhileStopped = false;
  bool _activeManualCorrection = false;
  StreamSubscription? _remoteCmdSub;
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
  DateTime? _presenterProgrammaticCommitBlockedUntil;
  DateTime? _lastPresenterUserScrollSignalAt;
  Offset? _lastPresenterPointerGlobalPosition;
  bool _windowsControlsHovering = false;
  bool _presenterFullscreen = false;
  bool _presenterWalkthroughVisible = false;
  int _presenterWalkthroughStep = 0;
  int _presenterSttQuestionIndex = 0;
  bool _presenterSttGuideDefaultsApplied = false;
  late final TeleprompterNotifier _teleprompterNotifier;
  late final RemoteControlService _remoteControlService;

  @override
  void initState() {
    super.initState();
    _teleprompterNotifier = ref.read(teleprompterProvider.notifier);
    _remoteControlService = ref.read(remoteControlProvider);
    _presenterWalkthroughVisible = widget.showWalkthroughGuide;
    HardwareKeyboard.instance.addHandler(_handlePresentationKey);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHideControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initRemoteListener();
        ref.listenManual(teleprompterProvider.select((s) => s.missingLanguage),
            (prev, next) {
          if (next != null && next.isNotEmpty && mounted) {
            _showMissingLanguageDialog(next);
          }
        });
        final currentIndex = ref.read(teleprompterProvider).confirmedWordIndex;
        if (currentIndex > 0 && !_resumeDialogShown) {
          _resumeDialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scrollToWordIndex(currentIndex, immediate: true);
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
    _recordPresenterDisposeFailure(
      _teleprompterNotifier.stopSession(),
      source: 'presenter.disposeStopSession',
    );
    _recordPresenterDisposeFailure(
      WakelockPlus.disable(),
      source: 'presenter.disposeWakelock',
    );
    if (_presenterFullscreen) {
      _recordPresenterDisposeFailure(
        PresenterFullscreenService.setEnabled(false),
        source: 'presenter.disposeFullscreenCleanup',
      );
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _manualScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
    _hideControlsTimer?.cancel();
    _smoothScrollTimer?.cancel();
    _activeManualCorrectionTimer?.cancel();
    _sttStartAffordanceTimer?.cancel();
    _remoteControlService.publishPresenterState(
      scriptActive: false,
      sessionActive: false,
      isStarting: false,
      scrollMode: 'auto',
      scrollSpeed: 0,
    );
    _scrollController.dispose();
    _remoteCmdSub?.cancel();
    super.dispose();
  }

  void _recordPresenterDisposeFailure(
    Future<void>? future, {
    required String source,
  }) {
    if (future == null) return;
    unawaited(future.catchError((Object error, StackTrace stack) {
      LightweightDiagnostics.instance.recordError(error, stack, source: source);
    }));
  }

  void _setPresenterDebugPinned(bool value) {
    _setTeleprompterState(() {
      _debugConsolePinned = value;
      if (_debugConsolePinned) {
        _debugConsoleMinimized = false;
      }
    });
  }

  void _setPresenterDebugExpanded(bool expanded) {
    _setTeleprompterState(() {
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

  void _setTeleprompterState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  Widget build(BuildContext context) => _buildTeleprompterScreen(context);
}
