import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../../settings/models/app_settings.dart';
import '../../../services/editor_text_geometry_service.dart';
import '../../../services/markup_decoration_service.dart';
import '../markup_controller.dart';

part 'global_selection_overlay.handles.dart';
part 'global_selection_overlay.selection.dart';
part 'global_selection_overlay.body_drag.dart';
part 'global_selection_overlay.geometry.dart';
part 'global_selection_overlay.build.dart';

/// Walk a render tree to find the first RenderEditable.
RenderEditable? _findRenderEditable(RenderObject obj) {
  if (obj is RenderEditable) return obj;
  RenderEditable? result;
  obj.visitChildren((child) {
    result ??= _findRenderEditable(child);
  });
  return result;
}

// Drag-handle autoscroll constants shared by the split overlay parts.
const double _autoScrollZone = 60.0;
const double _autoScrollMax = 40.0;
const double _handleHitWidth = 40.0;
const double _handleHitHeight = 56.0;
const double _handleBarWidth = 6.0;
const double _handleBarHeight = 40.0;
const double _hardExitMargin = 80.0;
const Duration _stalePointerTimeout = Duration(milliseconds: 2500);

enum SelectionSessionMode {
  none,
  overlaySelection,
  handleDrag,
  keyboardExtend,
}

enum SelectionPointerState {
  inside,
  edgeZone,
  outside,
  stale,
}

class SelectionEndpoint {
  final int block;
  final int offset;

  const SelectionEndpoint({required this.block, required this.offset});

  @override
  String toString() => '$block:$offset';
}

class SelectionSessionSnapshot {
  final SelectionSessionMode mode;
  final SelectionPointerState pointerState;
  final SelectionEndpoint endpointA;
  final SelectionEndpoint endpointB;
  final SelectionEndpoint anchor;
  final SelectionEndpoint focus;
  final bool focusEndpointIsA;

  const SelectionSessionSnapshot({
    required this.mode,
    required this.pointerState,
    required this.endpointA,
    required this.endpointB,
    required this.anchor,
    required this.focus,
    required this.focusEndpointIsA,
  });
}

class _HandleDragSession {
  final bool activeEndpointIsStart;
  final Offset panStartPointerGlobal;
  final Offset? panStartHandleGlobal;
  Offset latestPointerGlobal;
  Offset latestHandleGlobal;
  Offset? lastEndpointPointerGlobal;
  SelectionPointerState pointerState = SelectionPointerState.inside;
  Timer? autoScrollTimer;
  Timer? staleTimer;

  _HandleDragSession({
    required this.activeEndpointIsStart,
    required this.panStartPointerGlobal,
    required this.panStartHandleGlobal,
    required this.latestPointerGlobal,
    required this.latestHandleGlobal,
  });

  Offset handleGlobalForPointer(Offset pointerGlobal) {
    final handleStart = panStartHandleGlobal;
    if (handleStart == null) return pointerGlobal;
    return handleStart + (pointerGlobal - panStartPointerGlobal);
  }

  void cancelAutoScroll() {
    autoScrollTimer?.cancel();
    autoScrollTimer = null;
  }

  void cancelStale() {
    staleTimer?.cancel();
    staleTimer = null;
  }

  void cancelTimers() {
    cancelAutoScroll();
    cancelStale();
  }
}

/// v3.9.5.66: Global Multi-Paragraph Selection Manager
/// Coordinates drag-handles and selection highlights across independent TextField blocks.
class GlobalSelectionOverlay extends StatefulWidget {
  final List<MarkupController> controllers;
  final List<GlobalKey> blockKeys;
  final AppSettings settings;
  final Widget child;
  final VoidCallback onSelectionChanged;

  /// Editor scroll controller. When provided, dragging a selection handle
  /// near the top or bottom of the viewport automatically scrolls the list,
  /// letting users extend selections beyond the visible area.
  final ScrollController? scrollController;

  const GlobalSelectionOverlay({
    super.key,
    required this.controllers,
    required this.blockKeys,
    required this.settings,
    required this.child,
    required this.onSelectionChanged,
    this.scrollController,
  });

  @override
  State<GlobalSelectionOverlay> createState() => GlobalSelectionOverlayState();
}

class GlobalSelectionOverlayState extends State<GlobalSelectionOverlay> {
  // Global selection state
  int? _startBlock, _endBlock;
  int? _startOffset, _endOffset;

  // Interaction state
  bool _isSelecting = false;
  Offset? _handleStartPos, _handleEndPos;
  Size _stackSize = Size.zero;
  _HandleDragSession? _handleDrag;
  bool _ignoreBodyDragUntilPointerUp = false;
  bool _focusEndpointIsStart = false;
  SelectionSessionMode _sessionMode = SelectionSessionMode.none;
  SelectionPointerState _pointerState = SelectionPointerState.inside;

  // Anchor state for body-drag to prevent jumping
  int? _anchorBlock;
  int? _anchorOffset;

  final GlobalKey _stackKey = GlobalKey();

  int? _candidateBlock;
  int? _candidateOffset;
  Offset? _candidatePos;
  Timer? _bodyAutoScrollTimer;
  bool _bodyDragActive = false;
  Offset? _latestBodyDragGlobal;

  @override
  void dispose() {
    _discardHandleDragSession();
    _stopBodyAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildOverlay(context);
}
