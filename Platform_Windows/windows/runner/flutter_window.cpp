#include "flutter_window.h"

#include <windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  RegisterPresenterWindowChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  SetPresenterFullscreen(false);
  if (flutter_controller_) {
    presenter_window_channel_ = nullptr;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::RegisterPresenterWindowChannel() {
  presenter_window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "autoteleprompter/window",
          &flutter::StandardMethodCodec::GetInstance());

  presenter_window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setPresenterFullscreen") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (!enabled) {
            result->Error("bad_args", "Expected a boolean fullscreen value.");
            return;
          }
          const bool applied = SetPresenterFullscreen(*enabled);
          result->Success(flutter::EncodableValue(applied));
          return;
        }
        if (call.method_name() == "isPresenterFullscreen") {
          result->Success(flutter::EncodableValue(presenter_fullscreen_));
          return;
        }
        result->NotImplemented();
      });
}

bool FlutterWindow::SetPresenterFullscreen(bool enabled) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return false;
  }

  if (enabled == presenter_fullscreen_) {
    return presenter_fullscreen_;
  }

  if (enabled) {
    windowed_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
    windowed_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    windowed_placement_ = {};
    windowed_placement_.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(hwnd, &windowed_placement_);

    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitor_info = {};
    monitor_info.cbSize = sizeof(MONITORINFO);
    if (!GetMonitorInfo(monitor, &monitor_info)) {
      return false;
    }

    const LONG_PTR fullscreen_style =
        windowed_style_ &
        ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX |
          WS_SYSMENU);
    const LONG_PTR fullscreen_ex_style =
        windowed_ex_style_ &
        ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE |
          WS_EX_STATICEDGE);

    SetWindowLongPtr(hwnd, GWL_STYLE, fullscreen_style);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, fullscreen_ex_style);
    SetWindowPos(hwnd, HWND_TOPMOST, monitor_info.rcMonitor.left,
                 monitor_info.rcMonitor.top,
                 monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
                 monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
                 SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    presenter_fullscreen_ = true;
    return true;
  }

  SetWindowLongPtr(hwnd, GWL_STYLE, windowed_style_);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, windowed_ex_style_);
  windowed_placement_.length = sizeof(WINDOWPLACEMENT);
  SetWindowPlacement(hwnd, &windowed_placement_);
  SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOOWNERZORDER |
                   SWP_FRAMECHANGED);
  presenter_fullscreen_ = false;
  return false;
}
