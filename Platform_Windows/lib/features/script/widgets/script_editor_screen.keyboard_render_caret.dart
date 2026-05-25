part of 'script_editor_screen.dart';

extension _ScriptEditorKeyboardRenderCaretParts on _ScriptEditorScreenState {
  ({int block, int offset})? _renderEditableVerticalTarget({
    required int block,
    required int offset,
    required bool moveUp,
    required bool crossBlockOnly,
    double? preferredX,
  }) {
    if (block < 0 || block >= _controllers.length) return null;
    final targetX =
        preferredX ?? _renderEditableCaretX(blockIndex: block, offset: offset);
    if (targetX == null) return null;

    final candidates = _renderEditableCaretCandidatesForBlock(block);
    if (candidates.isNotEmpty) {
      final lines = _groupRenderCaretCandidatesByLine(candidates);
      final currentLine = _renderEditableLineIndexForOffset(
        block: block,
        offset: offset,
        lines: lines,
      );
      if (currentLine != null) {
        final targetLine = currentLine + (moveUp ? -1 : 1);
        if (targetLine >= 0 && targetLine < lines.length) {
          if (crossBlockOnly) return null;
          final target = _nearestRenderCaretCandidate(
            lines[targetLine],
            targetX,
          );
          return target == null ? null : (block: block, offset: target.raw);
        }
      }
    }

    return _renderEditableCrossBlockVerticalTarget(
      fromBlock: block,
      moveUp: moveUp,
      preferredX: targetX,
    );
  }

  ({int block, int offset})? _renderEditableCrossBlockVerticalTarget({
    required int fromBlock,
    required bool moveUp,
    required double preferredX,
  }) {
    final targetBlock = fromBlock + (moveUp ? -1 : 1);
    if (targetBlock < 0 || targetBlock >= _controllers.length) return null;
    final targetText = _controllers[targetBlock].text;
    if (StylingService.stripTags(targetText).trim().isEmpty) {
      return (block: targetBlock, offset: 0);
    }
    final candidates = _renderEditableCaretCandidatesForBlock(targetBlock);
    if (candidates.isEmpty) return null;
    final lines = _groupRenderCaretCandidatesByLine(candidates);
    if (lines.isEmpty) return null;
    final targetLine = moveUp ? lines.length - 1 : 0;
    final target = _nearestRenderCaretCandidate(
      lines[targetLine],
      preferredX,
    );
    return target == null ? null : (block: targetBlock, offset: target.raw);
  }

  double? _renderEditableCaretX({
    required int blockIndex,
    required int offset,
  }) {
    final editable = _renderEditableForBlock(blockIndex);
    if (editable == null) return null;
    final textLength = _controllers[blockIndex].text.length;
    final safeOffset = offset.clamp(0, textLength).toInt();
    final endpoints = editable.getEndpointsForSelection(
      TextSelection.collapsed(offset: safeOffset),
    );
    if (endpoints.isEmpty) return null;
    return endpoints.first.point.dx;
  }

  RenderEditable? _renderEditableForBlock(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _blockKeys.length) return null;
    return _findRenderEditable(
      _blockKeys[blockIndex].currentContext?.findRenderObject(),
    );
  }

  List<_RenderCaretCandidate> _renderEditableCaretCandidatesForBlock(
    int blockIndex,
  ) {
    final editable = _renderEditableForBlock(blockIndex);
    if (editable == null) return const [];
    final rawText = _controllers[blockIndex].text;
    final visible = EditorTextGeometryService.visibleText(rawText);
    if (visible.isEmpty) return const [];
    final rawStops = <int>{};
    for (var visibleOffset = 0;
        visibleOffset <= visible.length;
        visibleOffset++) {
      rawStops.add(
        MarkupController.visualToRawOffset(rawText, visibleOffset)
            .clamp(0, rawText.length)
            .toInt(),
      );
    }

    final candidates = <_RenderCaretCandidate>[];
    for (final raw in rawStops) {
      for (final affinity in const [
        TextAffinity.downstream,
        TextAffinity.upstream,
      ]) {
        final endpoints = editable.getEndpointsForSelection(
          TextSelection.collapsed(offset: raw, affinity: affinity),
        );
        if (endpoints.isEmpty) continue;
        final point = endpoints.first.point;
        final duplicate = candidates.any((existing) =>
            existing.raw == raw &&
            (existing.x - point.dx).abs() <= 0.75 &&
            (existing.y - point.dy).abs() <= 0.75);
        if (duplicate) continue;
        candidates.add(_RenderCaretCandidate(
          raw: raw,
          x: point.dx,
          y: point.dy,
        ));
      }
    }
    candidates.sort((a, b) {
      final yCompare = a.y.compareTo(b.y);
      if (yCompare != 0) return yCompare;
      final xCompare = a.x.compareTo(b.x);
      if (xCompare != 0) return xCompare;
      return a.raw.compareTo(b.raw);
    });
    return candidates;
  }

  List<List<_RenderCaretCandidate>> _groupRenderCaretCandidatesByLine(
    List<_RenderCaretCandidate> candidates,
  ) {
    if (candidates.isEmpty) return const [];
    const tolerance = 3.0;
    final sorted = [...candidates]..sort((a, b) => a.y.compareTo(b.y));
    final lines = <List<_RenderCaretCandidate>>[];
    for (final candidate in sorted) {
      if (lines.isEmpty ||
          (lines.last.first.y - candidate.y).abs() > tolerance) {
        lines.add([candidate]);
      } else {
        lines.last.add(candidate);
      }
    }
    for (final line in lines) {
      line.sort((a, b) {
        final xCompare = a.x.compareTo(b.x);
        if (xCompare != 0) return xCompare;
        return a.raw.compareTo(b.raw);
      });
    }
    return lines;
  }

  int? _renderEditableLineIndexForOffset({
    required int block,
    required int offset,
    required List<List<_RenderCaretCandidate>> lines,
  }) {
    final editable = _renderEditableForBlock(block);
    if (editable == null || lines.isEmpty) return null;
    final safeOffset = offset.clamp(0, _controllers[block].text.length).toInt();
    final endpoints = editable.getEndpointsForSelection(
      TextSelection.collapsed(offset: safeOffset),
    );
    if (endpoints.isEmpty) return null;
    final y = endpoints.first.point.dy;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < lines.length; i++) {
      final distance = (lines[i].first.y - y).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  _RenderCaretCandidate? _nearestRenderCaretCandidate(
    List<_RenderCaretCandidate> line,
    double preferredX,
  ) {
    if (line.isEmpty) return null;
    _RenderCaretCandidate? best;
    var bestDistance = double.infinity;
    for (final candidate in line) {
      final distance = (candidate.x - preferredX).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }
}
