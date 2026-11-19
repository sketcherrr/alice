#include "flutter_window.h"

#include <optional>
#include <algorithm>
#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

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

  const HWND window = GetHandle();
  // A transparent composition surface, rather than global window opacity:
  // the character and its antialiased edges keep their original alpha.
  struct AccentPolicy { int state; int flags; int color; int animation; };
  struct CompositionData { int attribute; void* data; SIZE_T size; };
  using SetComposition = BOOL(WINAPI*)(HWND, CompositionData*);
  const HMODULE user32 = GetModuleHandleW(L"user32.dll");
  const auto set_composition = reinterpret_cast<SetComposition>(
      GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (set_composition) {
    AccentPolicy policy{2, 2, 0, 0};
    CompositionData data{19, &policy, sizeof(policy)};
    set_composition(window, &data);
  }
  MARGINS margins{-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(window, &margins);
  SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  desktop_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "alice/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  desktop_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const HWND hwnd = GetHandle();
    const bool value = call.arguments() && std::holds_alternative<bool>(*call.arguments()) && std::get<bool>(*call.arguments());
    if (call.method_name() == "expanded") {
      RECT old; GetWindowRect(hwnd, &old);
      MONITORINFO info{sizeof(MONITORINFO)};
      GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &info);
      const double dpi = FlutterDesktopGetDpiForHWND(hwnd) / 96.0;
      const int width = (std::min)(static_cast<int>((value ? 500 : 360) * dpi), static_cast<int>(info.rcWork.right - info.rcWork.left));
      const int height = (std::min)(static_cast<int>((value ? 780 : 520) * dpi), static_cast<int>(info.rcWork.bottom - info.rcWork.top));
      const int x = (std::max)(static_cast<int>(info.rcWork.left), (std::min)(static_cast<int>(old.right) - width, static_cast<int>(info.rcWork.right) - width));
      const int y = (std::max)(static_cast<int>(info.rcWork.top), (std::min)(static_cast<int>(old.bottom) - height, static_cast<int>(info.rcWork.bottom) - height));
      SetWindowPos(hwnd, nullptr, x, y, width, height, SWP_NOZORDER);
      SetForegroundWindow(hwnd);
    } else if (call.method_name() == "drag") {
      ReleaseCapture();
      PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
    } else if (call.method_name() == "onTop") {
      SetWindowPos(hwnd, value ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    } else if (call.method_name() == "close") {
      PostMessage(hwnd, WM_CLOSE, 0, 0);
    } else { result->NotImplemented(); return; }
    result->Success();
  });

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
  desktop_channel_.reset();
  if (flutter_controller_) {
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
