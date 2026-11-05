#include "window_state_store.h"

#include <objbase.h>
#include <shlobj.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace mconnect {
namespace desktop {
namespace {

constexpr wchar_t kDataDirEnvironment[] = L"MCONNECT_DATA_DIR";
constexpr wchar_t kStateFileName[] = L"window_state.json";
constexpr wchar_t kTemporarySuffix[] = L".tmp";
constexpr uint64_t kMaxStateFileBytes = 64 * 1024;

// Bounds used when a stored state is brought back on screen. They are
// deliberately generous: the window's own minimum track size is enforced by
// Win32Window, these only reject nonsense values (0, negative, absurd).
constexpr int kMinimumWidth = 320;
constexpr int kMinimumHeight = 200;
constexpr int kMinimumVisibleWidth = 160;
constexpr int kMinimumVisibleHeight = 48;

std::wstring TrimTrailingSeparators(std::wstring value) {
  while (!value.empty() && (value.back() == L'\\' || value.back() == L'/')) {
    value.pop_back();
  }
  return value;
}

bool EnsureDirectory(const std::wstring& path) {
  if (path.empty()) {
    return false;
  }
  const int result = SHCreateDirectoryExW(nullptr, path.c_str(), nullptr);
  return result == ERROR_SUCCESS || result == ERROR_ALREADY_EXISTS ||
         result == ERROR_FILE_EXISTS;
}

bool ReadTextFile(const std::wstring& path, std::string* contents) {
  if (contents == nullptr) {
    return false;
  }
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 ||
      static_cast<uint64_t>(size.QuadPart) > kMaxStateFileBytes) {
    CloseHandle(file);
    return false;
  }
  contents->assign(static_cast<size_t>(size.QuadPart), '\0');
  DWORD read = 0;
  const BOOL ok = ReadFile(file, contents->data(),
                           static_cast<DWORD>(contents->size()), &read, nullptr);
  CloseHandle(file);
  if (ok == FALSE) {
    contents->clear();
    return false;
  }
  contents->resize(read);
  return true;
}

bool WriteTextFile(const std::wstring& path, const std::string& contents) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  DWORD written = 0;
  const BOOL ok = WriteFile(file, contents.data(),
                            static_cast<DWORD>(contents.size()), &written,
                            nullptr);
  FlushFileBuffers(file);
  CloseHandle(file);
  return ok != FALSE && written == static_cast<DWORD>(contents.size());
}

// Position of |key|'s value inside |json|, or std::string::npos.
//
// A hand-written scanner rather than a JSON library: the file is ours, the
// schema is five flat scalars, and refusing to parse anything else is exactly
// the behaviour we want for a corrupt or foreign file.
size_t FindValueStart(const std::string& json, const char* key) {
  const std::string pattern = std::string("\"") + key + "\"";
  size_t position = json.find(pattern);
  while (position != std::string::npos) {
    size_t cursor = position + pattern.size();
    while (cursor < json.size() &&
           (json[cursor] == ' ' || json[cursor] == '\t' || json[cursor] == '\r' ||
            json[cursor] == '\n')) {
      ++cursor;
    }
    if (cursor < json.size() && json[cursor] == ':') {
      ++cursor;
      while (cursor < json.size() &&
             (json[cursor] == ' ' || json[cursor] == '\t' ||
              json[cursor] == '\r' || json[cursor] == '\n')) {
        ++cursor;
      }
      return cursor;
    }
    position = json.find(pattern, position + pattern.size());
  }
  return std::string::npos;
}

bool ParseInt(const std::string& json, const char* key, int* value) {
  if (value == nullptr) {
    return false;
  }
  const size_t start = FindValueStart(json, key);
  if (start == std::string::npos) {
    return false;
  }
  const char* begin = json.c_str() + start;
  char* end = nullptr;
  const long parsed = std::strtol(begin, &end, 10);
  if (end == begin) {
    return false;
  }
  *value = static_cast<int>(parsed);
  return true;
}

bool ParseBool(const std::string& json, const char* key, bool* value) {
  if (value == nullptr) {
    return false;
  }
  const size_t start = FindValueStart(json, key);
  if (start == std::string::npos) {
    return false;
  }
  if (json.compare(start, 4, "true") == 0 || json.compare(start, 1, "1") == 0) {
    *value = true;
    return true;
  }
  if (json.compare(start, 5, "false") == 0 ||
      json.compare(start, 1, "0") == 0) {
    *value = false;
    return true;
  }
  return false;
}

}  // namespace

std::wstring DataDirectory() {
  wchar_t buffer[32768] = {};
  const DWORD length =
      GetEnvironmentVariableW(kDataDirEnvironment, buffer, 32768);
  if (length > 0 && length < 32768) {
    const std::wstring from_environment(buffer, length);
    if (!from_environment.empty()) {
      return TrimTrailingSeparators(from_environment);
    }
  }

  std::wstring root;
  PWSTR local_app_data = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE,
                                     nullptr, &local_app_data)) &&
      local_app_data != nullptr) {
    root = local_app_data;
  }
  CoTaskMemFree(local_app_data);
  if (root.empty()) {
    wchar_t profile[32768] = {};
    const DWORD profile_length =
        GetEnvironmentVariableW(L"USERPROFILE", profile, 32768);
    if (profile_length > 0 && profile_length < 32768) {
      root.assign(profile, profile_length);
    }
  }
  return TrimTrailingSeparators(root) + L"\\com.mconnect\\mconnect";
}

std::wstring WindowStatePath() {
  return DataDirectory() + L"\\" + kStateFileName;
}

bool LoadWindowState(WindowState* state) {
  if (state == nullptr) {
    return false;
  }
  std::string contents;
  if (!ReadTextFile(WindowStatePath(), &contents)) {
    return false;
  }

  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
  bool maximized = false;
  const bool has_position =
      ParseInt(contents, "x", &x) && ParseInt(contents, "y", &y);
  if (!ParseInt(contents, "width", &width) ||
      !ParseInt(contents, "height", &height) || width <= 0 || height <= 0) {
    return false;
  }
  ParseBool(contents, "maximized", &maximized);

  state->x = has_position ? x : 0;
  state->y = has_position ? y : 0;
  state->width = width;
  state->height = height;
  state->maximized = maximized;
  state->valid = true;
  return true;
}

bool SaveWindowState(const WindowState& state) {
  if (state.width <= 0 || state.height <= 0) {
    return false;
  }
  const std::wstring directory = DataDirectory();
  if (!EnsureDirectory(directory)) {
    return false;
  }

  char buffer[512] = {};
  const int written = std::snprintf(
      buffer, sizeof(buffer),
      "{\n"
      "  \"x\": %d,\n"
      "  \"y\": %d,\n"
      "  \"width\": %d,\n"
      "  \"height\": %d,\n"
      "  \"maximized\": %s\n"
      "}\n",
      state.x, state.y, state.width, state.height,
      state.maximized ? "true" : "false");
  if (written <= 0 || written >= static_cast<int>(sizeof(buffer))) {
    return false;
  }

  const std::wstring path = WindowStatePath();
  const std::wstring temporary = path + kTemporarySuffix;
  if (!WriteTextFile(temporary, std::string(buffer, static_cast<size_t>(written)))) {
    return false;
  }
  if (MoveFileExW(temporary.c_str(), path.c_str(),
                  MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) == FALSE) {
    DeleteFileW(temporary.c_str());
    return false;
  }
  return true;
}

bool DeleteWindowState() {
  const std::wstring path = WindowStatePath();
  const std::wstring temporary = path + kTemporarySuffix;
  DeleteFileW(temporary.c_str());
  if (DeleteFileW(path.c_str()) != FALSE) {
    return true;
  }
  return GetLastError() == ERROR_FILE_NOT_FOUND;
}

bool ClampWindowStateToWorkArea(WindowState* state) {
  if (state == nullptr || state->width <= 0 || state->height <= 0) {
    return false;
  }

  RECT bounds{state->x, state->y, state->x + state->width,
              state->y + state->height};
  HMONITOR monitor = MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (monitor == nullptr || GetMonitorInfoW(monitor, &info) == FALSE) {
    return false;
  }

  const int work_width = static_cast<int>(info.rcWork.right - info.rcWork.left);
  const int work_height =
      static_cast<int>(info.rcWork.bottom - info.rcWork.top);
  if (work_width <= 0 || work_height <= 0) {
    return false;
  }

  state->width = std::max(kMinimumWidth, std::min(state->width, work_width));
  state->height = std::max(kMinimumHeight, std::min(state->height, work_height));

  // Keep the title bar reachable: the left edge may hang off the screen, the
  // top edge may not, and at least kMinimumVisibleWidth of the frame stays
  // inside the work area horizontally.
  const int minimum_x =
      static_cast<int>(info.rcWork.left) - state->width + kMinimumVisibleWidth;
  const int maximum_x =
      static_cast<int>(info.rcWork.right) - kMinimumVisibleWidth;
  const int minimum_y = static_cast<int>(info.rcWork.top);
  const int maximum_y =
      static_cast<int>(info.rcWork.bottom) - kMinimumVisibleHeight;
  state->x = std::max(minimum_x, std::min(state->x, maximum_x));
  state->y = std::max(minimum_y, std::min(state->y, maximum_y));
  state->valid = true;
  return true;
}

bool LoadWindowRectForCreate(RECT* rect, bool* maximized) {
  if (rect == nullptr) {
    return false;
  }
  WindowState state;
  if (!LoadWindowState(&state) || !ClampWindowStateToWorkArea(&state)) {
    return false;
  }
  rect->left = state.x;
  rect->top = state.y;
  rect->right = state.x + state.width;
  rect->bottom = state.y + state.height;
  if (maximized != nullptr) {
    *maximized = state.maximized;
  }
  return true;
}

}  // namespace desktop
}  // namespace mconnect
