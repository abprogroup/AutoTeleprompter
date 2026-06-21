part of 'script_editor_screen.dart';

extension _ScriptEditorStylingCommandParts on _ScriptEditorScreenState {
  void handleBgColorChange(int color) {
    _isSuiteDirty =
        true; // Always treat as session change if color picker is involved
    ref.read(settingsProvider.notifier).setScriptBgColor(color);
    if (_activeSuite == EditorSuite.none) {
      _saveHistory(description: 'Change Background', debounce: true);
    }
    if (mounted) _setEditorState(() {});
  }

  /// Returns the list of controllers that should receive a style command,
  /// honoring an active overlay selection (refined or global) when present.
  List<MarkupController> _styleTargets() {
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection || hasOverlay) {
      final refined = _controllers
          .where((c) =>
              c.externalSelection != null &&
              c.externalSelection!.isValid &&
              !c.externalSelection!.isCollapsed)
          .toList();
      if (refined.isNotEmpty) return refined;
      return List.of(_controllers);
    }
    final active = _activeController;
    return active == null ? <MarkupController>[] : [active];
  }

  bool _hasActiveTextSelection() {
    _restoreSelectionIfNeeded();
    if (_isGlobalSelection ||
        (_overlayKey.currentState?.hasSelection ?? false)) {
      return true;
    }
    for (final controller in _controllers) {
      final external = controller.externalSelection;
      if (external != null && external.isValid && !external.isCollapsed) {
        return true;
      }
      final selection = controller.selection;
      if (selection.isValid && !selection.isCollapsed) return true;
    }
    return false;
  }

  void _applyStyleCmd(String open, String close, String label) {
    _setEditorState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    if (skipH) _trackSuiteSection('Style');

    if (_isGlobalSelection) {
      // Per-controller toggle: set full-block externalSelection on each,
      // temporarily disable global flag so the mixin uses single-controller path.
      _isGlobalSelection = false;
      for (final c in _controllers) {
        if (c.text.isEmpty) continue;
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: c.text.length);
        wrapSelection(open, close, controllerOverride: c, skipHistory: true);
      }
      if (!skipH) _saveHistory(description: 'Global $label');
      _isGlobalSelection = true;
      _resyncGlobalSelection();
    } else {
      final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
      final targets = _styleTargets();
      if (hasOverlay && targets.length > 1) {
        // v4.1.3: Apply style, then read c.selection synchronously.
        // wrapSelection sets controller.value (and thus c.selection) in the same
        // Dart call — iOS async platform resets only arrive at event-loop
        // boundaries, so the read is guaranteed correct before we return.
        for (final c in targets) {
          if (c.text.isEmpty) continue;
          final hadSelection = c.externalSelection != null &&
              c.externalSelection!.isValid &&
              !c.externalSelection!.isCollapsed;
          wrapSelection(open, close, controllerOverride: c, skipHistory: true);
          if (hadSelection) {
            final postSel = c.selection;
            if (postSel.isValid && !postSel.isCollapsed) {
              c.externalSelection = postSel;
              c.refresh();
            }
          }
        }
        _overlayKey.currentState
            ?.syncOffsetsFromExternalSelection(_controllers);
        if (!skipH) _saveHistory(description: 'Selection $label');
      } else if (targets.length > 1) {
        for (final c in targets) {
          wrapSelection(open, close, controllerOverride: c, skipHistory: true);
        }
        if (!skipH) _saveHistory(description: 'Selection $label');
      } else if (targets.length == 1) {
        final c = targets.first;
        // v4.1.3: Check whether a selection exists, apply the style, then read
        // c.selection synchronously — it is set by wrapSelection before any iOS
        // platform event can interfere. No visual-offset conversion needed.
        final hadSel = (c.externalSelection != null &&
                c.externalSelection!.isValid &&
                !c.externalSelection!.isCollapsed) ||
            !c.selection.isCollapsed;
        wrapSelection(open, close, controllerOverride: c, skipHistory: skipH);
        if (hadSel) {
          final postSel = c.selection;
          if (postSel.isValid && !postSel.isCollapsed) {
            c.externalSelection = postSel;
            c.refresh();
          }
          if (_overlayKey.currentState?.hasSelection ?? false) {
            _overlayKey.currentState
                ?.syncOffsetsFromExternalSelection(_controllers);
          }
        }
      }
    }

    if (skipH) _isSuiteDirty = true;
    // Update cursor style BEFORE clearing _isCommandExecuting,
    // so _onSelectionChanged won't clear global selection prematurely.
    _onSelectionChanged();
    _setEditorState(() => _isCommandExecuting = false);
  }

  void _onBold() => _applyStyleCmd('**', '**', 'Bold');
  void _onUnderline() => _applyStyleCmd('[u]', '[/u]', 'Underline');
  void _onItalic() => _applyStyleCmd('[i]', '[/i]', 'Italic');

  void _applyInlineCmd(String family, String open, String close, String label) {
    _setEditorState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    // Section mapping: size → Font Size, font → Font Family, color → Text Color, bg → Highlight
    if (skipH) {
      final sectionMap = {
        'size': 'Font Size',
        'font': 'Font Family',
        'color': 'Text Color',
        'bg': 'Highlight'
      };
      _trackSuiteSection(sectionMap[family] ?? label);
    }

    if (_isGlobalSelection) {
      _isGlobalSelection = false;
      for (final c in _controllers) {
        if (c.text.isEmpty) continue;
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: c.text.length);
        applyInlineProperty(family, open, close,
            controllerOverride: c, skipHistory: true);
      }
      if (!skipH) _saveHistory(description: 'Global $label');
      _isGlobalSelection = true;
      _resyncGlobalSelection();
    } else {
      final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
      final targets = _styleTargets();
      if (hasOverlay && targets.length > 1) {
        // v4.1.3: Same synchronous-read approach as _applyStyleCmd multi-block.
        for (final c in targets) {
          if (c.text.isEmpty) continue;
          final hadSelection = c.externalSelection != null &&
              c.externalSelection!.isValid &&
              !c.externalSelection!.isCollapsed;
          applyInlineProperty(family, open, close,
              controllerOverride: c, skipHistory: true);
          if (hadSelection) {
            final postSel = c.selection;
            if (postSel.isValid && !postSel.isCollapsed) {
              c.externalSelection = postSel;
              c.refresh();
            }
          }
        }
        _overlayKey.currentState
            ?.syncOffsetsFromExternalSelection(_controllers);
      } else if (targets.length == 1) {
        // v4.1.3: Same synchronous-read approach as _applyStyleCmd single-block.
        final c = targets.first;
        final hadSel = (c.externalSelection != null &&
                c.externalSelection!.isValid &&
                !c.externalSelection!.isCollapsed) ||
            !c.selection.isCollapsed;
        applyInlineProperty(family, open, close,
            controllerOverride: c, skipHistory: true);
        if (hadSel) {
          final postSel = c.selection;
          if (postSel.isValid && !postSel.isCollapsed) {
            c.externalSelection = postSel;
            c.refresh();
          }
          if (_overlayKey.currentState?.hasSelection ?? false) {
            _overlayKey.currentState
                ?.syncOffsetsFromExternalSelection(_controllers);
          }
        }
      } else {
        for (final c in targets) {
          applyInlineProperty(family, open, close,
              controllerOverride: c, skipHistory: true);
        }
      }
      if (!skipH && targets.isNotEmpty) {
        _saveHistory(description: targets.length > 1 ? 'Global $label' : label);
      }
    }

    if (skipH) _isSuiteDirty = true;
    _onSelectionChanged();
    _setEditorState(() => _isCommandExecuting = false);
  }

  void onDirection(String dir) {
    _restoreSelectionIfNeeded();
    _setEditorState(() => _isCommandExecuting = true);
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) _trackSuiteSection('Alignment');

    if (_isGlobalSelection) {
      broadcastDirection(dir, open: '[$dir]', close: '[/$dir]');
      _resyncGlobalSelection();
    } else {
      final targets = _styleTargets();
      for (final controller in targets) {
        // Direction strips/replaces only RTL/LTR tags, shifting raw offsets by
        // the tag-length delta. Capture visual offsets before applying, then
        // re-pin externalSelection after.
        final external = controller.externalSelection;
        final selection =
            external != null && external.isValid && !external.isCollapsed
                ? external
                : controller.selection;
        final hadSel = selection.isValid && !selection.isCollapsed;
        final visStart = hadSel
            ? MarkupController.rawToVisualOffset(
                controller.text,
                selection.start,
              )
            : 0;
        final visEnd = hadSel
            ? MarkupController.rawToVisualOffset(
                controller.text,
                selection.end,
              )
            : 0;
        controller.value = TextEditingValue(
          text: StylingService.applyDirection(controller.text, selection, dir),
          selection: const TextSelection.collapsed(offset: 0),
        );
        if (hadSel) {
          final newStart =
              MarkupController.visualToRawOffset(controller.text, visStart);
          final newEnd =
              MarkupController.visualToRawOffset(controller.text, visEnd);
          if (newEnd > newStart) {
            controller.externalSelection =
                TextSelection(baseOffset: newStart, extentOffset: newEnd);
            controller.refresh();
          }
        }
      }
      if (_overlayKey.currentState?.hasSelection ?? false) {
        _overlayKey.currentState?.syncOffsetsFromExternalSelection(targets);
      }
    }

    if (inSuite) {
      _isSuiteDirty = true;
    } else {
      _commitHistory('Direction: $dir');
    }
    _onSelectionChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cursorStyleProvider.notifier).state =
          ref.read(cursorStyleProvider).copyWith(textDirection: dir);
      _overlayKey.currentState?.refreshPositions();
    });
    _setEditorState(() => _isCommandExecuting = false);
  }

  void onAlign(String align) {
    _setEditorState(() => _isCommandExecuting = true);
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) _trackSuiteSection('Alignment');

    if (_isGlobalSelection) {
      broadcastAlign(align, open: '[align=$align]', close: '[/align=$align]');
      _resyncGlobalSelection();
    } else {
      final targets = _styleTargets();
      for (final controller in targets) {
        // v4.1.3: Same visual-offset preservation as onDirection.
        final hadSel = controller.externalSelection != null &&
            controller.externalSelection!.isValid &&
            !controller.externalSelection!.isCollapsed;
        final visStart = hadSel
            ? MarkupController.rawToVisualOffset(
                controller.text, controller.externalSelection!.start)
            : 0;
        final visEnd = hadSel
            ? MarkupController.rawToVisualOffset(
                controller.text, controller.externalSelection!.end)
            : 0;
        controller.value = TextEditingValue(
          text: StylingService.applyLayout(
              controller.text, controller.selection, align),
          selection: const TextSelection.collapsed(offset: 0),
        );
        if (hadSel) {
          final newStart =
              MarkupController.visualToRawOffset(controller.text, visStart);
          final newEnd =
              MarkupController.visualToRawOffset(controller.text, visEnd);
          if (newEnd > newStart) {
            controller.externalSelection =
                TextSelection(baseOffset: newStart, extentOffset: newEnd);
            controller.refresh();
          }
        }
      }
      if (_overlayKey.currentState?.hasSelection ?? false) {
        _overlayKey.currentState?.syncOffsetsFromExternalSelection(targets);
      }
    }

    if (inSuite) {
      _isSuiteDirty = true;
    } else {
      _commitHistory('Align: $align');
    }
    _onSelectionChanged();
    // Directly stamp the chosen alignment into cursorStyleProvider after the
    // detection callback runs — detection is unreliable immediately after an
    // apply because the focus/selection state is in flux.
    // Also refresh overlay handle positions — text moved visually but handles
    // are still at the old coordinates from before the alignment change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cursorStyleProvider.notifier).state =
          ref.read(cursorStyleProvider).copyWith(textAlign: align);
      _overlayKey.currentState?.refreshPositions();
    });
    _setEditorState(() => _isCommandExecuting = false);
  }

  void onFontSize(int size) {
    _applyGlobalFontSize(size.toDouble());
  }

  Future<void> _applyGlobalFontSize(double size) async {
    final clamped = size.clamp(14.0, 120.0).toDouble();
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) {
      _trackSuiteSection('Font Size');
      _isSuiteDirty = true;
    }
    await ref.read(settingsProvider.notifier).setFontSize(clamped);
    await ref.read(scriptProvider.notifier).updateStyleMetadata(
          fontSize: clamped,
        );
    if (!mounted) return;
    ref.read(cursorStyleProvider.notifier).state =
        ref.read(cursorStyleProvider).copyWith(fontSize: clamped.round());
    if (inSuite) {
      _scheduleRecentUpdate();
    } else {
      _commitHistory('Font Size');
    }
    _onSelectionChanged();
  }

  Future<void> _applyGlobalFontFamily(String family) async {
    final clean = EditorFontService.cleanFamily(family);
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) {
      _trackSuiteSection('Font Family');
      _isSuiteDirty = true;
    }
    await ref.read(settingsProvider.notifier).setFontFamily(clean);
    await ref.read(scriptProvider.notifier).updateStyleMetadata(
          fontFamily: clean,
        );
    if (!mounted) return;
    ref.read(cursorStyleProvider.notifier).state =
        ref.read(cursorStyleProvider).copyWith(fontFamily: clean);
    if (inSuite) {
      _scheduleRecentUpdate();
    } else {
      _commitHistory('Font Family');
    }
    _onSelectionChanged();
  }

  void onFontFamily(String family) {
    final clean = EditorFontService.cleanFamily(family).replaceAll(']', '');
    if (clean.isEmpty) return;
    if (_hasActiveTextSelection()) {
      _applyInlineCmd('font', '[font=$clean]', '[/font]', 'Font Family');
      if (mounted) {
        ref.read(cursorStyleProvider.notifier).state =
            ref.read(cursorStyleProvider).copyWith(fontFamily: clean);
      }
      return;
    }
    unawaited(_applyGlobalFontFamily(clean));
  }

  /// Restore the selection that was active before a dialog stole focus.
  /// Color picker dialogs cause the TextField to lose focus, collapsing the
  /// selection. This restores it so the style is applied to the right range.
  void _restoreSelectionIfNeeded() {
    final c = _activeController;
    if (c == null) return;
    if (c.selection.isCollapsed &&
        _preservedSelection != null &&
        !_preservedSelection!.isCollapsed) {
      final sel = _preservedSelection!;
      if (sel.end <= c.text.length) {
        c.selection = sel;
      }
    }
  }

  void onTextColorSelected(String hex) {
    final cleanHex = hex.replaceFirst('#', '').toUpperCase();
    final intVal = int.tryParse(cleanHex, radix: 16) ?? 0;
    // "None" color (transparent/0): REMOVE existing color tags instead of wrapping
    if (intVal == 0 || intVal == 0x00000000) {
      _restoreSelectionIfNeeded();
      _removeInlineTags('color', '[/color]');
      return;
    }
    final color = Color(int.tryParse('FF$cleanHex', radix: 16) ?? 0xFFFFBF00);
    _setEditorState(() => _lastChosenTextColor = color);
    ref
        .read(settingsProvider.notifier)
        .setLastChosenTextColor(color.toARGB32());
    _restoreSelectionIfNeeded();
    _applyInlineCmd('color', '[color=#$cleanHex]', '[/color]', 'Text Color');
  }

  void onBgColorSelected(String hex) {
    final cleanHex = hex.replaceFirst('#', '').toUpperCase();
    final intVal = int.tryParse(cleanHex, radix: 16) ?? 0;
    // "None" color (transparent/0): REMOVE existing bg tags instead of wrapping
    if (intVal == 0 || intVal == 0x00000000) {
      _restoreSelectionIfNeeded();
      _removeInlineTags('bg', '[/bg]');
      return;
    }
    final color = Color(int.tryParse('FF$cleanHex', radix: 16) ?? 0x00FFFFFF);
    _setEditorState(() => _lastChosenHighlightColor = color);
    ref
        .read(settingsProvider.notifier)
        .setLastChosenHighlightColor(color.toARGB32());
    _restoreSelectionIfNeeded();
    _applyInlineCmd('bg', '[bg=#$cleanHex]', '[/bg]', 'Highlight Color');
  }

  /// Remove all tags of a given family from the selection (used when "none" color is chosen).
  void _removeInlineTags(String family, String close) {
    _setEditorState(() => _isCommandExecuting = true);
    final openPattern = RegExp(r'\[' + family + r'=[^\]]*\]');

    if (_isGlobalSelection) {
      _isGlobalSelection = false;
      for (final c in _controllers) {
        if (c.text.isEmpty) continue;
        c.text = c.text.replaceAll(openPattern, '').replaceAll(close, '');
      }
      _saveHistory(description: 'Remove $family');
      _isGlobalSelection = true;
      _resyncGlobalSelection();
    } else {
      final targets = _styleTargets();
      for (final c in targets) {
        final sel = (c.externalSelection != null &&
                c.externalSelection!.isValid &&
                !c.externalSelection!.isCollapsed)
            ? c.externalSelection!
            : c.selection;
        if (sel.isCollapsed) {
          // Cursor mode: remove enclosing tag pair
          final text = c.text;
          final tagMatch = openPattern.allMatches(text).where((m) {
            final closeIdx = text.indexOf(close, m.end);
            return closeIdx != -1 &&
                m.start <= sel.start &&
                closeIdx + close.length >= sel.end;
          }).toList();
          if (tagMatch.isNotEmpty) {
            final m = tagMatch.last;
            final closeIdx = text.indexOf(close, m.end);
            final newText = text.substring(0, m.start) +
                text.substring(m.end, closeIdx) +
                text.substring(closeIdx + close.length);
            final offset =
                (sel.start - m.group(0)!.length).clamp(0, newText.length);
            c.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: offset),
            );
          }
        } else {
          // Range mode: strip all family tags within selection
          final before = c.text.substring(0, sel.start);
          final selected = c.text.substring(sel.start, sel.end);
          final after = c.text.substring(sel.end);
          final cleaned =
              selected.replaceAll(openPattern, '').replaceAll(close, '');
          c.value = TextEditingValue(
            text: before + cleaned + after,
            selection: TextSelection(
                baseOffset: sel.start,
                extentOffset: sel.start + cleaned.length),
          );
        }
      }
      if (targets.isNotEmpty) _saveHistory(description: 'Remove $family');
    }
    _onSelectionChanged();
    _setEditorState(() => _isCommandExecuting = false);
  }
}
