#include "flutter_window.h"

#include <windows.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "windows_mic_volume.h"

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
  RegisterWindowsMicVolumeChannel();

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
    windows_mic_volume_channel_ = nullptr;
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
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
    case WM_DPICHANGED:
    case WM_DISPLAYCHANGE:
      if (presenter_fullscreen_) {
        SnapFullscreenToCurrentMonitor();
        return 0;
      }
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

void FlutterWindow::RegisterWindowsMicVolumeChannel() {
  windows_mic_volume_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "autoteleprompter/windows_mic_volume",
          &flutter::StandardMethodCodec::GetInstance());

  auto to_encodable = [](const WindowsMicVolumeState& state) {
    flutter::EncodableMap map;
    map[flutter::EncodableValue("available")] =
        flutter::EncodableValue(state.available);
    map[flutter::EncodableValue("volumePercent")] =
        flutter::EncodableValue(state.volume_percent);
    map[flutter::EncodableValue("muted")] =
        flutter::EncodableValue(state.muted);
    map[flutter::EncodableValue("deviceName")] =
        flutter::EncodableValue(state.device_name);
    map[flutter::EncodableValue("error")] =
        flutter::EncodableValue(state.error);
    return flutter::EncodableValue(map);
  };

  windows_mic_volume_channel_->SetMethodCallHandler(
      [to_encodable](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        std::string preferred_label;
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (args) {
          auto it = args->find(flutter::EncodableValue("preferredLabel"));
          if (it != args->end()) {
            if (const auto* s = std::get_if<std::string>(&it->second)) {
              preferred_label = *s;
            }
          }
        }

        if (call.method_name() == "getMicVolume") {
          result->Success(to_encodable(GetWindowsMicVolume(preferred_label)));
          return;
        }

        if (call.method_name() == "setMicVolume") {
          int volume_percent = 100;
          std::optional<bool> muted;
          if (args) {
            auto vol_it = args->find(flutter::EncodableValue("volumePercent"));
            if (vol_it != args->end()) {
              if (const auto* v = std::get_if<int32_t>(&vol_it->second)) {
                volume_percent = *v;
              } else if (const auto* d = std::get_if<double>(&vol_it->second)) {
                volume_percent = static_cast<int>(*d);
              }
            }
            auto mute_it = args->find(flutter::EncodableValue("muted"));
            if (mute_it != args->end()) {
              if (const auto* m = std::get_if<bool>(&mute_it->second)) {
                muted = *m;
              }
            }
          }
          result->Success(to_encodable(
              SetWindowsMicVolume(preferred_label, volume_percent, muted)));
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
    // Borderless fullscreen using HWND_TOP covers the taskbar automatically
    // without trapping Alt+Tab or system dialogs behind HWND_TOPMOST.
    SetWindowPos(hwnd, HWND_TOP, monitor_info.rcMonitor.left,
                 monitor_info.rcMonitor.top,
                 monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
                 monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
                 SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    presenter_fullscreen_ = true;
    return true;
  }

  if (windowed_style_ != 0) {
    SetWindowLongPtr(hwnd, GWL_STYLE, windowed_style_);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, windowed_ex_style_);
    windowed_placement_.length = sizeof(WINDOWPLACEMENT);
    SetWindowPlacement(hwnd, &windowed_placement_);
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED);
  }
  presenter_fullscreen_ = false;
  return false;
}

void FlutterWindow::SnapFullscreenToCurrentMonitor() {
  HWND hwnd = GetHandle();
  if (!hwnd || !presenter_fullscreen_) {
    return;
  }
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return;
  }
  SetWindowPos(hwnd, HWND_TOP, monitor_info.rcMonitor.left,
               monitor_info.rcMonitor.top,
               monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
               monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
               SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_NOACTIVATE);
}
