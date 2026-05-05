import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/teleprompter_provider.dart';
import '../../script/providers/script_provider.dart';
import '../../script/models/script.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../script/services/markup_decoration_service.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../../core/widgets/global_color_picker.dart';
import '../../remote/services/remote_control_service.dart';
import '../../../platform/permissions/platform_permissions.dart';
import '../../../platform/stt/abstract_stt_service.dart';

part 'teleprompter_screen.session_stt.dart';
part 'teleprompter_screen.manual_scroll.dart';
part 'teleprompter_screen.bookmarks_search.dart';
part 'teleprompter_screen.smooth_settings.dart';
part 'teleprompter_screen.build.dart';
part 'teleprompter_screen.alignment_helpers.dart';
part 'teleprompter_screen.audio_debug_widgets.dart';
part 'teleprompter_screen.control_bar.dart';
part 'teleprompter_screen.settings_panel.dart';
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
  final List<GlobalKey> _wordKeys = [];
  bool _controlsVisible = true;
  bool _debugConsoleMinimized = false;
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
  DateTime? _lastVisibleWindowSync;
  bool _controlsHovering = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handlePresentationKey);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHideControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initRemoteListener();
        ref.listenManual(teleprompterProvider.select((s) => s.missingLanguage),
            (prev, next) {
          if (next != null && next.isNotEmpty && mounted)
            _showMissingLanguageDialog(next);
        });
        ref.listenManual(
            teleprompterProvider.select((s) => s.isListening || s.isStarting),
            (prev, next) {
          if (!mounted) return;
          _syncControlsForSpeech(next);
        });
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _manualScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
    _hideControlsTimer?.cancel();
    _smoothScrollTimer?.cancel();
    _scrollController.dispose();
    _remoteCmdSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildTeleprompterScreen(context);
}
