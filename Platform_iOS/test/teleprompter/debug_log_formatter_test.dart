import 'package:autoteleprompter/features/teleprompter/services/debug_log_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug log formatter strips corrupt prefixes and tags known messages',
      () {
    expect(
      DebugLogFormatter.normalize('��  WAIT #2 | heard: "hello"'),
      '[WAIT] WAIT #2 | heard: "hello"',
    );

    expect(
      DebugLogFormatter.normalize('ADVANCE -> #12 "message"'),
      '[OK] ADVANCE -> #12 "message"',
    );

    expect(
      DebugLogFormatter.normalize('[Apple] STATUS: listening'),
      '[Apple] STATUS: listening',
    );
  });
}
