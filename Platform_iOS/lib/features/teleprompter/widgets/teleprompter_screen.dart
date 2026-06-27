import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/teleprompter_provider.dart';
import '../models/alignment_result.dart';
import '../services/presenter_input_lock_service.dart';
import '../../script/providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../script/models/script_word.dart';
import '../../script/models/script.dart';
import '../../script/services/script_color_inversion_service.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../../core/widgets/global_color_picker.dart';
import '../../../core/widgets/stable_walkthrough_overlay.dart';
import '../../remote/services/remote_control_service.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../../platform/permissions/platform_permissions.dart';
import '../../../platform/stt/abstract_stt_service.dart';

part 'teleprompter_screen.audio_debug_widgets.dart';
part 'teleprompter_screen.session_stt.dart';
part 'teleprompter_screen.manual_scroll.dart';
part 'teleprompter_screen.build.dart';
part 'teleprompter_screen.bookmarks.dart';
part 'teleprompter_screen.search.dart';
part 'teleprompter_screen.control_bar.dart';
part 'teleprompter_screen.walkthrough.dart';
part 'teleprompter_screen.settings_panel.dart';
part 'teleprompter_screen.stt_profile_settings.dart';

// Regex to strip any unprocessed markup tags that somehow leaked into word.raw
final _tagStripRe = RegExp(
    r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg|font|align)(?:=[^\]]+)?\]|\*\*');

class TeleprompterScreen extends ConsumerStatefulWidget {
  final bool showWalkthroughGuide;

  const TeleprompterScreen({super.key, this.showWalkthroughGuide = false});

  @override
  ConsumerState<TeleprompterScreen> createState() => _TeleprompterScreenState();
}

class _TeleprompterScreenState extends ConsumerState<TeleprompterScreen> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _presentationFocusNode =
      FocusNode(debugLabel: 'iOS presentation shortcuts');
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
  bool _controlsAutoHideActive = false;
  int _manualWordIndex = 0;
  bool _manualScrolling = false;
  bool _scrollingBackward = false;
  StreamSubscription? _remoteCmdSub;
  DateTime? _lastVisibleWindowSync;
  bool _visibleWindowSyncScheduled = false;
  bool _userBrowsingWhileStopped = false;
  String? _bookmarkScopeKey;
  String? _bookmarkLoadingKey;
  bool _bookmarksLoaded = false;
  List<ScriptBookmark> _bookmarks = const [];
  bool _searchDialogOpen = false;
  String _lastSearchQuery = '';
  bool _searchWholeWord = false;
  bool _presenterSearchToolbarVisible = false;
  bool _presenterWalkthroughVisible = false;
  int _presenterWalkthroughStep = 0;
  final GlobalKey _presenterSttKey = GlobalKey();
  final GlobalKey _presenterSettingsKey = GlobalKey();
  final GlobalKey _presenterBookmarksKey = GlobalKey();
  final GlobalKey _presenterResetKey = GlobalKey();
  List<_PresenterSearchMatch> _presenterSearchMatches = const [];
  int _presenterSearchMatchIndex = -1;
  bool _resumePromptShown = false;
  late final TeleprompterNotifier _teleprompterNotifier;
  late final RemoteControlService _remoteControlService;
  String? _lastPublishedRemoteScrollMode;
  double? _lastPublishedRemoteScrollSpeed;
  bool? _lastPublishedRemoteScriptActive;
  bool? _lastPublishedRemoteSessionActive;
  bool? _lastPublishedRemoteIsStarting;

  @override
  void initState() {
    super.initState();
    _teleprompterNotifier = ref.read(teleprompterProvider.notifier);
    _remoteControlService = ref.read(remoteControlProvider);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHideControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Defensively stop any lingering session from a previous entry.
        // dispose() of the previous screen calls stopSession(), but the
        // async STT teardown may not have fully completed before this
        // screen's initState fires, leaving the recognizer active.
        _teleprompterNotifier.stopSession();
        _initRemoteListener();
        if (widget.showWalkthroughGuide) {
          _setTeleprompterState(() {
            _presenterWalkthroughVisible = true;
            _presenterWalkthroughStep = 0;
          });
        }
        // Listen for missing language notifications
        ref.listenManual(teleprompterProvider.select((s) => s.missingLanguage),
            (prev, next) {
          if (next != null && next.isNotEmpty && mounted) {
            _showMissingLanguageDialog(next);
          }
        });
        final currentIndex = ref.read(teleprompterProvider).confirmedWordIndex;
        if (currentIndex > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _offerResumeOrRestart(currentIndex);
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _disposeTeleprompterScreenBody();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildTeleprompterScreen(context);

  void _updatePresenterSearchState(VoidCallback update) {
    _setTeleprompterState(update);
  }

  void _setTeleprompterState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  // ── Smooth pixel-based manual scroll ───────────────────────────────────────

  TextAlign _toTextAlign(
      TextAlign? paraAlign, AppSettings settings, bool isRtl) {
    if (paraAlign != null) return paraAlign;
    // v3.8: Source of Truth - If no tag, Hebrew defaults to Right, English to Left
    return isRtl ? TextAlign.right : TextAlign.left;
  }

  WrapAlignment _toWrapAlignment(
      TextAlign? paraAlign, AppSettings settings, bool isRtl) {
    final textAlign = _toTextAlign(paraAlign, settings, isRtl);
    if (textAlign == TextAlign.center) return WrapAlignment.center;

    if (isRtl) {
      // In RTL, Start is Right, End is Left.
      if (textAlign == TextAlign.left) return WrapAlignment.end;
      if (textAlign == TextAlign.right) return WrapAlignment.start;
    } else {
      // In LTR, Start is Left, End is Right.
      if (textAlign == TextAlign.left) return WrapAlignment.start;
      if (textAlign == TextAlign.right) return WrapAlignment.end;
    }

    return WrapAlignment.center;
  }
}

// ── Control bar ────────────────────────────────────────────────────────────────

// ── Settings panel ─────────────────────────────────────────────────────────────
