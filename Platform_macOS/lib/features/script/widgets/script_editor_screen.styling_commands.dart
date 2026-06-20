part of 'script_editor_screen.dart';

extension _ScriptEditorStylingCommandParts on _ScriptEditorScreenState {
  List<MarkupController> _styleTargets() {
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    final hasStructuredSelection = _isGlobalSelection ||
        hasOverlay ||
        _controllers.any((c) {
          final external = c.externalSelection;
          return c.isGlobalSelected ||
              (external != null && external.isValid && !external.isCollapsed);
        });
    if (hasStructuredSelection) {
      final refined = _controllers
          .where((c) =>
              c.isGlobalSelected ||
              (c.externalSelection != null &&
                  c.externalSelection!.isValid &&
                  !c.externalSelection!.isCollapsed))
          .toList();
      if (refined.isNotEmpty) return refined;
      return List.of(_controllers);
    }
    final active = _activeController;
    return active == null ? <MarkupController>[] : [active];
  }

  bool _hasWholeScriptSelection() {
    if (_isGlobalSelection) return true;
    if (_controllers.isEmpty) return false;
    return _controllers.every((c) {
      if (c.text.isEmpty) return true;
      if (c.isGlobalSelected) return true;
      final external = c.externalSelection;
      return external != null &&
          external.isValid &&
          external.start <= 0 &&
          external.end >= c.text.length;
    });
  }

  void _applyStyleCmd(String open, String close, String label) {
    _restoreSelectionIfNeeded();
    _setEditorState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    if (skipH) _trackSuiteSection('Style');

    bool applyForcedToTargets(List<MarkupController> targets) {
      final states = targets
          .map((c) => selectionStyleState(open, close, controllerOverride: c))
          .where((state) => state.visibleCount > 0)
          .toList();
      if (states.isEmpty) return false;
      final enable = !states.every((state) => state.fullyStyled);

      for (final c in targets) {
        if (c.text.isEmpty) continue;
        final hadSelection = c.externalSelection != null &&
            c.externalSelection!.isValid &&
            !c.externalSelection!.isCollapsed;
        forceSelectionStyle(
          open,
          close,
          enable: enable,
          controllerOverride: c,
          skipHistory: true,
        );
        if (hadSelection) {
          final postSel = c.selection;
          if (postSel.isValid && !postSel.isCollapsed) {
            c.externalSelection = postSel;
            c.refresh();
          }
        }
      }
      return true;
    }

    if (_isGlobalSelection) {
      // Per-controller toggle: set full-block externalSelection on each,
      // temporarily disable global flag so the mixin uses single-controller path.
      _isGlobalSelection = false;
      final targets = <MarkupController>[];
      for (final c in _controllers) {
        if (c.text.isEmpty) continue;
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: c.text.length);
        targets.add(c);
      }
      applyForcedToTargets(targets);
      if (!skipH) _saveHistory(description: 'Global $label');
      _isGlobalSelection = true;
      _resyncGlobalSelection();
    } else {
      final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
      final targets = _styleTargets();
      if (hasOverlay && targets.length > 1 && applyForcedToTargets(targets)) {
        // v4.1.3: Apply style, then read c.selection synchronously.
        // wrapSelection sets controller.value (and thus c.selection) in the same
        // Dart call — iOS async platform resets only arrive at event-loop
        // boundaries, so the read is guaranteed correct before we return.
        _overlayKey.currentState
            ?.syncOffsetsFromExternalSelection(_controllers);
        if (!skipH) _saveHistory(description: 'Selection $label');
      } else if (targets.length > 1 && applyForcedToTargets(targets)) {
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
        if (!hadSel || !applyForcedToTargets([c])) {
          wrapSelection(open, close, controllerOverride: c, skipHistory: skipH);
        } else if (!skipH) {
          _saveHistory(description: label);
        }
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

    if (skipH) _recordSuiteHistoryChange('Style');
    // Update cursor style BEFORE clearing _isCommandExecuting,
    // so _onSelectionChanged won't clear global selection prematurely.
    _onSelectionChanged();
    _setEditorState(() => _isCommandExecuting = false);
  }

  void _onBold() => _applyStyleCmd('**', '**', 'Bold');
  void _onUnderline() => _applyStyleCmd('[u]', '[/u]', 'Underline');
  void _onItalic() => _applyStyleCmd('[i]', '[/i]', 'Italic');

  void _applyInlineCmd(String family, String open, String close, String label) {
    final parameterValue = _inlineParameterValue(open, family);
    if ((family == 'size' || family == 'font') && parameterValue != null) {
      _applyParameterizedInlineCmd(family, parameterValue, label);
      return;
    }

    _restoreSelectionIfNeeded();
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

    if (skipH) {
      final sectionMap = {
        'size': 'Font Size',
        'font': 'Font Family',
        'color': 'Text Color',
        'bg': 'Highlight'
      };
      _recordSuiteHistoryChange(sectionMap[family] ?? label);
    }
    _onSelectionChanged();
    _setEditorState(() => _isCommandExecuting = false);
  }

  String? _inlineParameterValue(String open, String family) {
    final prefix = '[$family=';
    if (!open.startsWith(prefix) || !open.endsWith(']')) return null;
    return open.substring(prefix.length, open.length - 1);
  }

  void _applyParameterizedInlineCmd(
    String family,
    String value,
    String label,
  ) {
    _restoreSelectionIfNeeded();
    _setEditorState(() => _isCommandExecuting = true);

    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) {
      _trackSuiteSection(label);
    }

    var changed = false;
    final wasGlobalSelection = _isGlobalSelection;
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;

    List<MarkupController> targets;
    if (wasGlobalSelection) {
      _isGlobalSelection = false;
      targets = <MarkupController>[];
      for (final c in _controllers) {
        if (c.text.isEmpty) continue;
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: c.text.length);
        c.externalVisibleSelection = TextSelection(
          baseOffset: 0,
          extentOffset: MarkupDecorationParser.visibleText(c.text).length,
        );
        targets.add(c);
      }
    } else {
      targets = _styleTargets();
    }
    final hasStructuredTargetSelection = targets.any((c) {
      final external = c.externalSelection;
      return c.isGlobalSelected ||
          (external != null && external.isValid && !external.isCollapsed);
    });

    for (final c in targets) {
      if (c.text.isEmpty) continue;
      final external = c.externalSelection;
      final selection =
          external != null && external.isValid && !external.isCollapsed
              ? external
              : c.selection;
      if (!selection.isValid || selection.isCollapsed) continue;

      final nextValue = EditorInlineStyleOperation.applyParameterized(
        text: c.text,
        selection: selection,
        family: family,
        value: value,
      );
      if (nextValue.text == c.text && nextValue.selection == c.selection) {
        continue;
      }
      c.value = nextValue;
      final postSelection = c.selection.isValid && !c.selection.isCollapsed
          ? c.selection
          : nextValue.selection;
      if (postSelection.isValid && !postSelection.isCollapsed) {
        c.externalSelection = postSelection;
        c.externalVisibleSelection =
            MarkupDecorationParser.rawToVisibleSelection(
          c.text,
          postSelection,
        );
      }
      c.refresh();
      changed = true;
    }

    if (wasGlobalSelection) {
      _isGlobalSelection = true;
      _resyncGlobalSelection();
    } else if (hasOverlay || hasStructuredTargetSelection) {
      _overlayKey.currentState?.syncOffsetsFromExternalSelection(_controllers);
    }

    if (changed && inSuite) {
      _recordSuiteHistoryChange(label);
    } else if (changed) {
      _commitHistory(targets.length > 1 ? 'Selection $label' : label);
    }
    _onSelectionChanged();
    _setEditorState(() => _isCommandExecuting = false);
  }

  void onDirection(String dir) {
    _restoreSelectionIfNeeded();
    _setEditorState(() => _isCommandExecuting = true);
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) _trackSuiteSection('Alignment');

    if (_hasWholeScriptSelection()) {
      _isGlobalSelection = true;
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
        _overlayKey.currentState
            ?.syncOffsetsFromExternalSelection(_controllers);
      }
    }

    if (inSuite) {
      _recordSuiteHistoryChange('Direction: $dir');
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
    _restoreSelectionIfNeeded();
    _setEditorState(() => _isCommandExecuting = true);
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) _trackSuiteSection('Alignment');

    if (_hasWholeScriptSelection()) {
      _isGlobalSelection = true;
      broadcastAlign(align, open: '[align=$align]', close: '[/align=$align]');
      _resyncGlobalSelection();
    } else {
      final targets = _styleTargets();
      for (final controller in targets) {
        // v4.1.3: Same visual-offset preservation as onDirection.
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
          text: StylingService.applyLayout(controller.text, selection, align),
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
        _overlayKey.currentState
            ?.syncOffsetsFromExternalSelection(_controllers);
      }
    }

    if (inSuite) {
      _recordSuiteHistoryChange('Align: $align');
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

  bool _hasActiveTextSelection() {
    if (_isGlobalSelection) return true;
    if (_overlayKey.currentState?.hasSelection ?? false) return true;
    for (final c in _controllers) {
      final external = c.externalSelection;
      if (external != null && external.isValid && !external.isCollapsed) {
        return true;
      }
    }
    final active = _activeController;
    return active != null &&
        active.selection.isValid &&
        !active.selection.isCollapsed;
  }

  String _formatInlineSize(double size) {
    final clamped = size.clamp(1.0, 300.0).toDouble();
    if ((clamped - clamped.roundToDouble()).abs() < 0.001) {
      return clamped.round().toString();
    }
    return clamped.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void onFontSize(double size) {
    if (_hasActiveTextSelection()) {
      final formatted = _formatInlineSize(size);
      _applyInlineCmd('size', '[size=$formatted]', '[/size]', 'Font Size');
      if (mounted) {
        ref.read(cursorStyleProvider.notifier).state =
            ref.read(cursorStyleProvider).copyWith(fontSize: size.round());
      }
      return;
    }
    _applyGlobalFontSize(size);
  }

  Future<void> _applyGlobalFontSize(double size) async {
    final clamped = size.clamp(14.0, 120.0).toDouble();
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) {
      _trackSuiteSection('Font Size');
    }
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final scriptNotifier = ref.read(scriptProvider.notifier);
    await settingsNotifier.setFontSize(clamped);
    await scriptNotifier.updateStyleMetadata(fontSize: clamped);
    if (!mounted) return;
    ref.read(cursorStyleProvider.notifier).state =
        ref.read(cursorStyleProvider).copyWith(fontSize: clamped.round());
    if (inSuite) {
      _recordSuiteHistoryChange('Font Size');
    } else {
      _commitHistory('Font Size');
    }
    _onSelectionChanged();
  }

  Future<void> _applyGlobalFontFamily(String family) async {
    final clean = family.trim().isEmpty ? 'Inter' : family.trim();
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) {
      _trackSuiteSection('Font Family');
    }
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final scriptNotifier = ref.read(scriptProvider.notifier);
    await settingsNotifier.setFontFamily(clean);
    await scriptNotifier.updateStyleMetadata(fontFamily: clean);
    if (!mounted) return;
    ref.read(cursorStyleProvider.notifier).state =
        ref.read(cursorStyleProvider).copyWith(fontFamily: clean);
    if (inSuite) {
      _recordSuiteHistoryChange('Font Family');
    } else {
      _commitHistory('Font Family');
    }
    _onSelectionChanged();
  }

  void onFontFamily(String family) {
    final escaped = family.trim().replaceAll(']', '');
    if (escaped.isEmpty) return;
    if (_hasActiveTextSelection()) {
      _applyInlineCmd('font', '[font=$escaped]', '[/font]', 'Font Family');
      if (mounted) {
        ref.read(cursorStyleProvider.notifier).state =
            ref.read(cursorStyleProvider).copyWith(fontFamily: escaped);
      }
      return;
    }
    _applyGlobalFontFamily(escaped);
  }

  /// Restore the selection that was active before a dialog stole focus.
  /// Color picker dialogs cause the TextField to lose focus, collapsing the
  /// selection. This restores it so the style is applied to the right range.
  void _restoreSelectionIfNeeded() {
    final c = _activeController;
    if (c == null) return;
    if (c.externalSelection != null &&
        c.externalSelection!.isValid &&
        !c.externalSelection!.isCollapsed) {
      return;
    }
    if (c.selection.isCollapsed &&
        identical(c, _lastFocusedController) &&
        _preservedSelection != null &&
        !_preservedSelection!.isCollapsed) {
      final sel = _preservedSelection!;
      if (sel.end <= c.text.length) {
        c.selection = sel;
        final blockIndex = _controllers.indexOf(c);
        if (blockIndex >= 0) {
          _overlayKey.currentState?.extendNativeBlockSelection(
            blockIndex,
            sel,
            allowFullBlock: true,
          );
        } else {
          c.externalSelection = sel;
          c.externalVisibleSelection = null;
          c.refresh();
        }
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
    _restoreSelectionIfNeeded();
    _setEditorState(() => _isCommandExecuting = true);
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) _trackSuiteSection('Remove $family');
    final openPattern = RegExp(r'\[' + family + r'=[^\]]*\]');

    if (_isGlobalSelection) {
      _isGlobalSelection = false;
      for (final c in _controllers) {
        if (c.text.isEmpty) continue;
        c.text = c.text.replaceAll(openPattern, '').replaceAll(close, '');
      }
      if (inSuite) {
        _recordSuiteHistoryChange('Remove $family');
      } else {
        _saveHistory(description: 'Remove $family');
      }
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
      if (targets.isNotEmpty) {
        if (inSuite) {
          _recordSuiteHistoryChange('Remove $family');
        } else {
          _saveHistory(description: 'Remove $family');
        }
      }
    }
    _onSelectionChanged();
    _setEditorState(() => _isCommandExecuting = false);
  }
}
