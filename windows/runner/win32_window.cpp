#include "win32_window.h"

#include <algorithm>
#include <cmath>

#include <dwmapi.h>
#include <flutter_windows.h>
#include <shellscalingapi.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  if (dpi == 0 || dpi == 96) {
    // Flutter 3.47's helper reports 96 for a 175% monitor. Ask the monitor
    // directly so the window is created at the physical size Windows expects.
    UINT dpi_x = 96;
    UINT dpi_y = 96;
    if (SUCCEEDED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
      dpi = dpi_x;
    }
  }
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  // Resize before FlutterViewController is created (OnCreate). Doing this
  // after the first frame (the old ResizeToWorkArea timer) resized the engine
  // surface after it had presented once and left the window black on 175%
  // displays. At this point the HWND already has its real per-monitor DPI, so
  // the logical size and the native client rect can be made to agree before
  // the view exists.
  {
    HMONITOR actual_monitor =
        MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    UINT window_dpi = GetDpiForWindow(window);
    if (window_dpi == 0 || window_dpi == 96) {
      UINT dpi_x = 96;
      UINT dpi_y = 96;
      if (SUCCEEDED(GetDpiForMonitor(actual_monitor, MDT_EFFECTIVE_DPI, &dpi_x,
                                     &dpi_y))) {
        window_dpi = dpi_x;
      }
    }
    if (window_dpi == 0) {
      window_dpi = 96;
    }
    const double window_scale = window_dpi / 96.0;

    int target_x = 0;
    int target_y = 0;
    int physical_width = 0;
    int physical_height = 0;
    bool have_bounds = false;

    // A geometry restored from the previous run wins over the default centred
    // size. The provider has already clamped it into a monitor work area, so
    // the window always comes back on screen even when the monitor it was saved
    // on is gone.
    RECT restored{};
    bool restored_maximized = false;
    if (initial_bounds_provider_ &&
        initial_bounds_provider_(&restored, &restored_maximized)) {
      const int restored_width = static_cast<int>(restored.right - restored.left);
      const int restored_height =
          static_cast<int>(restored.bottom - restored.top);
      if (restored_width > 0 && restored_height > 0) {
        target_x = static_cast<int>(restored.left);
        target_y = static_cast<int>(restored.top);
        physical_width = restored_width;
        physical_height = restored_height;
        start_maximized_ = restored_maximized;
        have_bounds = true;
      }
    }

    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    if (!have_bounds && GetMonitorInfo(actual_monitor, &monitor_info)) {
      const int work_width =
          monitor_info.rcWork.right - monitor_info.rcWork.left;
      const int work_height =
          monitor_info.rcWork.bottom - monitor_info.rcWork.top;
      int logical_width = 1360;
      int logical_height = 860;
      if (logical_width * window_scale > work_width - 40) {
        logical_width = std::max(
            900, static_cast<int>((work_width - 40) / window_scale));
      }
      if (logical_height * window_scale > work_height - 60) {
        logical_height = std::max(
            600, static_cast<int>((work_height - 60) / window_scale));
      }
      physical_width =
          static_cast<int>(std::lround(logical_width * window_scale));
      physical_height =
          static_cast<int>(std::lround(logical_height * window_scale));
      target_x = monitor_info.rcWork.left +
                 std::max(0, (work_width - physical_width) / 2);
      target_y = monitor_info.rcWork.top +
                 std::max(0, (work_height - physical_height) / 2);
      have_bounds = true;
    }

    if (have_bounds) {
      SetWindowPos(window, nullptr, target_x, target_y, physical_width,
                   physical_height, SWP_NOZORDER | SWP_NOACTIVATE);

      // The minimum track size follows the DPI of the monitor the window
      // actually landed on, which after a restore is not necessarily the one
      // |origin| pointed at.
      HMONITOR final_monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
      UINT final_dpi = GetDpiForWindow(window);
      if (final_dpi == 0 || final_dpi == 96) {
        UINT dpi_x = 96;
        UINT dpi_y = 96;
        if (SUCCEEDED(GetDpiForMonitor(final_monitor, MDT_EFFECTIVE_DPI, &dpi_x,
                                       &dpi_y))) {
          final_dpi = dpi_x;
        }
      }
      if (final_dpi == 0) {
        final_dpi = 96;
      }
      const double final_scale = final_dpi / 96.0;
      SetMinimumSize(Size(
          static_cast<int>(std::lround(1024 * final_scale)),
          static_cast<int>(std::lround(600 * final_scale))));
    }
  }

  return OnCreate();
}

bool Win32Window::Show() {
  // A restored "maximized" state is applied as a placement at the moment the
  // window first becomes visible. ShowWindow is not a resize of the engine
  // surface to a computed size: the client rect follows the normal maximise
  // path.
  return ShowWindow(window_handle_,
                    start_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE: {
      // Close behaviour belongs to FlutterWindow / the tray setting now: the
      // old MessageBox asked the question every single time and could not be
      // answered from the settings page.
      if (OnCloseRequested()) {
        return 0;
      }
      DestroyWindow(hwnd);
      return 0;
    }

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_GETMINMAXINFO: {
      auto info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = minimum_size_.width;
      info->ptMinTrackSize.y = minimum_size_.height;
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::SetInitialBoundsProvider(InitialBoundsProvider provider) {
  initial_bounds_provider_ = std::move(provider);
}

void Win32Window::SetMinimumSize(const Size& size) {
  minimum_size_ = size;
}

void Win32Window::SetSize(int width, int height) {
  if (window_handle_ == nullptr) {
    return;
  }
  SetWindowPos(window_handle_, nullptr, 0, 0, width, height,
               SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

bool Win32Window::OnCloseRequested() {
  // No-op; provided for subclasses.
  return false;
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
