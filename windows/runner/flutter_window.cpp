#include "flutter_window.h"

#include <optional>

#include <shellscalingapi.h>

#include "desktop/window_state_store.h"
#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {
  // Restored geometry is provided to Win32Window::Create, i.e. before the
  // Flutter view is constructed: the engine surface is created at the final
  // size and never resized after its first frame.
  SetInitialBoundsProvider([](RECT* bounds, bool* maximized) {
    return mconnect::desktop::LoadWindowRectForCreate(bounds, maximized);
  });
}

void FlutterWindow::SetInitialUri(std::wstring uri) {
  initial_uri_ = std::move(uri);
}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The FlutterViewController constructor interprets the size it is given as
  // *logical* pixels and multiplies it by the view DPI. Passing the raw client
  // rect (physical pixels) therefore created a 1.75x-too-large framebuffer on a
  // 175% display. Convert to logical first so the framebuffer exactly matches
  // the window.
  UINT dpi = GetDpiForWindow(GetHandle());
  if (dpi == 0 || dpi == 96) {
    HMONITOR monitor = MonitorFromWindow(GetHandle(), MONITOR_DEFAULTTONEAREST);
    UINT dpi_x = 96;
    UINT dpi_y = 96;
    if (SUCCEEDED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
      dpi = dpi_x;
    }
  }
  const double scale = dpi > 0 ? dpi / 96.0 : 1.0;
  const int logical_width =
      static_cast<int>((frame.right - frame.left) / scale);
  const int logical_height =
      static_cast<int>((frame.bottom - frame.top) / scale);

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      logical_width, logical_height, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  floating_lyrics_channel_ = std::make_unique<FloatingLyricsChannel>(
      flutter_controller_->engine()->messenger());
  file_opener_channel_ = std::make_unique<FileOpenerChannel>(
      flutter_controller_->engine()->messenger());
  // SMTC / tray / window state / hotkeys / single-instance hand-off. Created
  // before the first frame so a forwarded URI and the very first
  // setMediaMetadata both have a handler waiting.
  desktop_integration_channel_ =
      std::make_unique<mconnect::desktop::DesktopIntegrationChannel>(
          GetHandle(), flutter_controller_->engine()->messenger(),
          std::move(initial_uri_));
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    // Destroyed while the messenger is still valid: the channel unregisters its
    // handler, removes the tray icon and releases the SMTC session.
    desktop_integration_channel_ = nullptr;
    file_opener_channel_ = nullptr;
    floating_lyrics_channel_ = nullptr;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::OnCloseRequested() {
  if (desktop_integration_channel_) {
    return desktop_integration_channel_->HandleCloseRequest();
  }
  return false;
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  // Close-to-tray must answer WM_CLOSE before anything else looks at it.
  // Flutter 3.47's WindowsLifecycleManager routes the first WM_CLOSE through
  // System.requestAppExit, and the answer from Dart arrives too late for the
  // tray path: the window had already closed for real. Handling it here keeps
  // the close synchronous; a false answer falls through to the original
  // behaviour and lets Win32Window destroy the window.
  if (message == WM_CLOSE && desktop_integration_channel_ &&
      desktop_integration_channel_->HandleCloseRequest()) {
    return 0;
  }

  // Tray, hotkeys, the single-instance hand-off and SMTC requests are ours to
  // consume; the idle notifications (WM_SIZE, WM_EXITSIZEMOVE) are only
  // observed and still reach Flutter and DefWindowProc.
  if (desktop_integration_channel_) {
    LRESULT integration_result = 0;
    if (desktop_integration_channel_->HandleWindowMessage(
            hwnd, message, wparam, lparam, &integration_result)) {
      return integration_result;
    }
  }

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
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
