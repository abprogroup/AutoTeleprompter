/// Platform-specific keyboard behavior helpers for Android.
///
/// Android's system keyboard includes a built-in dismiss button in the
/// navigation bar — no in-app "Done" toolbar is needed.
class PlatformKeyboard {
  const PlatformKeyboard._();

  /// Always false on Android — the system keyboard has its own dismiss control.
  static const bool showDoneBar = false;
}
