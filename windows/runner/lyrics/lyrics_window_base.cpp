#include "lyrics_window_base.h"

#include <shellscalingapi.h>
#include <windowsx.h>

#include <algorithm>

namespace lyrics {
namespace {

constexpr int kResizeHandleLogical = 24;
constexpr int kMinWindowWidth = 140;
constexpr int kMinWindowHeight = 40;
constexpr int kMaxWindowWidth = 2400;
constexpr int kMaxWindowHeight = 900;

UINT QueryMonitorDpi(HMONITOR monitor) {
  if (monitor == nullptr) {
    return 96;
  }
  UINT dpi_x = 96;
  UINT dpi_y = 96;
  if (SUCCEEDED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y)) &&
      dpi_x > 0) {
    return dpi_x;
  }
  return 96;
}

BOOL CALLBACK MonitorEnumCallback(HMONITOR monitor,
                                  HDC monitor_dc,
                                  LPRECT monitor_rect,
                                  LPARAM data) {
  (void)monitor_dc;
  (void)monitor_rect;
  auto* monitors = reinterpret_cast<std::vector<MonitorInfo>*>(data);
  MONITORINFOEXW info = {};
  info.cbSize = sizeof(MONITORINFOEXW);
  if (GetMonitorInfoW(monitor, &info) == FALSE) {
    return TRUE;
  }
  MonitorInfo entry;
  entry.device_name = info.szDevice;
  entry.bounds = info.rcMonitor;
  entry.dpi = QueryMonitorDpi(monitor);
  entry.is_primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
  monitors->push_back(std::move(entry));
  return TRUE;
}

}  // namespace

bool EnumerateMonitors(std::vector<MonitorInfo>* monitors) {
  if (monitors == nullptr) {
    return false;
  }
  monitors->clear();
  EnumDisplayMonitors(nullptr, nullptr, MonitorEnumCallback,
                      reinterpret_cast<LPARAM>(monitors));
  return !monitors->empty();
}

const MonitorInfo* FindMonitor(const std::vector<MonitorInfo>& monitors,
                               const std::wstring& device_name) {
  if (device_name.empty()) {
    for (const auto& monitor : monitors) {
      if (monitor.is_primary) {
        return &monitor;
      }
    }
    return monitors.empty() ? nullptr : &monitors.front();
  }
  for (const auto& monitor : monitors) {
    if (monitor.device_name == device_name) {
      return &monitor;
    }
  }
  return monitors.empty() ? nullptr : &monitors.front();
}

UINT MonitorDpi(HMONITOR monitor) { return QueryMonitorDpi(monitor); }

std::wstring MonitorDeviceName(HMONITOR monitor) {
  if (monitor == nullptr) {
    return std::wstring();
  }
  MONITORINFOEXW info = {};
  info.cbSize = sizeof(MONITORINFOEXW);
  if (GetMonitorInfoW(monitor, &info) == FALSE) {
    return std::wstring();
  }
  return std::wstring(info.szDevice);
}

LyricsWindowBase::LyricsWindowBase() = default;

LyricsWindowBase::~LyricsWindowBase() { Destroy(); }

bool LyricsWindowBase::Create(const wchar_t* class_name,
                              const wchar_t* title,
                              int width,
                              int height) {
  if (hwnd_ != nullptr) {
    return true;
  }
  class_name_ = class_name;
  WNDCLASSEXW window_class = {};
  window_class.cbSize = sizeof(WNDCLASSEXW);
  window_class.lpfnWndProc = &LyricsWindowBase::WindowProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  window_class.lpszClassName = class_name_.c_str();
  window_class.hbrBackground = nullptr;
  // A layered window manages its own pixels and never paints a background, so
  // the class deliberately has no brush; RegisterClassExW may already know the
  // class from a previous instance and that is fine.
  RegisterClassExW(&window_class);

  width_ = std::max(1, width);
  height_ = std::max(1, height);
  hwnd_ = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW |
                              WS_EX_NOACTIVATE,
                          class_name_.c_str(), title, WS_POPUP, 0, 0, width_,
                          height_, nullptr, nullptr, window_class.hInstance, this);
  if (hwnd_ == nullptr) {
    return false;
  }
  dpi_ = GetDpiForWindow(hwnd_);
  if (dpi_ == 0) {
    dpi_ = 96;
  }
  dpi_scale_ = static_cast<double>(dpi_) / 96.0;
  renderer_.Initialize(hwnd_);
  render_ready_ = true;
  if (renderer_.kind() == RendererKind::kGdiPlus && !renderer_.fallback_reason().empty()) {
    Emit("rendererFallback",
         {{ "reason",
            ArgumentValue::Text(Utf8FromWide(renderer_.fallback_reason())) }});
  }
  return true;
}

void LyricsWindowBase::Destroy() {
  render_ready_ = false;
  StopTimer();
  if (hwnd_ != nullptr) {
    HWND window = hwnd_;
    hwnd_ = nullptr;
    DestroyWindow(window);
  }
  renderer_.Shutdown();
}

void LyricsWindowBase::ShowNoActivate() {
  if (hwnd_ == nullptr) {
    return;
  }
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  RequestFrame();
}

void LyricsWindowBase::Hide() {
  if (hwnd_ == nullptr) {
    return;
  }
  ShowWindow(hwnd_, SW_HIDE);
  StopTimer();
}

bool LyricsWindowBase::visible() const {
  return hwnd_ != nullptr && IsWindowVisible(hwnd_) != FALSE;
}

RECT LyricsWindowBase::bounds() const {
  RECT rect = {};
  if (hwnd_ != nullptr) {
    GetWindowRect(hwnd_, &rect);
  }
  return rect;
}

void LyricsWindowBase::SetBounds(int x,
                                 int y,
                                 int width,
                                 int height,
                                 bool show) {
  if (hwnd_ == nullptr) {
    return;
  }
  width_ = std::max(1, width);
  height_ = std::max(1, height);
  UINT flags = SWP_NOACTIVATE;
  if (show) {
    flags |= SWP_SHOWWINDOW;
  }
  SetWindowPos(hwnd_, topmost_ ? HWND_TOPMOST : HWND_NOTOPMOST, x, y, width_,
               height_, flags);
  RequestFrame();
}

void LyricsWindowBase::SetEventListener(EventListener listener) {
  listener_ = std::move(listener);
}

void LyricsWindowBase::SetTopmost(bool topmost) {
  if (topmost_ == topmost) {
    return;
  }
  topmost_ = topmost;
  if (hwnd_ != nullptr) {
    SetWindowPos(hwnd_, topmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
}

void LyricsWindowBase::SetClickThrough(bool click_through) {
  if (click_through_ == click_through) {
    return;
  }
  click_through_ = click_through;
  // WM_NCHITTEST answers HTTRANSPARENT for click-through windows, and Windows
  // only re-queries it after the pointer moves; nudging the window is the
  // documented way to make the new mode take effect immediately.
  if (hwnd_ != nullptr) {
    SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
  }
}

void LyricsWindowBase::Emit(const std::string& name,
                            const EventArguments& args) {
  if (listener_) {
    listener_(name, args);
  }
}

void LyricsWindowBase::RequestFrame() {
  if (hwnd_ == nullptr) {
    return;
  }
  StartTimer(kFrameIntervalMs);
}

void LyricsWindowBase::StartTimer(UINT interval_ms) {
  if (hwnd_ == nullptr) {
    return;
  }
  interval_ms = std::max<UINT>(8, interval_ms);
  if (timer_id_ != 0 && timer_interval_ == interval_ms) {
    return;
  }
  StopTimer();
  timer_id_ = SetTimer(hwnd_, kFrameTimerId, interval_ms, nullptr);
  timer_interval_ = interval_ms;
}

void LyricsWindowBase::StopTimer() {
  if (hwnd_ != nullptr && timer_id_ != 0) {
    KillTimer(hwnd_, kFrameTimerId);
  }
  timer_id_ = 0;
  timer_interval_ = 0;
}

void LyricsWindowBase::RenderNow() {
  if (hwnd_ == nullptr || !render_ready_) {
    return;
  }
  RenderScene scene;
  scene.width = width_;
  scene.height = height_;
  scene.dpi_scale = dpi_scale_;
  scene.hovered_action = hovered_action_;
  if (!BuildScene(&scene)) {
    return;
  }
  // The window geometry is the single source of truth for the surface size: a
  // scene that disagrees would present a bitmap stretched over the window.
  scene.width = width_;
  scene.height = height_;
  scene.dpi_scale = dpi_scale_;
  renderer_.Render(scene);
}

void LyricsWindowBase::UpdateHover(int x, int y) {
  const std::string action = HitTestAction(x, y);
  if (action == hovered_action_) {
    return;
  }
  hovered_action_ = action;
  RenderNow();
}

void LyricsWindowBase::BeginDrag(int x, int y) {
  POINT cursor = {x, y};
  ClientToScreen(hwnd_, &cursor);
  drag_cursor_ = cursor;
  GetWindowRect(hwnd_, &drag_rect_);
  dragging_ = true;
  SetCapture(hwnd_);
}

LRESULT CALLBACK LyricsWindowBase::WindowProc(HWND hwnd,
                                              UINT message,
                                              WPARAM wparam,
                                              LPARAM lparam) {
  auto* self = reinterpret_cast<LyricsWindowBase*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = static_cast<LyricsWindowBase*>(create->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    if (self != nullptr) {
      self->hwnd_ = hwnd;
    }
  }
  if (self == nullptr) {
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }
  return self->HandleMessage(hwnd, message, wparam, lparam);
}

LRESULT LyricsWindowBase::HandleMessage(HWND hwnd,
                                        UINT message,
                                        WPARAM wparam,
                                        LPARAM lparam) {
  LRESULT custom_result = 0;
  if (OnWindowMessage(message, wparam, lparam, &custom_result)) {
    return custom_result;
  }

  switch (message) {
    case WM_NCCREATE:
      return TRUE;

    case WM_NCDESTROY:
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
      break;

    case WM_DESTROY:
      StopTimer();
      renderer_.Shutdown();
      hwnd_ = nullptr;
      return 0;

    case WM_ERASEBKGND:
      return 1;

    case WM_PAINT: {
      PAINTSTRUCT paint = {};
      BeginPaint(hwnd, &paint);
      EndPaint(hwnd, &paint);
      return 0;
    }

    case WM_TIMER:
      if (wparam == kFrameTimerId) {
        const long long now = NowMilliseconds();
        OnFrameTick(now);
        RenderNow();
        return 0;
      }
      break;

    case WM_NCHITTEST: {
      if (click_through_) {
        return HTTRANSPARENT;
      }
      if (!CanResizeNow()) {
        return HTCLIENT;
      }
      RECT window_rect = {};
      if (GetWindowRect(hwnd, &window_rect) == FALSE) {
        return HTCLIENT;
      }
      const POINT cursor = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      const int handle = static_cast<int>(
          std::lround(static_cast<double>(kResizeHandleLogical) * dpi_scale_));
      if (cursor.x > window_rect.right - handle &&
          cursor.y > window_rect.bottom - handle) {
        return HTBOTTOMRIGHT;
      }
      return HTCLIENT;
    }

    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = static_cast<LONG>(
          std::lround(static_cast<double>(kMinWindowWidth) * dpi_scale_));
      info->ptMinTrackSize.y = static_cast<LONG>(
          std::lround(static_cast<double>(kMinWindowHeight) * dpi_scale_));
      info->ptMaxTrackSize.x = static_cast<LONG>(
          std::lround(static_cast<double>(kMaxWindowWidth) * dpi_scale_));
      info->ptMaxTrackSize.y = static_cast<LONG>(
          std::lround(static_cast<double>(kMaxWindowHeight) * dpi_scale_));
      return 0;
    }

    case WM_SIZE: {
      const int new_width = LOWORD(lparam);
      const int new_height = HIWORD(lparam);
      if (new_width > 0 && new_height > 0) {
        width_ = new_width;
        height_ = new_height;
        RenderNow();
      }
      return 0;
    }

    case WM_MOUSEMOVE: {
      const int x = GET_X_LPARAM(lparam);
      const int y = GET_Y_LPARAM(lparam);
      if (dragging_) {
        POINT cursor = {x, y};
        ClientToScreen(hwnd, &cursor);
        const int delta_x = cursor.x - drag_cursor_.x;
        const int delta_y = cursor.y - drag_cursor_.y;
        SetWindowPos(hwnd, HWND_TOPMOST, drag_rect_.left + delta_x,
                     drag_rect_.top + delta_y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE);
        RenderNow();
        return 0;
      }
      if (!tracking_mouse_) {
        TRACKMOUSEEVENT track = {};
        track.cbSize = sizeof(TRACKMOUSEEVENT);
        track.dwFlags = TME_LEAVE;
        track.hwndTrack = hwnd;
        TrackMouseEvent(&track);
        tracking_mouse_ = true;
      }
      UpdateHover(x, y);
      OnMouseMove(x, y);
      return 0;
    }

    case WM_MOUSELEAVE:
      tracking_mouse_ = false;
      if (!hovered_action_.empty()) {
        hovered_action_.clear();
        RenderNow();
      }
      return 0;

    case WM_LBUTTONDOWN: {
      const int x = GET_X_LPARAM(lparam);
      const int y = GET_Y_LPARAM(lparam);
      const std::string action = HitTestAction(x, y);
      if (!action.empty() && OnAction(action, x, y)) {
        return 0;
      }
      if (CanDragNow()) {
        BeginDrag(x, y);
        return 0;
      }
      break;
    }

    case WM_LBUTTONUP:
      if (dragging_) {
        dragging_ = false;
        ReleaseCapture();
        OnDragFinished();
        RenderNow();
        return 0;
      }
      break;

    case WM_CAPTURECHANGED:
      if (dragging_) {
        dragging_ = false;
        OnDragFinished();
      }
      return 0;

    case WM_ENTERSIZEMOVE:
      // A modal move/size loop started (a resize from the frame, or a
      // move the shell initiated). Programmatic layout must stand down until it
      // ends, or the window jumps back to its stored rectangle.
      resizing_ = true;
      return 0;

    case WM_EXITSIZEMOVE: {
      resizing_ = false;
      RECT window_rect = {};
      if (GetWindowRect(hwnd, &window_rect) != FALSE) {
        width_ = window_rect.right - window_rect.left;
        height_ = window_rect.bottom - window_rect.top;
      }
      OnSizeSettled();
      RenderNow();
      return 0;
    }

    case WM_DPICHANGED: {
      const UINT new_dpi = HIWORD(wparam);
      if (new_dpi != 0) {
        dpi_ = new_dpi;
        dpi_scale_ = static_cast<double>(dpi_) / 96.0;
      }
      const auto* suggested = reinterpret_cast<const RECT*>(lparam);
      if (suggested != nullptr) {
        SetWindowPos(hwnd, nullptr, suggested->left, suggested->top,
                     suggested->right - suggested->left,
                     suggested->bottom - suggested->top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
      }
      OnDpiChanged(dpi_, width_, height_);
      RenderNow();
      return 0;
    }

    case WM_SETTINGCHANGE:
    case WM_DISPLAYCHANGE:
    case WM_THEMECHANGED:
      OnSystemChange(message);
      RenderNow();
      break;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

}  // namespace lyrics
