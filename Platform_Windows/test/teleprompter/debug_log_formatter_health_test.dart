import 'package:autoteleprompter/features/teleprompter/services/debug_log_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('labels engine readiness as health rather than speech activity', () {
    expect(
      DebugLogFormatter.normalize(
        'ENGINE HEALTH: BROWSER ONLINE READY (speech not implied)',
      ),
      '[HEALTH] ENGINE HEALTH: BROWSER ONLINE READY (speech not implied)',
    );
  });
}
