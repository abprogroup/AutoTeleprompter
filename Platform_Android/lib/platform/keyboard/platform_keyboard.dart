/// Platform-specific keyboard behavior helpers for Android.
///
/// Android phones need the same in-app "Done" affordance as iOS for the
/// script editor because many keyboards do not expose a clear dismiss key.
class PlatformKeyboard {
  const PlatformKeyboard._();

  /// Show a "Done" dismiss bar above the on-screen keyboard.
  static const bool showDoneBar = true;
}
