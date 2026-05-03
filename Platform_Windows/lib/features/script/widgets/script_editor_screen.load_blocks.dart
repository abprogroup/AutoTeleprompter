part of 'script_editor_screen.dart';

extension _ScriptEditorLoadBlockParts on _ScriptEditorScreenState {
  Future<void> _runPendingFileLoad(File file) async {
    try {
      final settings = ref.read(settingsProvider);
      _lastChosenTextColor = Color(settings.lastTextColor);
      _lastChosenHighlightColor = Color(settings.lastHighlightColor);

      await ref.read(settingsProvider.notifier).resetToDefaultAppearance();
      final result = await ref.read(scriptProvider.notifier).parseFile(file);
      final String content = result.text;
      final String title = file.path.split(RegExp(r'[\\/]')).last;

      // Conflict Detection Logic
      String? existingMeta;
      final List<String> recentScripts =
          ref.read(settingsProvider).recentScripts;
      String normalize(String? t) => (t ?? '').replaceAll('\r', '').trim();
      final String normalizedNew = normalize(content);

      for (final meta in recentScripts) {
        try {
          final decoded = jsonDecode(meta);
          if (decoded['title'] == title) {
            existingMeta = meta;
            break;
          }
        } catch (_) {}
      }

      String finalContent = content;
      String finalType = title.split('.').last.toUpperCase();
      String? finalSessionId;
      String? finalHistoryJson;

      if (existingMeta != null) {
        final decoded = jsonDecode(existingMeta);
        final String existingContent = decoded['fullText'] ?? '';
        final String sessionId = decoded['sessionId'];
        final String type = decoded['type'] ?? 'TXT';

        if (normalize(existingContent) == normalizedNew) {
          finalContent = existingContent;
          finalType = type;
          finalSessionId = sessionId;
          finalHistoryJson = decoded['historyJson'];
        } else {
          if (!mounted) return;
          final choice = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFFFBF00), size: 22),
                SizedBox(width: 10),
                Text("Conflict Detected",
                    style: TextStyle(color: Colors.white, fontSize: 17)),
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('"$title" is already in your Recents.',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                      'The version on your disk is different from the version in your history. What do you want to do?',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text("KEEP HISTORY",
                      style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, 'reload'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFBF00),
                      foregroundColor: Colors.black),
                  child: const Text("RELOAD & DISCARD EDITS",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );

          if (choice == 'reload') {
            finalType = type;
            finalSessionId = sessionId;
          } else if (choice == 'cancel') {
            finalContent = existingContent;
            finalType = type;
            finalSessionId = sessionId;
            finalHistoryJson = decoded['historyJson'];
          } else {
            if (mounted) Navigator.pop(context);
            return;
          }
        }
      }

      if (!mounted) return;
      _currentTitle = title;
      _sourceType = finalType;
      _currentSessionId = finalSessionId ?? _currentSessionId;
      _loadText(finalContent);
      unawaited(_loadBookmarksForCurrentScript());

      if (finalHistoryJson != null) {
        try {
          final List<dynamic> historyData = jsonDecode(finalHistoryJson);
          _history.clear();
          _history.addAll(historyData.map((d) => EditorState.fromJson(d)));
          _historyIndex = _history.length - 1;
          if (_history.isNotEmpty) _applyState(_history.last);
        } catch (_) {}
      } else {
        _saveHistory(description: 'Import');
      }
      _forceRecentUpdate();
    } finally {
      if (mounted) setState(() => _isPendingLoad = false);
    }
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final text = _getRefinedFullTextWithoutBookmarkSigns();
      if (text.isEmpty && _currentTitle == 'New Project') return;
      try {
        _forceRecentUpdate();
      } catch (_) {}
    });
  }

  void _clearControllers() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _controllers.clear();
    _focusNodes.clear();
    _blockKeys.clear();
  }

  void _addBlock(int index, {String text = ''}) {
    setState(() {
      final controller = MarkupController(text: text);
      final blockKey = GlobalKey(); // v3.9.5.66

      final node = FocusNode(onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent)
          return KeyEventResult.ignored;

        // Arrow-key cross-block navigation is owned entirely by the screen-level
        // Focus (_handleEditorArrowKey). Handling arrows here via requestFocus()
        // caused a race condition: requestFocus() is async, so multiple KeyRepeat
        // events arrived at the old block before focus transferred, each trying to
        // jump one more block. The screen-level handler avoids this by updating
        // _lastFocusedController synchronously before requestFocus(), so
        // subsequent events use the new controller even during the async transition.
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          final idx = _controllers.indexOf(controller);
          final text = controller.text;
          final sel = controller.selection;
          if (sel.isValid) {
            final before = text.substring(0, sel.start);
            final after = text.substring(sel.start);
            controller.text = before;
            _addBlock(idx + 1, text: after);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && idx + 1 < _focusNodes.length) {
                _focusNodes[idx + 1].requestFocus();
                _controllers[idx + 1].selection =
                    const TextSelection.collapsed(offset: 0);
              }
            });
          }
          _saveHistory(description: 'Split Paragraph');
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.backspace &&
            controller.text.isEmpty) {
          final idx = _controllers.indexOf(controller);
          if (_controllers.length > 1 && idx != -1) {
            setState(() {
              _controllers.removeAt(idx).dispose();
              _focusNodes.removeAt(idx).dispose();
              _blockKeys.removeAt(idx);
              if (idx > 0) _focusNodes[idx - 1].requestFocus();
            });
            _saveHistory(description: 'Delete Empty Line');
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      });

      node.addListener(() {
        if (node.hasFocus) {
          _lastFocusedController = controller;
          // Restore native-selection rendering on focus regain by clearing
          // any externalSelection sentinel set during focus loss.
          if (controller.externalSelection != null &&
              !_isGlobalSelection &&
              !(_overlayKey.currentState?.hasSelection ?? false)) {
            controller.externalSelection = null;
            controller.refresh();
          }
          _onSelectionChanged();
        } else {
          if (_isDirty && !_isCommandExecuting) {
            // Flush any pending typing bulk on focus loss
            if (_typingCharCount > 0) {
              _commitHistory('Edit Text');
            }
            _isDirty = false;
          }
          // On focus loss, suppress any lingering native selection highlight
          // (set via TextField drag-select). MarkupController otherwise falls
          // through to controller.selection and renders amber on the now-
          // unfocused block — which is the "two highlights at once" bug.
          // Skip while a global multi-block selection or overlay drag is active
          // (their externalSelection values must not be overwritten here).
          final overlayActive = _overlayKey.currentState?.hasSelection ?? false;
          if (!_isGlobalSelection &&
              !overlayActive &&
              !controller.isGlobalSelected &&
              !controller.selection.isCollapsed) {
            controller.externalSelection =
                const TextSelection.collapsed(offset: 0);
            controller.refresh();
          }
        }
      });

      String lastText = text;
      controller.addListener(() {
        if (_isLoading) return;
        if (controller.text == lastText) {
          if (node.hasFocus) {
            _lastSelection = controller.selection;
            if (!controller.selection.isCollapsed) {
              _preservedSelection = controller.selection;
            }
            _onSelectionChanged();
            // Escalate native full-block select to global Select All.
            // Catches all paths: context menu, keyboard, platform menu.
            // Skip when overlay has active handles (refine mode) to avoid
            // infinite loop: refine clears isGlobal → escalation re-selects → loop.
            final overlayActive =
                _overlayKey.currentState?.hasSelection ?? false;
            if (!_isGlobalSelection &&
                !_isCommandExecuting &&
                !overlayActive &&
                !HardwareKeyboard.instance.isShiftPressed &&
                controller.text.isNotEmpty &&
                controller.selection.baseOffset == 0 &&
                controller.selection.extentOffset == controller.text.length) {
              _selectAllBlocks();
            }
          }
          return;
        }
        lastText = controller.text;
        _isDirty = true;
        // v4.1.2: When the user edits text (not inside a style command), clear
        // any pinned externalSelection so stale amber doesn't linger after typing.
        if (!_isCommandExecuting && controller.externalSelection != null) {
          controller.externalSelection = null;
          controller.refresh();
        }
        _onBlockChanged();
      });

      _controllers.insert(index, controller);
      _focusNodes.insert(index, node);
      _blockKeys.insert(index, blockKey);
    });

    if (text.isEmpty) {
      Future.delayed(Duration.zero, () => _focusNodes[index].requestFocus());
    }
  }

  void _removeBlock(int index) {
    if (_controllers.length <= 1) return;
    setState(() {
      _controllers[index].dispose();
      _focusNodes[index].dispose();
      _controllers.removeAt(index);
      _focusNodes.removeAt(index);
      _blockKeys.removeAt(index);
    });
  }

  void _loadText(String text) {
    _isLoading = true;
    try {
      _clearControllers();
      final paragraphs = text.split('\n');
      for (int i = 0; i < paragraphs.length; i++)
        _addBlock(i, text: paragraphs[i]);
      if (_controllers.isEmpty) _addBlock(0);
    } finally {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _isLoading = false;
      });
    }
    // Sync toolbar state after load. Non-empty blocks don't auto-request focus,
    // so _onSelectionChanged never fires — cursorStyleProvider stays at its
    // default 'left'. Point lastFocusedController at the first block so
    // _detectAlignAtCursor reads the right text, then run detection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controllers.isNotEmpty) _lastFocusedController = _controllers.first;
      _onSelectionChanged();
    });
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    final controller = _activeController;
    if (controller != null) {
      // v3.9.5.1: Synchronize selection with status broadcast logic
      // Only reset Global Selection if a manual PARTIAL selection occurs.
      // If the selection is collapsed (cursor) or spans the whole block, keep the flag.
      if (_isGlobalSelection && !_isCommandExecuting) {
        // Keep global selection only if the active block is still fully selected
        // (i.e. the notification came from our own _selectAllBlocks).
        // Any other selection state (collapsed tap, partial drag) clears it.
        // Guard: if the overlay has active handles (e.g. alignment was just applied
        // or drag is in progress), do NOT clear — focus events fire before
        // _isCommandExecuting is set and would prematurely destroy the selection.
        if (_overlayKey.currentState?.hasSelection ?? false) return;
        final textLen = controller.text.length;
        final isFullBlock = !controller.selection.isCollapsed &&
            controller.selection.start == 0 &&
            controller.selection.end == textLen;
        if (!isFullBlock) {
          _clearGlobalSelection();
        }
      }

      // Defer provider update to avoid "modified during build" errors
      // when _onSelectionChanged is triggered from controller listeners
      // during setState callbacks.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final settings = ref.read(settingsProvider);
        final styles = CursorStyle(
          isBold: _detectStyleAtCursor('**', '**'),
          isItalic: _detectStyleAtCursor('[i]', '[/i]'),
          isUnderline: _detectStyleAtCursor('[u]', '[/u]'),
          fontSize: _detectIntAtCursor('size=', settings.fontSize.toInt()),
          fontFamily: _detectStringAtCursor('font=', 'Inter'),
          textAlign: _detectAlignAtCursor(),
          textColor: _detectColorAtCursor(textColor: true),
          highlightColor: _detectColorAtCursor(textColor: false),
        );
        ref.read(cursorStyleProvider.notifier).state = styles;
      });
    }
  }

  void _scheduleRecentUpdate() {
    _recentTimer?.cancel();
    _recentTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _forceRecentUpdate();
    });
  }

  Future<void> _forceRecentUpdate() async {
    _recentTimer?.cancel();
    final text = _getRefinedFullTextWithoutBookmarkSigns();
    if (text.trim().isEmpty) return;
    final settings = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).saveScript(
          text,
          title: _currentTitle,
          type: _sourceType,
          historyIndex: _historyIndex,
          sessionId: _currentSessionId,
          fontSize: settings.fontSize,
          fontFamily: settings.fontFamily,
          lineSpacing: settings.lineSpacing,
          letterSpacing: settings.letterSpacing,
          wordSpacing: settings.wordSpacing,
          textAlign: settings.textAlign,
          scriptBgColor: settings.scriptBgColor,
          currentWordColor: settings.currentWordColor,
          futureWordColor: settings.futureWordColor,
          historyJson: jsonEncode(_history.map((e) => e.toJson()).toList()),
        );
    // Keep scriptProvider.state in sync so that a new ScriptEditorScreen
    // (created on re-entry after navigating away) reads the correct
    // historyIndex and historyJson rather than stale startup values.
    if (mounted) {
      ref.read(scriptProvider.notifier).updateHistory(
            _historyIndex,
            jsonEncode(_history.map((e) => e.toJson()).toList()),
          );
    }
  }

  void _onBlockChanged() {
    if (_isCleaning || _isCommandExecuting) return;
    _saveHistory(description: 'Edit Text', debounce: true);
    _scheduleRecentUpdate();
  }

  Color? _detectColorAtCursor({required bool textColor, int? offset}) {
    final controller = _activeController;
    if (controller == null) return null;
    final text = controller.text;
    final off = offset ?? controller.selection.start;
    final tag = textColor ? '[color=' : '[bg=';
    final closeTag = textColor ? '[/color]' : '[/bg]';
    final matches = RegExp(RegExp.escape(tag) + r'([^\]]+)\]').allMatches(text);
    Color? found;
    for (final m in matches) {
      if (m.start <= off) {
        final nextClose = text.indexOf(closeTag, m.end);
        if (nextClose == -1 || nextClose >= off) {
          final hex = m.group(1)!.trim().replaceFirst('#', '');
          found = Color(int.tryParse('FF$hex', radix: 16) ??
              (textColor ? 0xFFFFFFFF : 0x00000000));
        }
      }
    }
    return found ?? const Color(0x00000000);
  }

  String _detectAlignAtCursor({int? offset}) {
    final controller = _activeController;
    if (controller == null) return 'left';
    final text = controller.text;
    // Clamp to 0 when selection is invalid (e.g. focus moved to layout suite).
    // Alignment tags always wrap from position 0 so scanning at 0 is correct.
    final rawOff = offset ?? controller.selection.baseOffset;
    final off = rawOff.clamp(0, text.isEmpty ? 0 : text.length);
    final alignMatches =
        RegExp(r'\[(?:align=)?(center|left|right)\]').allMatches(text);
    final dirMatches = RegExp(r'\[(rtl|ltr)\]').allMatches(text);
    String found = 'left';
    for (final m in alignMatches) {
      if (m.start <= off) {
        final val = m.group(1)!;
        // Use the correct close tag depending on whether the opening was
        // old-format [right] or new-format [align=right].
        final isNewFormat = m.group(0)!.startsWith('[align=');
        final closeTag = isNewFormat ? '[/align=$val]' : '[/$val]';
        final nextClose = text.indexOf(closeTag, m.end);
        if (nextClose == -1 || nextClose >= off) found = val;
      }
    }
    if (found == 'left') {
      for (final m in dirMatches) {
        if (m.start <= off) {
          final nextClose = text.indexOf('[/${m.group(1)}]', m.end);
          if (nextClose == -1 || nextClose >= off) if (m.group(1) == 'rtl')
            found = 'right';
        }
      }
    }
    // Mirror the editor's own auto-RTL rule: if no explicit tag was found but
    // the text is predominantly Hebrew, treat it as right-aligned.
    if (found == 'left' && text.isHebrew) found = 'right';
    return found;
  }

  bool _detectStyleAtCursor(String open, String close, {int? offset}) {
    final controller = _activeController;
    if (controller == null) return false;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final mid = (start + (end - start) / 2).floor().clamp(0, text.length);
    bool isPointActive(int off) =>
        _detectStyleAtPoint(text, selection, off, open, close);
    if (selection.isCollapsed) return isPointActive(selection.baseOffset);
    return isPointActive(start) || isPointActive(end) || isPointActive(mid);
  }

  int _detectIntAtCursor(String prefix, int defaultValue) {
    final controller = _activeController;
    if (controller == null) return defaultValue;
    final text = controller.text;
    final selection = controller.selection;
    int valAtPoint(int off) =>
        _detectIntAtPoint(text, selection, off, prefix, defaultValue);
    if (selection.isCollapsed) return valAtPoint(selection.baseOffset);
    final mid = (selection.start + (selection.end - selection.start) / 2)
        .floor()
        .clamp(0, text.length);
    final vMid = valAtPoint(mid);
    if (vMid != defaultValue) return vMid;
    return valAtPoint(selection.start);
  }

  String _detectStringAtCursor(String prefix, String defaultValue) {
    final controller = _activeController;
    if (controller == null) return defaultValue;
    final text = controller.text;
    final selection = controller.selection;
    String valAtPoint(int off) =>
        _detectStringAtPoint(text, selection, off, prefix, defaultValue);
    if (selection.isCollapsed) return valAtPoint(selection.baseOffset);
    final mid = (selection.start + (selection.end - selection.start) / 2)
        .floor()
        .clamp(0, text.length);
    final vMid = valAtPoint(mid);
    if (vMid != defaultValue) return vMid;
    return valAtPoint(selection.start);
  }

  bool _detectStyleAtPoint(String text, TextSelection selection, int off,
      String open, String close) {
    if (off < 0 || off > text.length) return false;
    bool check(int p) {
      if (p < 0 || p > text.length) return false;
      if (open == '**' && close == '**') {
        final subText = text.substring(0, p);
        final count = RegExp(r'\*\*').allMatches(subText).length;
        return count % 2 != 0;
      }
      final tagIdx = text.lastIndexOf(open, p);
      if (tagIdx == -1) return false;
      final exitIdx = text.indexOf(close, tagIdx + open.length);
      return exitIdx != -1 && exitIdx >= p;
    }

    // Check at cursor, one back, and several nearby positions to handle
    // landing on invisible tag characters (fontSize: 0.1 in MarkupController)
    if (check(off)) return true;
    for (int delta = 1; delta <= open.length + 2; delta++) {
      if (off - delta >= 0 && check(off - delta)) return true;
      if (off + delta <= text.length && check(off + delta)) return true;
    }
    return false;
  }

  int _detectIntAtPoint(String text, TextSelection selection, int off,
      String prefix, int defaultValue) {
    final openTag = '[' + prefix;
    int check(int p) {
      if (p < 0 || p > text.length) return defaultValue;
      final tagIdx = text.lastIndexOf(openTag, p);
      if (tagIdx == -1) return defaultValue;
      final closeBracket = text.indexOf(']', tagIdx);
      if (closeBracket == -1 || closeBracket > p) return defaultValue;
      final tagName = prefix.split('=').first;
      final closeTag = '[/' + tagName + ']';
      final exitIdx = text.indexOf(closeTag, tagIdx);
      if (exitIdx != -1 && exitIdx < p) return defaultValue;
      if (exitIdx == -1) return defaultValue;
      return int.tryParse(
              text.substring(tagIdx + openTag.length, closeBracket)) ??
          defaultValue;
    }

    final atBoundary = check(off);
    if (atBoundary != defaultValue) return atBoundary;
    // Search nearby positions to handle cursor landing on tag characters
    for (int delta = 1; delta <= openTag.length + 2; delta++) {
      if (off - delta >= 0) {
        final v = check(off - delta);
        if (v != defaultValue) return v;
      }
      if (off + delta <= text.length) {
        final v = check(off + delta);
        if (v != defaultValue) return v;
      }
    }
    return defaultValue;
  }

  String _detectStringAtPoint(String text, TextSelection selection, int off,
      String prefix, String defaultValue) {
    final openTag = '[' + prefix;
    String check(int p) {
      if (p < 0 || p > text.length) return defaultValue;
      final tagIdx = text.lastIndexOf(openTag, p);
      if (tagIdx == -1) return defaultValue;
      final closeBracket = text.indexOf(']', tagIdx);
      if (closeBracket == -1 || closeBracket > p) return defaultValue;
      final tagName = prefix.split('=').first;
      final closeTag = '[/' + tagName + ']';
      final exitIdx = text.indexOf(closeTag, tagIdx);
      if (exitIdx != -1 && exitIdx < p) return defaultValue;
      if (exitIdx == -1) return defaultValue;
      return text.substring(tagIdx + openTag.length, closeBracket);
    }

    final atBoundary = check(off);
    if (atBoundary != defaultValue) return atBoundary;
    // Search nearby positions to handle cursor landing on tag characters
    for (int delta = 1; delta <= openTag.length + 2; delta++) {
      if (off - delta >= 0) {
        final v = check(off - delta);
        if (v != defaultValue) return v;
      }
      if (off + delta <= text.length) {
        final v = check(off + delta);
        if (v != defaultValue) return v;
      }
    }
    return defaultValue;
  }

  _VerticalLayoutInfo _getVerticalLayout(
    int index, {
    TextSelection? selection,
  }) {
    final controller = _controllers[index];
    final settings = ref.read(settingsProvider);
    final isRtl = controller.text.isHebrew;

    // 1. Determine alignment
    TextAlign textAlign = isRtl ? TextAlign.right : TextAlign.left;
    if (RegExp(r'\[(?:align=)?center\]').hasMatch(controller.text)) {
      textAlign = TextAlign.center;
    } else if (RegExp(r'\[(?:align=)?right\]').hasMatch(controller.text)) {
      textAlign = TextAlign.right;
    } else if (RegExp(r'\[(?:align=)?left\]').hasMatch(controller.text)) {
      textAlign = TextAlign.left;
    }

    // 2. Build style
    final style = TextStyle(
      fontSize: settings.fontSize,
      height: settings.lineSpacing,
      letterSpacing: settings.letterSpacing,
      wordSpacing: settings.wordSpacing,
    );

    // 3. Get width
    double width = 800; // fallback
    final context = _blockKeys[index].currentContext;
    if (context != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null)
        width = box.size.width -
            30; // Accounting for Padding(left: 30) in _EditorBlock
    }

    // 4. Paint
    final span = controller.text.isEmpty
        ? TextSpan(text: ' ', style: style)
        : controller.buildTextSpan(
            context: context ?? this.context,
            style: style,
            withComposing: false,
          );
    final painter = TextPainter(
      text: span,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: textAlign,
    );
    painter.layout(maxWidth: width > 0 ? width : 800);

    return _VerticalLayoutInfo(painter, selection ?? controller.selection);
  }
}

class _VerticalLayoutInfo {
  final TextPainter painter;
  final TextSelection selection;

  _VerticalLayoutInfo(this.painter, this.selection);

  bool get isAtTop {
    if (!selection.isCollapsed) return false;
    if (painter.text?.toPlainText().isEmpty ?? true) return true;
    return _currentLineIndex <= 0;
  }

  bool get isAtBottom {
    if (!selection.isCollapsed) return false;
    if (painter.text?.toPlainText().isEmpty ?? true) return true;
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return true;
    return _currentLineIndex >= lines.length - 1;
  }

  double get currentX {
    if (selection.baseOffset < 0) return 0;
    final pos = TextPosition(offset: selection.baseOffset);
    return painter.getOffsetForCaret(pos, Rect.zero).dx;
  }

  int getPositionAtX(double x, {required bool fromBottom}) {
    if (painter.text?.toPlainText().isEmpty ?? true) return 0;
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return 0;
    final y = _lineCenterY(fromBottom ? lines.length - 1 : 0);
    return painter.getPositionForOffset(Offset(x, y)).offset;
  }

  int? getPositionOnAdjacentLineAtX(double x, {required bool moveUp}) {
    if (painter.text?.toPlainText().isEmpty ?? true) return null;
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return null;
    final targetLine = _currentLineIndex + (moveUp ? -1 : 1);
    if (targetLine < 0 || targetLine >= lines.length) return null;
    return painter
        .getPositionForOffset(Offset(x, _lineCenterY(targetLine)))
        .offset;
  }

  int get _currentLineIndex {
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return 0;
    final text = painter.text?.toPlainText() ?? '';
    final offset = selection.baseOffset.clamp(0, text.length).toInt();
    final caretY =
        painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < lines.length; i++) {
      final center = _lineCenterY(i);
      final distance = (center - caretY).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  double _lineCenterY(int index) {
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return 0;
    final safeIndex = index.clamp(0, lines.length - 1).toInt();
    final line = lines[safeIndex];
    final top = line.baseline - line.ascent;
    final bottom = line.baseline + line.descent;
    return (top + bottom) / 2;
  }
}
