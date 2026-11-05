#include "single_instance.h"

#include <shellapi.h>

#include <string>

namespace mconnect {
namespace desktop {
namespace {

constexpr wchar_t kMutexName[] =
    L"Local\\com.mconnect.mconnect.single_instance";

// The window class Win32Window registers (see win32_window.cpp). Preferring it
// keeps the hand-off on the main window: the layered lyrics windows belong to
// the same process but ignore WM_COPYDATA.
constexpr wchar_t kMainWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

constexpr DWORD kSendTimeoutMs = 3000;
constexpr int kForwardAttempts = 40;
constexpr DWORD kForwardRetryDelayMs = 50;

HANDLE g_instance_mutex = nullptr;
HWND g_instance_window = nullptr;

std::wstring BaseNameOf(const std::wstring& path) {
  const size_t separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return path;
  }
  return path.substr(separator + 1);
}

std::wstring ExecutableBaseName() {
  wchar_t path[MAX_PATH * 4] = {};
  const DWORD length = GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
  if (length == 0 || length >= ARRAYSIZE(path)) {
    return std::wstring();
  }
  return BaseNameOf(std::wstring(path, length));
}

bool ProcessBaseName(DWORD process_id, std::wstring* name) {
  if (name == nullptr) {
    return false;
  }
  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (process == nullptr) {
    return false;
  }
  wchar_t path[MAX_PATH * 4] = {};
  DWORD length = ARRAYSIZE(path);
  const BOOL ok = QueryFullProcessImageNameW(process, 0, path, &length);
  CloseHandle(process);
  if (ok == FALSE || length == 0) {
    return false;
  }
  *name = BaseNameOf(std::wstring(path, length));
  return true;
}

struct WindowSearch {
  DWORD own_process_id = 0;
  std::wstring executable;
  bool main_class_only = true;
  HWND found = nullptr;
};

BOOL CALLBACK FindWindowProc(HWND window, LPARAM parameter) {
  auto* search = reinterpret_cast<WindowSearch*>(parameter);
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id == 0 || process_id == search->own_process_id) {
    return TRUE;
  }
  if (search->main_class_only) {
    wchar_t class_name[128] = {};
    if (GetClassNameW(window, class_name, ARRAYSIZE(class_name)) <= 0) {
      return TRUE;
    }
    if (lstrcmpiW(class_name, kMainWindowClass) != 0) {
      return TRUE;
    }
  }
  std::wstring name;
  if (!ProcessBaseName(process_id, &name)) {
    return TRUE;
  }
  if (lstrcmpiW(name.c_str(), search->executable.c_str()) != 0) {
    return TRUE;
  }
  search->found = window;
  return FALSE;
}

HWND FindRunningInstanceWindow() {
  if (g_instance_window != nullptr && IsWindow(g_instance_window) != FALSE) {
    return g_instance_window;
  }
  g_instance_window = nullptr;

  WindowSearch search;
  search.own_process_id = GetCurrentProcessId();
  search.executable = ExecutableBaseName();
  if (search.executable.empty()) {
    return nullptr;
  }
  search.main_class_only = true;
  EnumWindows(&FindWindowProc, reinterpret_cast<LPARAM>(&search));
  if (search.found == nullptr) {
    // A first instance whose main window is still being created (or a runner
    // built with a different window class) still owns the app: fall back to any
    // top-level window of that process, which at worst ignores the hand-off.
    search.main_class_only = false;
    EnumWindows(&FindWindowProc, reinterpret_cast<LPARAM>(&search));
  }
  g_instance_window = search.found;
  return search.found;
}

}  // namespace

bool AcquireSingleInstanceMutex() {
  if (g_instance_mutex != nullptr) {
    return true;
  }
  HANDLE mutex = CreateMutexW(nullptr, FALSE, kMutexName);
  if (mutex == nullptr) {
    // Without the mutex the single-instance check cannot answer; starting up is
    // better than refusing to start.
    return true;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(mutex);
    return false;
  }
  g_instance_mutex = mutex;
  return true;
}

std::wstring InitialUriFromProcessCommandLine() {
  int argument_count = 0;
  LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  if (arguments == nullptr) {
    return std::wstring();
  }
  std::wstring uri;
  for (int index = 1; index < argument_count; ++index) {
    const std::wstring candidate(arguments[index]);
    if (candidate.empty()) {
      continue;
    }
    if (candidate.rfind(L"mconnect:", 0) == 0 ||
        candidate.find(L"://") != std::wstring::npos) {
      uri = candidate;
      break;
    }
  }
  LocalFree(arguments);
  return uri;
}

bool ForwardToRunningInstance(const std::wstring& payload) {
  for (int attempt = 0; attempt < kForwardAttempts; ++attempt) {
    HWND window = FindRunningInstanceWindow();
    if (window != nullptr) {
      COPYDATASTRUCT copy_data{};
      copy_data.dwData = kSingleInstanceCopyDataId;
      copy_data.cbData =
          static_cast<DWORD>((payload.size() + 1) * sizeof(wchar_t));
      copy_data.lpData = const_cast<wchar_t*>(payload.c_str());
      DWORD_PTR message_result = 0;
      const LRESULT sent = SendMessageTimeoutW(
          window, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&copy_data),
          SMTO_ABORTIFHUNG | SMTO_BLOCK, kSendTimeoutMs, &message_result);
      // A window that exists but does not answer still means another instance
      // owns the app: this process exits either way, so both outcomes count as
      // a hand-off.
      return sent != 0;
    }
    Sleep(kForwardRetryDelayMs);
  }
  return false;
}

}  // namespace desktop
}  // namespace mconnect
