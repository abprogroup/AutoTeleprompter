part of 'global_selection_overlay.dart';

extension GlobalSelectionOverlayGeometry on GlobalSelectionOverlayState {
  void _updateControllers() {
    final range = _normalizedRange();
    if (range == null) return;

    for (int i = 0; i < widget.controllers.length; i++) {
      final c = widget.controllers[i];
      if (i < range.startBlock || i > range.endBlock) {
        c.isGlobalSelected = false;
        c.externalSelection = const TextSelection.collapsed(offset: 0);
        c.externalVisibleSelection = null;
      } else if (i > range.startBlock && i < range.endBlock) {
        c.isGlobalSelected = true;
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: c.text.length);
        c.externalVisibleSelection = TextSelection(
          baseOffset: 0,
          extentOffset: MarkupDecorationParser.visibleText(c.text).length,
        );
      } else if (i == range.startBlock && i == range.endBlock) {
        c.isGlobalSelected = false;
        final start = range.startOffset < range.endOffset
            ? range.startOffset
            : range.endOffset;
        final end = range.startOffset > range.endOffset
            ? range.startOffset
            : range.endOffset;
        c.externalSelection =
            TextSelection(baseOffset: start, extentOffset: end);
        c.externalVisibleSelection =
            MarkupDecorationParser.rawToVisibleSelection(
          c.text,
          TextSelection(baseOffset: start, extentOffset: end),
        );
      } else if (i == range.startBlock) {
        c.isGlobalSelected = c.text.isEmpty;
        c.externalSelection = TextSelection(
            baseOffset: range.startOffset, extentOffset: c.text.length);
        c.externalVisibleSelection =
            MarkupDecorationParser.rawToVisibleSelection(
          c.text,
          TextSelection(
              baseOffset: range.startOffset, extentOffset: c.text.length),
        );
      } else if (i == range.endBlock) {
        c.isGlobalSelected = c.text.isEmpty;
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: range.endOffset);
        c.externalVisibleSelection =
            MarkupDecorationParser.rawToVisibleSelection(
          c.text,
          TextSelection(baseOffset: 0, extentOffset: range.endOffset),
        );
      }
      c.refresh();
    }
  }

  /// Recalculates handle positions after an external layout change (e.g. alignment
  /// applied to selected text). Must be called after the next frame so the
  /// RenderEditable has been laid out with the new textAlign/textDirection.
  void refreshPositions() {
    if (!hasSelection) {
      setState(() {
        _handleStartPos = null;
        _handleEndPos = null;
      });
      return;
    }

    final startPos = _getPositionInStack(
      _startBlock!,
      _startOffset!,
      endpointA: true,
    );
    final endPos = _getPositionInStack(
      _endBlock!,
      _endOffset!,
      endpointA: false,
    );

    setState(() {
      _handleStartPos = startPos;
      _handleEndPos = endPos;
    });
  }

  Offset? _getPositionInStack(
    int blockIdx,
    int offset, {
    required bool endpointA,
  }) {
    if (blockIdx < 0 || blockIdx >= widget.blockKeys.length) return null;
    final key = widget.blockKeys[blockIdx];
    final renderObj = key.currentContext?.findRenderObject();
    if (renderObj == null) return null;

    final editable = _findRenderEditable(renderObj);
    final ourStack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (ourStack == null) return null;

    if (editable != null) {
      final controller = widget.controllers[blockIdx];
      final safeOffset = offset.clamp(0, controller.text.length).toInt();
      final caretOffset = editable.getLocalRectForCaret(
        TextPosition(offset: safeOffset, affinity: TextAffinity.downstream),
      );
      var endpointX = caretOffset.left;
      var endpointY = caretOffset.top + caretOffset.height / 2;
      final range = _normalizedRange();
      if (range != null) {
        final blockRtl = EditorTextGeometryService.resolveBlockRtl(
          widget.controllers.map((controller) => controller.text).toList(),
          blockIdx,
        );
        final isRangeStart = _endpointIsRangeStart(endpointA);
        final blockTextLength = controller.text.length;
        final selection = blockIdx == range.startBlock &&
                blockIdx == range.endBlock
            ? TextSelection(
                baseOffset: range.startOffset.clamp(0, blockTextLength).toInt(),
                extentOffset: range.endOffset.clamp(0, blockTextLength).toInt(),
              )
            : blockIdx == range.startBlock
                ? TextSelection(
                    baseOffset:
                        range.startOffset.clamp(0, blockTextLength).toInt(),
                    extentOffset: blockTextLength,
                  )
                : blockIdx == range.endBlock
                    ? TextSelection(
                        baseOffset: 0,
                        extentOffset:
                            range.endOffset.clamp(0, blockTextLength).toInt(),
                      )
                    : TextSelection(
                        baseOffset: 0, extentOffset: blockTextLength);
        final paintedEndpoint = _paintedSelectionEndpoint(
          editable,
          selection,
          isRangeStart: isRangeStart,
        );
        if (paintedEndpoint != null) {
          endpointX = paintedEndpoint.dx;
          endpointY = paintedEndpoint.dy;
        } else {
          final endpoints = editable.getEndpointsForSelection(selection);
          if (endpoints.isNotEmpty) {
            final endpoint = blockRtl
                ? _rtlSelectionEndpoint(endpoints, isRangeStart: isRangeStart)
                : (isRangeStart ? endpoints.first : endpoints.last);
            endpointX = endpoint.point.dx;
            endpointY = endpoint.point.dy;
          }
        }
      }
      final anchor = Offset(
        endpointX,
        endpointY,
      );
      return editable.localToGlobal(anchor, ancestor: ourStack);
    }

    final box = renderObj as RenderBox;
    return box.localToGlobal(Offset.zero, ancestor: ourStack);
  }

  Offset? _paintedSelectionEndpoint(
    RenderEditable editable,
    TextSelection selection, {
    required bool isRangeStart,
  }) {
    return MarkupRenderEditableGeometry.endpointForSelection(
      editable,
      selection,
      isRangeStart: isRangeStart,
    );
  }

  TextSelectionPoint _rtlSelectionEndpoint(
    List<TextSelectionPoint> endpoints, {
    required bool isRangeStart,
  }) {
    const lineTolerance = 4.0;
    if (endpoints.length == 1) return endpoints.single;
    final sortedByLine = [...endpoints]..sort((a, b) {
        final yCompare = a.point.dy.compareTo(b.point.dy);
        if (yCompare != 0) return yCompare;
        return a.point.dx.compareTo(b.point.dx);
      });
    final anchorY =
        isRangeStart ? sortedByLine.first.point.dy : sortedByLine.last.point.dy;
    final sameLine = sortedByLine
        .where(
            (endpoint) => (endpoint.point.dy - anchorY).abs() <= lineTolerance)
        .toList();
    if (sameLine.isEmpty) {
      return isRangeStart ? sortedByLine.first : sortedByLine.last;
    }
    sameLine.sort((a, b) => a.point.dx.compareTo(b.point.dx));
    return isRangeStart ? sameLine.last : sameLine.first;
  }

  Offset _handleVisualCenter(Offset caret, bool _) {
    return caret;
  }

  /// v4.0.8: Called after a style command mutates text so that _startOffset /
  /// _endOffset stay in sync with the new externalSelection positions set by
  /// wrapSelection.  Each affected controller already has its externalSelection
  /// updated to the post-insert range before this method is called.
  void syncOffsetsFromExternalSelection(List<MarkupController> controllers) {
    if (_startBlock == null || _endBlock == null) return;
    if (_startBlock! < controllers.length) {
      final c = controllers[_startBlock!];
      if (c.externalSelection != null &&
          c.externalSelection!.isValid &&
          !c.externalSelection!.isCollapsed) {
        _startOffset = c.externalSelection!.start;
      }
    }
    if (_endBlock! < controllers.length) {
      final c = controllers[_endBlock!];
      if (c.externalSelection != null &&
          c.externalSelection!.isValid &&
          !c.externalSelection!.isCollapsed) {
        _endOffset = c.externalSelection!.end;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refreshPositions();
    });
  }

  void _updateBlockHighlights() {
    if (_startBlock == null ||
        _endBlock == null ||
        _startOffset == null ||
        _endOffset == null) {
      return;
    }

    // Ensure start is before end
    int sB = _startBlock!, eB = _endBlock!;
    int sO = _startOffset!, eO = _endOffset!;
    if (sB > eB || (sB == eB && sO > eO)) {
      final tB = sB;
      sB = eB;
      eB = tB;
      final tO = sO;
      sO = eO;
      eO = tO;
    }

    for (int i = 0; i < widget.controllers.length; i++) {
      final c = widget.controllers[i];
      if (i < sB || i > eB) {
        // Use a collapsed (non-null) selection to explicitly suppress any
        // highlight. Setting null would fall through to the native
        // controller.selection, which may still hold a range from a prior
        // user gesture and would show a stale amber highlight.
        c.externalSelection = const TextSelection.collapsed(offset: 0);
      } else if (i == sB && i == eB) {
        c.externalSelection = TextSelection(baseOffset: sO, extentOffset: eO);
      } else if (i == sB) {
        c.externalSelection =
            TextSelection(baseOffset: sO, extentOffset: c.text.length);
      } else if (i == eB) {
        c.externalSelection = TextSelection(baseOffset: 0, extentOffset: eO);
      } else {
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: c.text.length);
      }
    }
  }

  bool? _nearestHandleForPointer(Offset globalPos, {required bool fallback}) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return fallback;

    double? distanceTo(Offset? caret, bool endpointA) {
      if (caret == null) return null;
      final center = _handleVisualCenter(caret, endpointA);
      final globalCenter = stackBox.localToGlobal(center);
      final delta = globalCenter - globalPos;
      return delta.dx * delta.dx + delta.dy * delta.dy;
    }

    final startDistance = distanceTo(_handleStartPos, true);
    final endDistance = distanceTo(_handleEndPos, false);
    if (startDistance == null && endDistance == null) return fallback;
    if (startDistance == null) return false;
    if (endDistance == null) return true;
    return startDistance <= endDistance;
  }

  void _enterRefineMode() {
    if (!_isWholeScriptSelected) return;
    for (final c in widget.controllers) {
      c.isGlobalSelected = false;
      c.refresh(); // repaint TextFields immediately so isGlobalSelected=false takes effect
    }
    widget.onSelectionChanged();
    // Note: native controller.selection is intentionally NOT collapsed here.
    // selectionColor is always transparent (set in _EditorBlock), so RenderEditable
    // never paints its own amber regardless of native selection state.
    // Collapsing native selection was causing _getPositionForPoint() to misreport
    // positions on the second visual line of wrapped text blocks (multi-line drag bug).
  }
}
