#include "desktop_integration_channel.h"

#include <dwmapi.h>
#include <shellapi.h>
// IsUserAnAdmin() lives in shlobj; the status card uses it to explain why a
// shell running at a different integrity level may refuse the tray icon.
#include <shlobj.h>
#include <windowsx.h>

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <iterator>
#include <string>
#include <vector>

#include "../resource.h"
#include "single_instance.h"

#ifndef NIF_SHOWTIP
#define NIF_SHOWTIP 0x00000080
#endif

namespace mconnect {
namespace desktop {
namespace {

constexpr char kChannelName[] = "com.mconnect.mconnect/desktop_integration";

// Fallback only: the live id is DesktopIntegrationChannel::tray_icon_id_, set
// per process in Initialize().
constexpr UINT kTrayIconId = 1;

// Opt-in file logging for the tray registration path.
//
// The tray icon failed silently for two releases: the shell said no, the app
// answered with a generic fallback, and there was no way to see which call was
// refused once the process was gone. Setting MCONNECT_TRAY_DEBUG=1 writes the
// sequence to %TEMP%\mconnect-tray-debug.log; production stays quiet.
void TrayDebugLog(const std::string& line) {
  // The logger must not disturb GetLastError(): the caller uses it to report the
  // shell's answer, and our own file I/O was overwriting it with things like
  // ERROR_ENVVAR_NOT_FOUND (203) — which is why the status card once claimed 203.
  const DWORD saved_error = GetLastError();
  wchar_t flag[8] = {};
  if (GetEnvironmentVariableW(L"MCONNECT_TRAY_DEBUG", flag,
                              static_cast<DWORD>(std::size(flag))) == 0) {
    SetLastError(saved_error);
    return;
  }
  wchar_t temp[32768] = {};
  const DWORD temp_length =
      GetTempPathW(static_cast<DWORD>(std::size(temp)), temp);
  if (temp_length == 0) {
    SetLastError(saved_error);
    return;
  }
  const std::wstring path =
      std::wstring(temp, temp_length) + L"mconnect-tray-debug.log";
  HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                            nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    SetLastError(saved_error);
    return;
  }
  const std::string text = line + "\n";
  DWORD written = 0;
  WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written,
            nullptr);
  CloseHandle(file);
  SetLastError(saved_error);
}

// The tray icon gets its own hidden top-level window instead of borrowing the
// Flutter window. Registering against the Flutter window failed in practice
// (three flag sets in a row) while a plain window in the same session is
// accepted, and a dedicated host keeps the icon alive across a view rebuild.
constexpr wchar_t kTrayHostClass[] = L"MCONNECT_TRAY_HOST";

// Second registration strategy: a GUID-anchored icon. The shell keys that by
// GUID instead of by (window, id), which is the escape hatch for a window whose
// slot-based registration keeps being refused.
constexpr GUID kTrayIconGuid = {
    0x9f1c2a44,
    0x3b7e,
    0x4d21,
    {0xa6, 0x11, 0x5c, 0x0d, 0x2f, 0x90, 0x8e, 0x41}};

struct TrayHostContext {
  HWND target = nullptr;
  UINT tray_message = 0;
  UINT taskbar_created = 0;
};

// The process hosts exactly one channel, so one context is enough.
TrayHostContext g_tray_host{};

LRESULT CALLBACK TrayHostProc(HWND hwnd,
                              UINT message,
                              WPARAM wparam,
                              LPARAM lparam) {
  // Hand the shell's notifications to the window that already implements the
  // menu, the balloon and the TaskbarCreated recovery.
  if (message == g_tray_host.tray_message ||
      (g_tray_host.taskbar_created != 0 &&
       message == g_tray_host.taskbar_created)) {
    if (g_tray_host.target != nullptr) {
      PostMessageW(g_tray_host.target, message, wparam, lparam);
    }
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
// Our own timer ids: the main window does not otherwise use WM_TIMER.
constexpr UINT_PTR kStateSaveTimerId = 0x4D50;
constexpr UINT_PTR kTrayRetryTimerId = 0x4D51;
constexpr UINT kStateSaveDelayMs = 600;
constexpr UINT kTrayRetryBaseDelayMs = 1000;
constexpr UINT kTrayRetryMaxDelayMs = 30000;
constexpr int kHotkeyBaseId = 0x4D60;

std::string Utf8FromWide(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  if (size <= 0) {
    return std::string();
  }
  std::string result(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

std::wstring WideFromUtf8(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

// EncodableValue's const char* constructor resolves to bool, so every map key
// and string value goes through std::string explicitly.
flutter::EncodableValue Text(const std::string& value) {
  return flutter::EncodableValue(value);
}

const flutter::EncodableValue* FindArgument(const flutter::EncodableMap& arguments,
                                            const char* key) {
  const auto found = arguments.find(Text(key));
  if (found == arguments.end()) {
    return nullptr;
  }
  return &found->second;
}

bool ArgumentBool(const flutter::EncodableMap& arguments,
                  const char* key,
                  bool fallback) {
  const flutter::EncodableValue* value = FindArgument(arguments, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* flag = std::get_if<bool>(value)) {
    return *flag;
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return *number != 0;
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return *number != 0;
  }
  return fallback;
}

int64_t ArgumentInt(const flutter::EncodableMap& arguments,
                    const char* key,
                    int64_t fallback) {
  const flutter::EncodableValue* value = FindArgument(arguments, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<double>(value)) {
    return static_cast<int64_t>(*number);
  }
  return fallback;
}

std::string ArgumentString(const flutter::EncodableMap& arguments,
                           const char* key,
                           const std::string& fallback) {
  const flutter::EncodableValue* value = FindArgument(arguments, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* text = std::get_if<std::string>(value)) {
    return *text;
  }
  return fallback;
}

flutter::EncodableMap ActionArguments(const std::string& action) {
  flutter::EncodableMap arguments;
  arguments[Text("action")] = Text(action);
  return arguments;
}

flutter::EncodableMap WindowStateArguments(const WindowState& state) {
  flutter::EncodableMap arguments;
  arguments[Text("x")] = flutter::EncodableValue(state.x);
  arguments[Text("y")] = flutter::EncodableValue(state.y);
  arguments[Text("width")] = flutter::EncodableValue(state.width);
  arguments[Text("height")] = flutter::EncodableValue(state.height);
  arguments[Text("maximized")] = flutter::EncodableValue(state.maximized);
  return arguments;
}

std::wstring BuildTooltip(const std::wstring& title,
                          const std::wstring& artist) {
  if (title.empty()) {
    return L"Mconnect";
  }
  std::wstring tooltip = L"Mconnect \u00B7 " + title;
  if (!artist.empty()) {
    tooltip += L" \u2014 " + artist;
  }
  return tooltip;
}

struct ParsedHotkey {
  bool valid = false;
  UINT modifiers = 0;
  UINT virtual_key = 0;
};

std::string TrimAscii(const std::string& value) {
  size_t begin = 0;
  size_t end = value.size();
  while (begin < end &&
         (value[begin] == ' ' || value[begin] == '\t' || value[begin] == '\r' ||
          value[begin] == '\n')) {
    ++begin;
  }
  while (end > begin &&
         (value[end - 1] == ' ' || value[end - 1] == '\t' ||
          value[end - 1] == '\r' || value[end - 1] == '\n')) {
    --end;
  }
  return value.substr(begin, end - begin);
}

std::string ToLowerAscii(std::string value) {
  for (char& character : value) {
    if (character >= 'A' && character <= 'Z') {
      character = static_cast<char>(character - 'A' + 'a');
    }
  }
  return value;
}

bool VirtualKeyFromName(const std::string& name, UINT* virtual_key) {
  if (virtual_key == nullptr || name.empty()) {
    return false;
  }
  if (name.size() == 1) {
    const char character = name[0];
    if (character >= 'a' && character <= 'z') {
      *virtual_key = static_cast<UINT>(character - 'a' + 'A');
      return true;
    }
    if (character >= '0' && character <= '9') {
      *virtual_key = static_cast<UINT>(character);
      return true;
    }
  }
  if (name.size() >= 2 && name.size() <= 3 && name[0] == 'f') {
    const int index = std::atoi(name.c_str() + 1);
    if (index >= 1 && index <= 24) {
      *virtual_key = static_cast<UINT>(VK_F1 + index - 1);
      return true;
    }
  }
  static const struct {
    const char* name;
    UINT virtual_key;
  } kNamedKeys[] = {
      {"space", VK_SPACE},           {"enter", VK_RETURN},
      {"return", VK_RETURN},         {"tab", VK_TAB},
      {"escape", VK_ESCAPE},         {"esc", VK_ESCAPE},
      {"backspace", VK_BACK},        {"delete", VK_DELETE},
      {"insert", VK_INSERT},         {"home", VK_HOME},
      {"end", VK_END},               {"pageup", VK_PRIOR},
      {"pagedown", VK_NEXT},         {"up", VK_UP},
      {"down", VK_DOWN},             {"left", VK_LEFT},
      {"right", VK_RIGHT},           {"mediaplaypause", VK_MEDIA_PLAY_PAUSE},
      {"medianext", VK_MEDIA_NEXT_TRACK},
      {"mediaprev", VK_MEDIA_PREV_TRACK},
      {"mediastop", VK_MEDIA_STOP},  {"volumeup", VK_VOLUME_UP},
      {"volumedown", VK_VOLUME_DOWN},
      {"mute", VK_VOLUME_MUTE},
  };
  for (const auto& entry : kNamedKeys) {
    if (name == entry.name) {
      *virtual_key = entry.virtual_key;
      return true;
    }
  }
  return false;
}

// "Ctrl+Alt+L", "ctrl+shift+space", "Win+F5", "MediaPlayPause".
ParsedHotkey ParseHotkey(const std::string& text) {
  ParsedHotkey parsed;
  std::vector<std::string> tokens;
  std::string current;
  for (const char character : text) {
    if (character == '+') {
      const std::string token = TrimAscii(current);
      if (!token.empty()) {
        tokens.push_back(ToLowerAscii(token));
      }
      current.clear();
    } else {
      current.push_back(character);
    }
  }
  const std::string tail = TrimAscii(current);
  if (!tail.empty()) {
    tokens.push_back(ToLowerAscii(tail));
  }
  if (tokens.empty()) {
    return parsed;
  }

  UINT modifiers = 0;
  UINT virtual_key = 0;
  for (size_t index = 0; index < tokens.size(); ++index) {
    const std::string& token = tokens[index];
    const bool is_last = index + 1 == tokens.size();
    if (!is_last) {
      if (token == "ctrl" || token == "control") {
        modifiers |= MOD_CONTROL;
        continue;
      }
      if (token == "alt") {
        modifiers |= MOD_ALT;
        continue;
      }
      if (token == "shift") {
        modifiers |= MOD_SHIFT;
        continue;
      }
      if (token == "win" || token == "meta" || token == "super" ||
          token == "cmd") {
        modifiers |= MOD_WIN;
        continue;
      }
      return parsed;
    }
    if (!VirtualKeyFromName(token, &virtual_key)) {
      return parsed;
    }
  }
  if (virtual_key == 0) {
    return parsed;
  }
  parsed.modifiers = modifiers;
  parsed.virtual_key = virtual_key;
  parsed.valid = true;
  return parsed;
}

// Never answers nullptr.
//
// The old version answered whatever LoadImageW said, and a null handle is why
// AddTrayIcon used to give up before even calling the shell: the user then had
// "关闭到托盘" switched on with no tray icon to hide into. A generic Windows
// icon is still infinitely better than "the window disappeared and the process
// is gone", so each fallback below is tried in turn:
//   small app icon -> default-size app icon -> module icon -> stock IDI_APPLICATION.
HICON LoadTrayIcon() {
  HINSTANCE instance = GetModuleHandleW(nullptr);
  const int width = GetSystemMetrics(SM_CXSMICON);
  const int height = GetSystemMetrics(SM_CYSMICON);
  HICON icon = static_cast<HICON>(LoadImageW(
      instance, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON, width, height,
      LR_SHARED));
  if (icon == nullptr) {
    // Some resource layouts fail the explicitly-scaled load while the default
    // size still resolves.
    icon = static_cast<HICON>(LoadImageW(
        instance, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON, 0, 0, LR_SHARED));
  }
  if (icon == nullptr) {
    icon = LoadIconW(instance, MAKEINTRESOURCEW(IDI_APP_ICON));
  }
  if (icon == nullptr) {
    // The resource itself is missing (a stripped runner, a broken build): the
    // tray icon is a way back to the window, not a branding surface.
    icon = LoadIconW(nullptr, IDI_APPLICATION);
  }
  return icon;
}

}  // namespace

DesktopIntegrationChannel::DesktopIntegrationChannel(
    HWND window,
    flutter::BinaryMessenger* messenger,
    std::wstring initial_uri)
    : window_(window),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      pending_uri_(std::move(initial_uri)) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });

  // Requests are re-posted instead of being delivered from inside the SMTC
  // callback: the projection marshals its events onto this (apartment) thread,
  // and calling back into the controls from a handler is not supported.
  smtc_.SetRequestHandler([this](const SmtcRequest& request) {
    if (window_ == nullptr) {
      return;
    }
    PostMessage(window_, kSmtcRequestMessage,
                static_cast<WPARAM>(static_cast<int>(request.action)),
                static_cast<LPARAM>(request.position_ms));
  });
}

DesktopIntegrationChannel::~DesktopIntegrationChannel() {
  if (channel_ != nullptr) {
    // The messenger outlives this object only until FlutterWindow::OnDestroy
    // resets the controller, which is exactly when this destructor runs.
    channel_->SetMethodCallHandler(nullptr);
  }
  UnregisterHotkeys();
  RemoveTrayIcon();
  smtc_.Teardown();
  SetThreadExecutionState(ES_CONTINUOUS);
  if (window_ != nullptr) {
    KillTimer(window_, kStateSaveTimerId);
    KillTimer(window_, kTrayRetryTimerId);
  }
}

bool DesktopIntegrationChannel::Initialize() {
  TrayDebugLog("Initialize()");
  if (initialized_) {
    return true;
  }
  initialized_ = true;

  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  if (AddTrayIcon()) {
    UpdateTrayTooltip();
    EmitEvent("trayReady", flutter::EncodableMap());
  } else if (window_ != nullptr) {
    // The shell can still be starting up (a session restored at logon). Keep
    // retrying with a growing delay instead of giving up: an icon that appears
    // a minute late is still a way back to the window.
    tray_retry_delay_ms_ = std::min(tray_retry_delay_ms_, kTrayRetryMaxDelayMs);
    SetTimer(window_, kTrayRetryTimerId, tray_retry_delay_ms_, nullptr);
  }

  if (smtc_.Initialize(window_)) {
    smtc_.SetButtons(has_song_, playing_);
  } else {
    // Playback is unaffected; Dart only surfaces "原生媒体面板不可用".
    EmitEvent("smtcUnavailable", flutter::EncodableMap());
  }
  return true;
}

// Current process integrity level (SECURITY_MANDATORY_*); 0 when unknown.
// A low-integrity process (sandbox, restricted launcher) cannot talk to a
// medium-integrity Explorer, and Shell_NotifyIcon answers ERROR_ACCESS_DENIED
// (5) because of it. Reporting the level turns that into a readable hint.
int CurrentIntegrityLevel() {
  HANDLE token = nullptr;
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token) == FALSE) {
    return 0;
  }
  DWORD size = 0;
  GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &size);
  if (size == 0) {
    CloseHandle(token);
    return 0;
  }
  std::vector<unsigned char> buffer(size);
  int level = 0;
  if (GetTokenInformation(token, TokenIntegrityLevel, buffer.data(), size,
                          &size) != FALSE) {
    auto* label =
        reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buffer.data());
    DWORD sub_authority_count = 0;
    if (label->Label.Sid != nullptr) {
      const UCHAR count = *GetSidSubAuthorityCount(label->Label.Sid);
      sub_authority_count = count;
      if (sub_authority_count > 0) {
        const DWORD* rid = GetSidSubAuthority(
            label->Label.Sid, static_cast<DWORD>(sub_authority_count - 1));
        if (rid != nullptr) {
          level = static_cast<int>(*rid);
        }
      }
    }
  }
  CloseHandle(token);
  return level;
}

bool DesktopIntegrationChannel::EnsureTrayHost() {
  if (tray_host_ != nullptr) {
    return true;
  }
  HINSTANCE instance = GetModuleHandleW(nullptr);
  WNDCLASSEXW window_class = {};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = &TrayHostProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kTrayHostClass;
  // Already registered by a previous instance of this channel is fine.
  RegisterClassExW(&window_class);

  g_tray_host.target = window_;
  g_tray_host.tray_message = kTrayCallbackMessage;
  g_tray_host.taskbar_created = taskbar_created_message_;
  tray_host_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                               kTrayHostClass, L"", WS_POPUP, 0, 0, 0, 0,
                               nullptr, nullptr, instance, nullptr);
  return tray_host_ != nullptr;
}
bool DesktopIntegrationChannel::AddTrayIcon() {
  {
    char buffer[128] = {};
    std::snprintf(buffer, sizeof(buffer), "AddTrayIcon window=%p added=%d",
                  reinterpret_cast<void*>(window_), tray_icon_added_ ? 1 : 0);
    TrayDebugLog(buffer);
  }
  if (window_ == nullptr || tray_icon_added_) {
    return tray_icon_added_;
  }
  // Prefer the dedicated host window; the Flutter window was refused by the
  // shell in practice.
  HWND host = EnsureTrayHost() ? tray_host_ : window_;
  if (host == nullptr) {
    return false;
  }
  if (tray_icon_id_ == 0) {
    // One slot per process. A fixed id plus a killed run leaves the shell
    // answering ERROR_ALREADY_EXISTS for a window that no longer exists, which
    // is exactly the 183 the status card reported.
    tray_icon_id_ = GetCurrentProcessId();
    if (tray_icon_id_ == 0) {
      tray_icon_id_ = kTrayIconId;
    }
  }

  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = host;
  icon.uID = tray_icon_id_;
  icon.uCallbackMessage = kTrayCallbackMessage;
  icon.hIcon = LoadTrayIcon();
  lstrcpynW(icon.szTip, tray_tooltip_.c_str(), ARRAYSIZE(icon.szTip));

  // Drop any leftover entry for this id before adding: a run that was killed
  // never sent NIM_DELETE, and the shell then refuses the new registration for
  // the same slot. Deleting an absent icon is a harmless failure.
  Shell_NotifyIconW(NIM_DELETE, &icon);

  // Documented sequence, and the reason the earlier versions failed: the icon
  // is added with plain flags first, then the callback is upgraded with
  // NIM_SETVERSION, and only then is NIF_SHOWTIP applied with NIM_MODIFY.
  // NIF_SHOWTIP itself demands the version-4 callback; sending it inside the
  // very first NIM_ADD makes a strict shell reject the whole registration.
  const UINT base_flags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  icon.uFlags = base_flags;
  bool added = Shell_NotifyIconW(NIM_ADD, &icon) != FALSE;
  DWORD add_error = added ? ERROR_SUCCESS : GetLastError();
  {
    char buffer[256] = {};
    std::snprintf(buffer, sizeof(buffer),
                  "host=%p cbSize=%d add=%d err=%lu",
                  reinterpret_cast<void*>(host), static_cast<int>(sizeof(icon)),
                  added ? 1 : 0, static_cast<unsigned long>(add_error));
    TrayDebugLog(buffer);
  }

  if (!added && add_error == ERROR_ALREADY_EXISTS) {
    // The shell still holds this slot (a previous run that was killed never
    // sent NIM_DELETE). NIM_MODIFY rebinds the existing entry to this window
    // instead of adding a second one.
    added = Shell_NotifyIconW(NIM_MODIFY, &icon) != FALSE;
    add_error = added ? ERROR_SUCCESS : GetLastError();
    TrayDebugLog(added ? "recovered via NIM_MODIFY after 183"
                       : "183 and NIM_MODIFY refused");
  }

  if (!added && add_error == ERROR_ACCESS_DENIED) {
    // The shell refused *this* window. Rebuild it once and retry: an icon
    // registered against a window the shell has already rejected never works,
    // but a fresh window often does.
    if (tray_host_ != nullptr) {
      DestroyWindow(tray_host_);
      tray_host_ = nullptr;
    }
    if (EnsureTrayHost()) {
      icon.hWnd = tray_host_;
      added = Shell_NotifyIconW(NIM_ADD, &icon) != FALSE;
      add_error = added ? ERROR_SUCCESS : GetLastError();
      char buffer[160] = {};
      std::snprintf(buffer, sizeof(buffer), "retry on fresh host add=%d err=%lu",
                    added ? 1 : 0, static_cast<unsigned long>(add_error));
      TrayDebugLog(buffer);
    }
  }

  if (!added) {
    // Last resort: register the icon by GUID. This survives leftovers from a
    // killed run and does not depend on the window slot at all.
    NOTIFYICONDATAW guided{};
    guided.cbSize = sizeof(guided);
    guided.hWnd = icon.hWnd;
    guided.uID = icon.uID;
    guided.uFlags = base_flags | NIF_GUID;
    guided.uCallbackMessage = kTrayCallbackMessage;
    guided.hIcon = icon.hIcon;
    lstrcpynW(guided.szTip, tray_tooltip_.c_str(), ARRAYSIZE(guided.szTip));
    guided.guidItem = kTrayIconGuid;
    added = Shell_NotifyIconW(NIM_ADD, &guided) != FALSE;
    add_error = added ? ERROR_SUCCESS : GetLastError();
    TrayDebugLog(added ? "registered by GUID" : "GUID registration refused");
    if (added) {
      tray_guid_mode_ = true;
      icon = guided;
    }
  }

  if (!added) {
    const DWORD last_error = add_error;
    // 0 is the "no error" sentinel in the protocol, so a failure that did not
    // set one is reported as a generic failure rather than as success.
    tray_error_ = static_cast<int>(last_error == ERROR_SUCCESS
                                       ? ERROR_GEN_FAILURE
                                       : last_error);
    flutter::EncodableMap arguments;
    arguments[Text("error")] = flutter::EncodableValue(tray_error_);
    // "icon" says the icon handle is the suspect, "add" says the shell refused.
    arguments[Text("stage")] =
        Text(icon.hIcon == nullptr ? "icon" : "add");
    EmitEvent("trayFailed", arguments);
    return false;
  }

  // Upgrade the callback to version 4 (the anchor point arrives in wParam),
  // then let the shell show the tooltip on hover.
  tray_error_ = 0;
  icon.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconW(NIM_SETVERSION, &icon);
  icon.uFlags = NIF_SHOWTIP;
  Shell_NotifyIconW(NIM_MODIFY, &icon);
  tray_icon_added_ = true;
  tray_unavailable_ = false;
  tray_retry_delay_ms_ = 1000;
  tray_retry_attempts_ = 0;

  // Ask the shell where the icon ended up. A failure here is diagnostic only:
  // an icon parked in the overflow flyout may not answer, and refusing to
  // believe NIM_ADD would make the app never hide. The studio shows the answer
  // so "the icon is added but invisible" stops looking like "no tray at all".
  NOTIFYICONIDENTIFIER identifier{};
  identifier.cbSize = sizeof(identifier);
  identifier.hWnd = icon.hWnd;
  identifier.uID = icon.uID;
  RECT icon_rect{};
  const HRESULT rect_result = Shell_NotifyIconGetRect(&identifier, &icon_rect);
  flutter::EncodableMap verify;
  verify[Text("ok")] = flutter::EncodableValue(SUCCEEDED(rect_result));
  verify[Text("rectLeft")] =
      flutter::EncodableValue(static_cast<int32_t>(icon_rect.left));
  verify[Text("rectTop")] =
      flutter::EncodableValue(static_cast<int32_t>(icon_rect.top));
  EmitEvent("trayIconPlaced", verify);
  return true;
}

void DesktopIntegrationChannel::RemoveTrayIcon() {
  HWND host = tray_host_ != nullptr ? tray_host_ : window_;
  if (host == nullptr || !tray_icon_added_) {
    return;
  }
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = host;
  icon.uID = tray_icon_id_;
  if (tray_guid_mode_) {
    icon.uFlags = NIF_GUID;
    icon.guidItem = kTrayIconGuid;
  }
  Shell_NotifyIconW(NIM_DELETE, &icon);
  tray_icon_added_ = false;
}

void DesktopIntegrationChannel::UpdateTrayTooltip() {
  HWND host = tray_host_ != nullptr ? tray_host_ : window_;
  if (host == nullptr || !tray_icon_added_) {
    return;
  }
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = host;
  icon.uID = tray_icon_id_;
  icon.uFlags = NIF_TIP;
  if (tray_guid_mode_) {
    icon.uFlags |= NIF_GUID;
    icon.guidItem = kTrayIconGuid;
  }
  lstrcpynW(icon.szTip, tray_tooltip_.c_str(), ARRAYSIZE(icon.szTip));
  Shell_NotifyIconW(NIM_MODIFY, &icon);
}

void DesktopIntegrationChannel::ShowTrayMenu(POINT point) {
  if (window_ == nullptr) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }

  AppendMenuW(menu, MF_STRING, kMenuShow, L"显示主窗口");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING | (has_song_ ? MF_ENABLED : MF_GRAYED),
              kMenuPlayPause, playing_ ? L"暂停" : L"播放");
  AppendMenuW(menu, MF_STRING | (has_song_ ? MF_ENABLED : MF_GRAYED),
              kMenuPrevious, L"上一首");
  AppendMenuW(menu, MF_STRING | (has_song_ ? MF_ENABLED : MF_GRAYED),
              kMenuNext, L"下一首");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING | (floating_lyrics_ ? MF_CHECKED : 0),
              kMenuFloatingLyrics, L"悬浮歌词");
  AppendMenuW(menu, MF_STRING | (taskbar_lyrics_ ? MF_CHECKED : 0),
              kMenuTaskbarLyrics, L"任务栏歌词");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuExit, L"退出 Mconnect");

  // Without the foreground activation Windows leaves the menu on screen when
  // the user clicks elsewhere.
  SetForegroundWindow(window_);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, point.x, point.y, 0,
                 window_, nullptr);
  PostMessage(window_, WM_NULL, 0, 0);
  DestroyMenu(menu);
}

void DesktopIntegrationChannel::ShowTrayBalloon(const std::wstring& title,
                                                const std::wstring& text) {
  HWND host = tray_host_ != nullptr ? tray_host_ : window_;
  if (host == nullptr || !tray_icon_added_) {
    return;
  }
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = host;
  icon.uID = tray_icon_id_;
  icon.uFlags = NIF_INFO;
  if (tray_guid_mode_) {
    icon.uFlags |= NIF_GUID;
    icon.guidItem = kTrayIconGuid;
  }
  icon.dwInfoFlags = NIIF_INFO;
  lstrcpynW(icon.szInfoTitle, title.c_str(), ARRAYSIZE(icon.szInfoTitle));
  lstrcpynW(icon.szInfo, text.c_str(), ARRAYSIZE(icon.szInfo));
  Shell_NotifyIconW(NIM_MODIFY, &icon);
}

void DesktopIntegrationChannel::HandleTrayMessage(WPARAM wparam, LPARAM lparam) {
  const UINT event = static_cast<UINT>(LOWORD(lparam));
  POINT point{GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam)};
  if (point.x == 0 && point.y == 0) {
    GetCursorPos(&point);
  }
  switch (event) {
    case WM_CONTEXTMENU:
    case WM_RBUTTONUP:
      ShowTrayMenu(point);
      break;
    case NIN_SELECT:
    case NIN_KEYSELECT:
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
      ShowMainWindow();
      break;
    default:
      break;
  }
}

void DesktopIntegrationChannel::HandleMenuCommand(UINT command) {
  switch (command) {
    case kMenuShow:
      ShowMainWindow();
      break;
    case kMenuPlayPause:
      EmitTrayCommand(playing_ ? "pause" : "play");
      break;
    case kMenuPrevious:
      EmitTrayCommand("previous");
      break;
    case kMenuNext:
      EmitTrayCommand("next");
      break;
    case kMenuFloatingLyrics:
      EmitTrayCommand("toggleLyrics");
      break;
    case kMenuTaskbarLyrics:
      EmitTrayCommand("toggleTaskbarLyrics");
      break;
    case kMenuExit:
      RequestQuit();
      break;
    default:
      break;
  }
}

void DesktopIntegrationChannel::RequestQuit() {
  // The next WM_CLOSE has to go through even when close-to-tray is on.
  force_quit_ = true;
  SaveWindowStateNow(false);
  if (window_ != nullptr) {
    PostMessage(window_, WM_CLOSE, 0, 0);
  }
}

void DesktopIntegrationChannel::ShowMainWindow() {
  if (window_ == nullptr) {
    return;
  }
  if (IsIconic(window_) != FALSE) {
    ShowWindow(window_, SW_RESTORE);
  } else {
    ShowWindow(window_, SW_SHOWNORMAL);
  }
  SetForegroundWindow(window_);
}

bool DesktopIntegrationChannel::HandleCloseRequest() {
  if (force_quit_) {
    // RequestQuit already archived the geometry. The same WM_CLOSE can reach us
    // twice (our hook in FlutterWindow::MessageHandler, then Win32Window), so
    // this branch stays silent and only answers "let it die".
    SaveWindowStateNow(false);
    return false;
  }
  // Dart persists playback state / tears down the media session on this event;
  // it must arrive before the window disappears.
  EmitEvent("windowCloseRequested", flutter::EncodableMap());

  if (!minimize_to_tray_) {
    // The user asked for "close means quit"; there is nothing to hide.
    SaveWindowStateNow(false);
    EmitEvent("closeFellBackToExit", flutter::EncodableMap());
    // Win32Window asks once more after us; treat this as a quit so the events
    // above are not replayed.
    force_quit_ = true;
    return false;
  }

  if (tray_icon_added_) {
    SaveWindowStateNow(false);
    if (window_ != nullptr) {
      ShowWindow(window_, SW_HIDE);
    }
    EmitEvent("hiddenToTray", flutter::EncodableMap());
    if (first_run_hint_ && hint_armed_) {
      hint_armed_ = false;
      close_hint_shown_ = true;
      ShowTrayBalloon(L"Mconnect 仍在后台运行",
                      L"右键托盘图标可以控制播放，或选择“退出 Mconnect”。");
    }
    return true;
  }

  // 关闭到托盘 is on but the shell never accepted an icon. The user's contract for
  // the X button is "do not leave this in the taskbar", so hide the window
  // anyway -- and keep it recoverable: launching mconnect.exe again forwards
  // its command line here (single-instance hand-off) and calls ShowMainWindow(),
  // which restores exactly this hidden window.
  SaveWindowStateNow(false);
  tray_unavailable_ = true;
  flutter::EncodableMap arguments;
  arguments[Text("reason")] =
      flutter::EncodableValue(tray_error_ != 0 ? tray_error_ : 1);
  if (window_ != nullptr) {
    ShowWindow(window_, SW_HIDE);
  }
  EmitEvent("hiddenWithoutTray", arguments);
  // Keep retrying: an icon that appears later makes the next close a real one.
  if (window_ != nullptr) {
    SetTimer(window_, kTrayRetryTimerId, tray_retry_delay_ms_, nullptr);
  }
  return true;
}

bool DesktopIntegrationChannel::ApplyHotkeys(bool enabled,
                                             const std::string& lyrics_toggle,
                                             const std::string& play_pause) {
  UnregisterHotkeys();
  if (!enabled) {
    return true;
  }
  if (window_ == nullptr) {
    return false;
  }

  const struct {
    const std::string* text;
    const char* action;
  } requests[] = {{&lyrics_toggle, "toggleLyrics"},
                  {&play_pause, "playPause"}};

  for (const auto& request : requests) {
    const ParsedHotkey parsed = ParseHotkey(*request.text);
    if (!parsed.valid) {
      UnregisterHotkeys();
      return false;
    }
    HotkeyBinding binding;
    binding.id = kHotkeyBaseId + static_cast<int>(hotkeys_.size());
    binding.modifiers = parsed.modifiers;
    binding.virtual_key = parsed.virtual_key;
    binding.action = request.action;
    // MOD_NOREPEAT: holding the chord must not fire the command repeatedly.
    if (RegisterHotKey(window_, binding.id, binding.modifiers | MOD_NOREPEAT,
                       binding.virtual_key) == FALSE) {
      // Another application owns this chord. Registering only half of the pair
      // would leave the app in a state the settings page cannot describe, so
      // the whole set is rolled back and Dart shows a conflict.
      UnregisterHotkeys();
      return false;
    }
    hotkeys_.push_back(binding);
  }
  return true;
}

void DesktopIntegrationChannel::UnregisterHotkeys() {
  if (window_ != nullptr) {
    for (const HotkeyBinding& binding : hotkeys_) {
      UnregisterHotKey(window_, binding.id);
    }
  }
  hotkeys_.clear();
}

bool DesktopIntegrationChannel::HandleHotkey(int id) {
  for (const HotkeyBinding& binding : hotkeys_) {
    if (binding.id != id) {
      continue;
    }
    if (binding.action == "toggleLyrics") {
      EmitTrayCommand("toggleLyrics");
    } else if (binding.action == "playPause") {
      // The native side owns the last known state, so the command it emits is
      // already concrete: Dart never has to guess which way to toggle.
      EmitTrayCommand(playing_ ? "pause" : "play");
    }
    return true;
  }
  return false;
}

void DesktopIntegrationChannel::ApplyExecutionState() {
  const bool keep_awake = prevent_sleep_ && playing_;
  SetThreadExecutionState(ES_CONTINUOUS |
                          (keep_awake ? ES_SYSTEM_REQUIRED : 0));
}

void DesktopIntegrationChannel::EmitEvent(const std::string& name,
                                          flutter::EncodableMap arguments) {
  if (channel_ == nullptr) {
    return;
  }
  channel_->InvokeMethod(name,
                         std::make_unique<flutter::EncodableValue>(arguments));
}

void DesktopIntegrationChannel::EmitTrayCommand(const std::string& action) {
  EmitEvent("trayCommand", ActionArguments(action));
}

void DesktopIntegrationChannel::DeliverSmtcRequest(int action,
                                                   int64_t position_ms) {
  switch (static_cast<SmtcRequest::Action>(action)) {
    case SmtcRequest::Action::kPlay:
      EmitEvent("smtcControl", ActionArguments("play"));
      break;
    case SmtcRequest::Action::kPause:
      EmitEvent("smtcControl", ActionArguments("pause"));
      break;
    case SmtcRequest::Action::kStop:
      EmitEvent("smtcControl", ActionArguments("stop"));
      break;
    case SmtcRequest::Action::kNext:
      EmitEvent("smtcControl", ActionArguments("next"));
      break;
    case SmtcRequest::Action::kPrevious:
      EmitEvent("smtcControl", ActionArguments("previous"));
      break;
    case SmtcRequest::Action::kSeek: {
      flutter::EncodableMap arguments = ActionArguments("seek");
      arguments[Text("positionMs")] = flutter::EncodableValue(position_ms);
      EmitEvent("smtcControl", arguments);
      break;
    }
    default:
      break;
  }
}

WindowState DesktopIntegrationChannel::CurrentWindowState() const {
  WindowState state;
  if (window_ == nullptr) {
    return state;
  }
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (GetWindowPlacement(window_, &placement) == FALSE) {
    return state;
  }
  // rcNormalPosition is the restored geometry, which is what has to be stored:
  // a maximized window's GetWindowRect is the maximized frame and would come
  // back as a slightly-too-large "normal" window.
  const RECT& normal = placement.rcNormalPosition;
  state.x = normal.left;
  state.y = normal.top;
  state.width = normal.right - normal.left;
  state.height = normal.bottom - normal.top;
  state.maximized = placement.showCmd == SW_SHOWMAXIMIZED ||
                    IsZoomed(window_) != FALSE;
  state.valid = state.width > 0 && state.height > 0;
  return state;
}

bool DesktopIntegrationChannel::SaveWindowStateNow(bool emit_event) {
  // "记住窗口位置" is off: nothing reaches the disk, including the save that
  // runs while the window is closing.
  if (!remember_window_state_) {
    return false;
  }
  const WindowState state = CurrentWindowState();
  if (!state.valid) {
    return false;
  }
  const bool saved = SaveWindowState(state);
  if (emit_event) {
    EmitEvent("windowStateChanged", WindowStateArguments(state));
  }
  return saved;
}

void DesktopIntegrationChannel::HandleForwardedPayload(
    const std::wstring& payload) {
  if (!payload.empty()) {
    pending_uri_ = payload;
    flutter::EncodableMap arguments;
    arguments[Text("uri")] = Text(Utf8FromWide(payload));
    EmitEvent("uriReceived", arguments);
  }
  ShowMainWindow();
}

bool DesktopIntegrationChannel::HandleWindowMessage(HWND window,
                                                    UINT message,
                                                    WPARAM wparam,
                                                    LPARAM lparam,
                                                    LRESULT* result) {
  if (result == nullptr) {
    return false;
  }

  // Explorer restarted: the notification area is empty again and the shell
  // broadcasts TaskbarCreated to every top-level window.
  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    tray_icon_added_ = false;
    tray_retry_attempts_ = 0;
    tray_retry_delay_ms_ = kTrayRetryBaseDelayMs;
    if (AddTrayIcon()) {
      UpdateTrayTooltip();
      EmitEvent("trayReady", flutter::EncodableMap());
    } else {
      // The new taskbar may not be ready yet; retry with backoff.
      SetTimer(window, kTrayRetryTimerId, tray_retry_delay_ms_, nullptr);
    }
    *result = 0;
    return true;
  }

  switch (message) {
    case kTrayCallbackMessage:
      HandleTrayMessage(wparam, lparam);
      *result = 0;
      return true;

    case kSmtcRequestMessage:
      DeliverSmtcRequest(static_cast<int>(wparam),
                         static_cast<int64_t>(lparam));
      *result = 0;
      return true;

    case WM_HOTKEY:
      if (HandleHotkey(static_cast<int>(wparam))) {
        *result = 0;
        return true;
      }
      return false;

    case WM_COMMAND: {
      const UINT command = LOWORD(wparam);
      if (command < kMenuShow || command > kMenuExit) {
        return false;
      }
      HandleMenuCommand(command);
      *result = 0;
      return true;
    }

    case WM_TIMER:
      if (wparam == kStateSaveTimerId) {
        KillTimer(window, kStateSaveTimerId);
        if (remember_window_state_) {
          SaveWindowStateNow(true);
        }
        *result = 0;
        return true;
      }
      if (wparam == kTrayRetryTimerId) {
        ++tray_retry_attempts_;
        const bool added = AddTrayIcon();
        if (added) {
          UpdateTrayTooltip();
          EmitEvent("trayReady", flutter::EncodableMap());
          KillTimer(window, kTrayRetryTimerId);
        } else {
          // Exponential backoff, capped: a shell that keeps refusing costs one
          // call every 30s, not ten calls then silence.
          tray_retry_delay_ms_ = std::min(tray_retry_delay_ms_ * 2,
                                          kTrayRetryMaxDelayMs);
          SetTimer(window, kTrayRetryTimerId, tray_retry_delay_ms_, nullptr);
        }
        *result = 0;
        return true;
      }
      return false;

    case WM_EXITSIZEMOVE:
      // Debounced: a drag/resize ends here, and the user often closes the app
      // right afterwards. With "记住窗口位置" off there is no timer at all, so
      // moving the window never writes to disk.
      if (remember_window_state_) {
        SetTimer(window, kStateSaveTimerId, kStateSaveDelayMs, nullptr);
      }
      return false;

    case WM_COPYDATA: {
      const auto* copy_data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (copy_data == nullptr ||
          copy_data->dwData != kSingleInstanceCopyDataId ||
          copy_data->lpData == nullptr ||
          copy_data->cbData < sizeof(wchar_t)) {
        return false;
      }
      const size_t characters = copy_data->cbData / sizeof(wchar_t);
      std::wstring payload(
          static_cast<const wchar_t*>(copy_data->lpData), characters);
      while (!payload.empty() && payload.back() == L'\0') {
        payload.pop_back();
      }
      HandleForwardedPayload(payload);
      *result = TRUE;
      return true;
    }

    default:
      break;
  }
  return false;
}

void DesktopIntegrationChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const flutter::EncodableValue* raw_arguments = call.arguments();
  const flutter::EncodableMap* arguments = nullptr;
  if (raw_arguments != nullptr) {
    arguments = std::get_if<flutter::EncodableMap>(raw_arguments);
  }

  // Ordered by call frequency: the timeline ticks about once a second, the
  // settings methods run when the user changes something.
  if (method == "setTimeline") {
    if (arguments == nullptr) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    smtc_.SetTimeline(ArgumentInt(*arguments, "positionMs", 0),
                      ArgumentInt(*arguments, "durationMs", 0));
    result->Success(flutter::EncodableValue(smtc_.available()));
    return;
  }

  if (method == "setMediaMetadata") {
    if (arguments == nullptr) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    smtc_.SetMetadata(
        WideFromUtf8(ArgumentString(*arguments, "title", std::string())),
        WideFromUtf8(ArgumentString(*arguments, "artist", std::string())),
        WideFromUtf8(ArgumentString(*arguments, "album", std::string())),
        ArgumentInt(*arguments, "durationMs", 0));
    result->Success(flutter::EncodableValue(smtc_.available()));
    return;
  }

  if (method == "setPlaybackState") {
    const std::string status =
        arguments == nullptr
            ? std::string("stopped")
            : ArgumentString(*arguments, "status", std::string("stopped"));
    int playback_status = 2;
    if (status == "playing") {
      playback_status = 0;
    } else if (status == "paused") {
      playback_status = 1;
    }
    playing_ = playback_status == 0;
    smtc_.SetPlaybackStatus(playback_status);
    smtc_.SetButtons(has_song_, playing_);
    ApplyExecutionState();
    result->Success(flutter::EncodableValue(smtc_.available()));
    return;
  }

  if (method == "setTrayState") {
    if (arguments != nullptr) {
      playing_ = ArgumentBool(*arguments, "playing", playing_);
      has_song_ = ArgumentBool(*arguments, "hasSong", has_song_);
      floating_lyrics_ =
          ArgumentBool(*arguments, "floatingLyrics", floating_lyrics_);
      taskbar_lyrics_ =
          ArgumentBool(*arguments, "taskbarLyrics", taskbar_lyrics_);
      liked_ = ArgumentBool(*arguments, "liked", liked_);
      tray_tooltip_ = BuildTooltip(
          WideFromUtf8(ArgumentString(*arguments, "title", std::string())),
          WideFromUtf8(ArgumentString(*arguments, "artist", std::string())));
    }
    UpdateTrayTooltip();
    smtc_.SetButtons(has_song_, playing_);
    ApplyExecutionState();
    result->Success(flutter::EncodableValue(tray_icon_added_));
    return;
  }

  if (method == "initialize") {
    result->Success(flutter::EncodableValue(Initialize()));
    return;
  }

  if (method == "setCloseBehavior") {
    if (arguments != nullptr) {
      const bool minimize_to_tray =
          ArgumentBool(*arguments, "minimizeToTray", minimize_to_tray_);
      minimize_to_tray_ = minimize_to_tray;
      first_run_hint_ =
          ArgumentBool(*arguments, "firstRunHint", first_run_hint_);
      remember_window_state_ = ArgumentBool(*arguments, "rememberWindowState",
                                            remember_window_state_);
      if (minimize_to_tray) {
        // Turning close-to-tray back on should explain the tray icon again.
        hint_armed_ = true;
      }
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "setHotkeys") {
    if (arguments == nullptr) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    const bool enabled = ArgumentBool(*arguments, "enabled", true);
    const std::string lyrics_toggle = ArgumentString(
        *arguments, "lyricsToggle", std::string("Ctrl+Alt+L"));
    const std::string play_pause = ArgumentString(
        *arguments, "playPause", std::string("Ctrl+Alt+Space"));
    result->Success(flutter::EncodableValue(
        ApplyHotkeys(enabled, lyrics_toggle, play_pause)));
    return;
  }

  if (method == "setPreventSleep") {
    bool enabled = false;
    if (raw_arguments != nullptr) {
      if (const auto* flag = std::get_if<bool>(raw_arguments)) {
        enabled = *flag;
      } else if (arguments != nullptr) {
        enabled = ArgumentBool(*arguments, "enabled", false);
      }
    }
    prevent_sleep_ = enabled;
    ApplyExecutionState();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "getWindowState") {
    result->Success(flutter::EncodableValue(
        WindowStateArguments(CurrentWindowState())));
    return;
  }

  if (method == "saveWindowState") {
    // The map is optional (the protocol's call takes no parameters at all).
    // When a caller does send a complete rectangle, that is the state to keep —
    // otherwise the live geometry of the window that owns it wins.
    if (arguments != nullptr) {
      WindowState supplied;
      supplied.x = static_cast<int>(ArgumentInt(*arguments, "x", 0));
      supplied.y = static_cast<int>(ArgumentInt(*arguments, "y", 0));
      supplied.width = static_cast<int>(ArgumentInt(*arguments, "width", 0));
      supplied.height = static_cast<int>(ArgumentInt(*arguments, "height", 0));
      supplied.maximized = ArgumentBool(*arguments, "maximized", false);
      supplied.valid = supplied.width > 0 && supplied.height > 0;
      if (supplied.valid) {
        result->Success(flutter::EncodableValue(SaveWindowState(supplied)));
        return;
      }
    }
    result->Success(flutter::EncodableValue(SaveWindowStateNow(false)));
    return;
  }

  if (method == "resetWindowState") {
    result->Success(flutter::EncodableValue(DeleteWindowState()));
    return;
  }

  if (method == "takeInitialUri") {
    if (pending_uri_.empty()) {
      result->Success();
      return;
    }
    const std::string uri = Utf8FromWide(pending_uri_);
    pending_uri_.clear();
    result->Success(flutter::EncodableValue(uri));
    return;
  }

  if (method == "getAccentColor") {
    DWORD colorization = 0;
    BOOL opaque = FALSE;
    if (SUCCEEDED(DwmGetColorizationColor(&colorization, &opaque))) {
      // 0xAARRGGBB, handed over as a positive int64 so Dart does not have to
      // deal with the sign of a 32-bit ARGB value.
      result->Success(
          flutter::EncodableValue(static_cast<int64_t>(colorization)));
    } else {
      result->Success();
    }
    return;
  }

  if (method == "getRuntimeStatus") {
    // Pushed events are the fast path, not the only one: a tray icon the shell
    // never accepted emits nothing at all, which is why the settings card used
    // to sit on "尚未收到运行器答复" forever. Asking once at startup fixes that.
    flutter::EncodableMap status;
    status[Text("trayAdded")] = flutter::EncodableValue(tray_icon_added_);
    status[Text("trayError")] = flutter::EncodableValue(tray_error_);
    status[Text("smtcAvailable")] = flutter::EncodableValue(smtc_.available());
    // The binding list is the truth: ApplyHotkeys(enabled=false) answers true
    // because there was nothing to do, which is not "a hotkey is registered".
    status[Text("hotkeysEnabled")] =
        flutter::EncodableValue(!hotkeys_.empty());
    // Elevation is a real cause of "the shell will not take my tray icon": an
    // elevated process can be refused by an unelevated Explorer. Reporting it
    // turns a mystery into an actionable hint.
    status[Text("elevated")] = flutter::EncodableValue(IsUserAnAdmin() != FALSE);
    status[Text("integrity")] =
        flutter::EncodableValue(CurrentIntegrityLevel());
    status[Text("trayHost")] = flutter::EncodableValue(tray_host_ != nullptr);
    status[Text("trayUnavailableClose")] =
        flutter::EncodableValue(tray_unavailable_);
    result->Success(flutter::EncodableValue(status));
    return;
  }

  if (method == "freeSpaceBytes") {
    std::string path;
    if (raw_arguments != nullptr) {
      if (const auto* text = std::get_if<std::string>(raw_arguments)) {
        path = *text;
      } else if (arguments != nullptr) {
        path = ArgumentString(*arguments, "path", std::string());
      }
    }
    const std::wstring wide_path = WideFromUtf8(path);
    ULARGE_INTEGER free_bytes{};
    bool measured = false;
    if (!wide_path.empty()) {
      measured = GetDiskFreeSpaceExW(wide_path.c_str(), nullptr, nullptr,
                                     &free_bytes) != FALSE;
      if (!measured) {
        // The caller may hand us a file (a download target) instead of a
        // directory; the volume is the same either way.
        const size_t separator = wide_path.find_last_of(L"\\/");
        if (separator != std::wstring::npos && separator > 0) {
          const std::wstring parent = wide_path.substr(0, separator);
          measured = GetDiskFreeSpaceExW(parent.c_str(), nullptr, nullptr,
                                         &free_bytes) != FALSE;
        }
      }
    }
    if (measured) {
      result->Success(
          flutter::EncodableValue(static_cast<int64_t>(free_bytes.QuadPart)));
    } else {
      // null means "unknown", never "plenty of room".
      result->Success();
    }
    return;
  }

  result->NotImplemented();
}

}  // namespace desktop
}  // namespace mconnect