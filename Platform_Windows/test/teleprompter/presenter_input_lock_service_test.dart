import 'package:autoteleprompter/features/teleprompter/services/presenter_input_lock_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active manual scroll is allowed only while listening and enabled', () {
    expect(
      PresenterInputLockService.allowActiveManualScroll(
        settingEnabled: true,
        isListening: true,
        isStarting: false,
      ),
      isTrue,
    );
    expect(
      PresenterInputLockService.allowActiveManualScroll(
        settingEnabled: true,
        isListening: false,
        isStarting: true,
      ),
      isFalse,
    );
    expect(
      PresenterInputLockService.allowActiveManualScroll(
        settingEnabled: false,
        isListening: true,
        isStarting: false,
      ),
      isFalse,
    );
  });

  test('windows presenter input locks while speech owns the session', () {
    expect(
      PresenterInputLockService.inputLocked(
        isWindows: true,
        isListening: true,
        isStarting: false,
        allowActiveManualScroll: false,
      ),
      isTrue,
    );
    expect(
      PresenterInputLockService.inputLocked(
        isWindows: true,
        isListening: true,
        isStarting: false,
        allowActiveManualScroll: true,
      ),
      isFalse,
    );
    expect(
      PresenterInputLockService.inputLocked(
        isWindows: false,
        isListening: true,
        isStarting: false,
        allowActiveManualScroll: false,
      ),
      isFalse,
    );
  });
}
