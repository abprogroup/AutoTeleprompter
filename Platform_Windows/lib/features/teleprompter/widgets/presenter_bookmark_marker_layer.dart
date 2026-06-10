import 'package:flutter/material.dart';

import '../../script/models/script_word.dart';

TextDirection presenterBookmarkParagraphDirection(
  List<ScriptWord> words,
  int index,
) {
  if (index < 0 || index >= words.length) return TextDirection.ltr;
  var start = index;
  while (start > 0 && !words[start - 1].isNewline) {
    start--;
  }
  var end = index;
  while (end + 1 < words.length && !words[end + 1].isNewline) {
    end++;
  }
  var hasLatin = false;
  for (var i = start; i <= end; i++) {
    final clean = words[i].raw.replaceAll(RegExp(r'\[[^\]]+\]'), '');
    if (clean.trim().isEmpty) continue;
    if (RegExp(r'[\u0590-\u08FF]').hasMatch(clean)) {
      return TextDirection.rtl;
    }
    if (RegExp(r'[A-Za-z]').hasMatch(clean)) hasLatin = true;
  }
  if (hasLatin) return TextDirection.ltr;
  return words[index].effectiveRtl ? TextDirection.rtl : TextDirection.ltr;
}

double presenterBookmarkMarkerLeft({
  required Rect wordRect,
  required TextDirection paragraphDirection,
  required double markerWidth,
  required double gap,
}) {
  return paragraphDirection == TextDirection.rtl
      ? wordRect.right + gap
      : wordRect.left - markerWidth - gap;
}

class PresenterBookmarkMarkerLayer extends StatefulWidget {
  final GlobalKey contentKey;
  final List<GlobalKey> wordKeys;
  final List<ScriptWord> words;
  final Set<int> bookmarkWordIndexes;
  final Color color;
  final double fontSize;
  final double lineSpacing;
  final ValueChanged<int>? onTap;

  const PresenterBookmarkMarkerLayer({
    super.key,
    required this.contentKey,
    required this.wordKeys,
    required this.words,
    required this.bookmarkWordIndexes,
    required this.color,
    required this.fontSize,
    required this.lineSpacing,
    this.onTap,
  });

  @override
  State<PresenterBookmarkMarkerLayer> createState() =>
      _PresenterBookmarkMarkerLayerState();
}

class _PresenterBookmarkMarkerLayerState
    extends State<PresenterBookmarkMarkerLayer> {
  List<_BookmarkMarkerPlacement> _placements = const [];
  bool _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant PresenterBookmarkMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final next = _measurePlacements();
      if (!_samePlacements(next, _placements)) {
        setState(() => _placements = next);
      }
    });
  }

  List<_BookmarkMarkerPlacement> _measurePlacements() {
    final contentBox =
        widget.contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (contentBox == null || !contentBox.attached) return const [];

    final markerFontSize = widget.fontSize * 0.62;
    final markerWidth = markerFontSize * 0.75;
    final markerHeight = markerFontSize * widget.lineSpacing;
    final gap = (widget.fontSize * 0.10).clamp(4.0, 16.0).toDouble();
    final result = <_BookmarkMarkerPlacement>[];

    for (final index in widget.bookmarkWordIndexes) {
      if (index < 0 ||
          index >= widget.words.length ||
          index >= widget.wordKeys.length) {
        continue;
      }
      final word = widget.words[index];
      if (word.isNewline) continue;
      final box = widget.wordKeys[index].currentContext?.findRenderObject()
          as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final topLeft = box.localToGlobal(Offset.zero, ancestor: contentBox);
      final rect = topLeft & box.size;
      final paragraphDirection =
          presenterBookmarkParagraphDirection(widget.words, index);
      final left = presenterBookmarkMarkerLeft(
        wordRect: rect,
        paragraphDirection: paragraphDirection,
        markerWidth: markerWidth,
        gap: gap,
      );
      result.add(
        _BookmarkMarkerPlacement(
          index: index,
          left: left,
          top: rect.center.dy - markerHeight / 2,
          width: markerWidth,
          height: markerHeight,
        ),
      );
    }

    return result;
  }

  bool _samePlacements(
    List<_BookmarkMarkerPlacement> a,
    List<_BookmarkMarkerPlacement> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: widget.onTap == null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final placement in _placements)
              Positioned(
                left: placement.left,
                top: placement.top,
                width: placement.width,
                height: placement.height,
                child: Tooltip(
                  message: 'Bookmark',
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.onTap == null
                        ? null
                        : () => widget.onTap!(placement.index),
                    child: Text(
                      '\u00BB',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.color,
                        fontSize: widget.fontSize * 0.62,
                        fontWeight: FontWeight.bold,
                        height: widget.lineSpacing,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkMarkerPlacement {
  final int index;
  final double left;
  final double top;
  final double width;
  final double height;

  const _BookmarkMarkerPlacement({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  @override
  bool operator ==(Object other) {
    return other is _BookmarkMarkerPlacement &&
        other.index == index &&
        (other.left - left).abs() < 0.5 &&
        (other.top - top).abs() < 0.5 &&
        (other.width - width).abs() < 0.5 &&
        (other.height - height).abs() < 0.5;
  }

  @override
  int get hashCode => Object.hash(
        index,
        left.round(),
        top.round(),
        width.round(),
        height.round(),
      );
}
