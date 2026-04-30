import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/teleprompter_provider.dart';
import '../../script/providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../script/models/script_word.dart';
import '../../script/models/script.dart';
import '../../../core/widgets/global_color_picker.dart';
import '../../remote/services/remote_control_service.dart';
import '../../../platform/permissions/platform_permissions.dart';

part 'teleprompter_screen.session_stt.dart';
part 'teleprompter_screen.manual_scroll.dart';
part 'teleprompter_screen.build.dart';
part 'teleprompter_screen.control_bar.dart';
part 'teleprompter_screen.settings_panel.dart';

const _systemChannel = MethodChannel('autoteleprompter/system');

// Regex to strip any unprocessed markup tags that somehow leaked into word.raw
final _tagStripRe = RegExp(
    r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg|font|align)(?:=[^\]]+)?\]|\*\*');

class TeleprompterScreen extends ConsumerStatefulWidget {
  const TeleprompterScreen({super.key});

  @override
  ConsumerState<TeleprompterScreen> createState() => _TeleprompterScreenState();
}

class _TeleprompterScreenState extends ConsumerState<TeleprompterScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _wordKeys = [];
  bool _controlsVisible = true;
  Timer? _manualScrollTimer;
  Timer? _wordTrackTimer;
  Timer? _hideControlsTimer;
  Timer? _smoothScrollTimer;
  double _scrollTarget = 0.0;
  bool _smoothScrollActive = false;
  int _manualWordIndex = 0;
  bool _manualScrolling = false;
  bool _scrollingBackward = false;
  StreamSubscription? _remoteCmdSub;
  // Item 3: visible-word-window sync state for opt-in visible-skip aligner.
  DateTime? _lastVisibleWindowSync;
  bool _visibleWindowSyncScheduled = false;
  // Item 5: tracks user drag-scroll while STT is stopped so a scroll-end can
  // sync the resume point. Must stay false while STT is listening or starting
  // (Item 4 scroll-lock contract).
  bool _userBrowsingWhileStopped = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHideControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Defensively stop any lingering session from a previous entry.
        // dispose() of the previous screen calls stopSession(), but the
        // async STT teardown may not have fully completed before this
        // screen's initState fires, leaving the recognizer active.
        ref.read(teleprompterProvider.notifier).stopSession();
        _initRemoteListener();
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
            if (mounted) _scrollToWordIndex(currentIndex);
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

  // ── Smooth pixel-based manual scroll ───────────────────────────────────────

  @override
  TextAlign _toTextAlign(
      TextAlign? paraAlign, AppSettings settings, bool isRtl) {
    if (paraAlign != null) return paraAlign;
    // v3.8: Source of Truth - If no tag, Hebrew defaults to Right, English to Left
    return isRtl ? TextAlign.right : TextAlign.left;
  }

  Alignment _toAlignment(
      TextAlign? paraAlign, AppSettings settings, bool isRtl) {
    final textAlign = _toTextAlign(paraAlign, settings, isRtl);
    if (textAlign == TextAlign.center) return Alignment.center;

    if (textAlign == TextAlign.right) return Alignment.centerRight;
    if (textAlign == TextAlign.left) return Alignment.centerLeft;

    // Default fallback
    return Alignment.center;
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

  WrapAlignment _parseWrapAlignment(String align, bool isRtl) {
    if (isRtl) {
      switch (align) {
        case 'right':
          return WrapAlignment.start;
        case 'left':
          return WrapAlignment.end;
        default:
          return WrapAlignment.center;
      }
    }
    switch (align) {
      case 'left':
        return WrapAlignment.start;
      case 'right':
        return WrapAlignment.end;
      default:
        return WrapAlignment.center;
    }
  }
}

// ── Control bar ────────────────────────────────────────────────────────────────

// ── Settings panel ─────────────────────────────────────────────────────────────
