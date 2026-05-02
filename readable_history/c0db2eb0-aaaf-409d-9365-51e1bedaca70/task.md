# Execution Tasks: Native Windows SAPI Pivot

- [x] Add the embedded Browser method to the `MASTER_TODO_V5.md` as a future premium fallback option matching the user's instructions.
- [x] Remove `webview_windows`, `shelf`, `shelf_router`, `shelf_web_socket`, and `web_socket_channel` from `Platform_Windows/pubspec.yaml`.
- [x] Delete `Platform_Windows/lib/platform/stt/stt_browser_adapter.dart`.
- [x] Update `Platform_Windows/lib/platform/stt/stt_service_factory.dart` to return `SttDesktopAdapter` for Windows.
- [x] Rewrite `_showMissingLanguageDialog` in `teleprompter_screen.dart` to include Microsoft Windows deep-link prompts (`ms-settings:speech`).
- [x] Remove all `WebviewController` variables, hooks, and presentation widgets out of `teleprompter_screen.dart`.
