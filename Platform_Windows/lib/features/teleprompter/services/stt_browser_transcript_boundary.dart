import '../../../core/extensions/string_extensions.dart';
import 'speech_service.dart';

/// Optional browser result-slot provenance. Finalized Web Speech slots cannot
/// be rewritten; later slots are fresh even if the consumed interim tail was
/// corrected when it became final. Legacy/ambiguous snapshots stay fail closed.
class SttBrowserTranscriptBoundary {
  List<String> _segments = const [];
  int _finalizedCount = 0;
  int? _consumedSegmentCount;
  String _primary = '';

  void reset() {
    _segments = const [];
    _finalizedCount = 0;
    _consumedSegmentCount = null;
    _primary = '';
  }

  void observe(SpeechResult result) {
    _segments = const [];
    _finalizedCount = 0;
    _primary = '';
    final parts = result.browserSegments;
    if (!result.isCumulative ||
        result.streamId == null ||
        parts.isEmpty ||
        result.browserFinalizedSegmentCount < 0 ||
        result.browserFinalizedSegmentCount > parts.length ||
        _canonical(parts.join(' ')) != _canonical(result.words)) {
      return;
    }
    _segments = parts;
    _primary = result.words.trim();
    _finalizedCount = result.browserFinalizedSegmentCount;
  }

  void consumeSnapshot() {
    _consumedSegmentCount = _segments.isEmpty ? null : _segments.length;
  }

  int? freshFloorCeiling(String candidate) {
    final count = _consumedSegmentCount;
    // Alternatives have different token offsets. Only the authenticated
    // primary snapshot's validated slot offsets may constrain its floor.
    if (candidate != _primary ||
        count == null ||
        count <= 0 ||
        count >= _segments.length ||
        count > _finalizedCount) {
      return null;
    }
    return _segments
        .take(count)
        .join(' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.normalizeForMatching().isNotEmpty)
        .length;
  }

  String _canonical(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
