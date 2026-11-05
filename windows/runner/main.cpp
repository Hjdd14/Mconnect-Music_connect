#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellscalingapi.h>

#include <string>

#include "desktop/single_instance.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

bool EnsureWritableDirectory(const std::wstring& path) {
  if (path.empty()) {
    return false;
  }
  CreateDirectoryW(path.c_str(), nullptr);
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
    return false;
  }
  const std::wstring probe = path + L"\\mconnect_temp_probe";
  HANDLE file = CreateFileW(probe.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS,
                            FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  CloseHandle(file);
  return true;
}

// media_kit creates NativeReferenceHolder files through Directory.systemTemp.
// On a locked-down profile that directory can be unwritable even though the
// app's own data directory has a working fallback, and the player then never
// starts. Point TMP/TEMP at a probed writable directory before Dart boots.
void ConfigureWritableTempDirectory() {
  std::wstring base;
  wchar_t buffer[32768] = {};
  DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", buffer,
                                         static_cast<DWORD>(std::size(buffer)));
  if (length > 0) {
    const std::wstring root =
        std::wstring(buffer, length) + L"\\com.mconnect";
    CreateDirectoryW(root.c_str(), nullptr);
    const std::wstring app = root + L"\\mconnect";
    CreateDirectoryW(app.c_str(), nullptr);
    const std::wstring candidate = app + L"\\tmp";
    if (EnsureWritableDirectory(candidate)) {
      base = candidate;
    }
  }
  if (base.empty()) {
    wchar_t exe[32768] = {};
    const DWORD exe_length = GetModuleFileNameW(nullptr, exe,
                                                static_cast<DWORD>(std::size(exe)));
    if (exe_length > 0) {
      std::wstring path(exe, exe_length);
      const size_t slash = path.find_last_of(L"\\/");
      if (slash != std::wstring::npos) {
        const std::wstring candidate = path.substr(0, slash) + L"\\tmp";
        if (EnsureWritableDirectory(candidate)) {
          base = candidate;
        }
      }
    }
  }
  if (base.empty()) {
    wchar_t temp[32768] = {};
    const DWORD temp_length = GetTempPathW(
        static_cast<DWORD>(std::size(temp)), temp);
    if (temp_length > 0) {
      const std::wstring candidate = std::wstring(temp, temp_length) +
                                     L"mconnect";
      if (EnsureWritableDirectory(candidate)) {
        base = candidate;
      }
    }
  }
  if (!base.empty()) {
    SetEnvironmentVariableW(L"TMP", base.c_str());
    SetEnvironmentVariableW(L"TEMP", base.c_str());
    SetEnvironmentVariableW(L"TMPDIR", base.c_str());
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // The manifest declares PerMonitorV2, but in some launch contexts Windows
  // still gives the process a 96-DPI (virtualized) view: GetDpiForWindow then
  // reports 96 while the Flutter engine uses the real 1.75 scale, and the
  // framebuffer ends up 1.75x larger than the window. Setting the context
  // explicitly before any window exists makes both sides agree.
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  ConfigureWritableTempDirectory();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Single instance. A second launch — double clicking a file, a browser deep
  // link, a shortcut clicked twice — hands its URI to the running instance and
  // exits before creating a window, so two processes never write the same
  // library data files. The mutex is session local and dies with the process,
  // so a crashed instance does not lock the app out.
  if (!mconnect::desktop::AcquireSingleInstanceMutex()) {
    mconnect::desktop::ForwardToRunningInstance(
        mconnect::desktop::InitialUriFromProcessCommandLine());
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Same URI this process was started with, so Dart can ask for it once
  // (`takeInitialUri`) instead of racing the first frame.
  window.SetInitialUri(mconnect::desktop::InitialUriFromProcessCommandLine());
  Win32Window::Point origin(10, 10);
  // Placeholder size: Win32Window::Create resizes to the monitor work area
  // using the real per-monitor DPI *before* FlutterViewController is created,
  // so the engine surface never changes size after its first frame.
  Win32Window::Size size(900, 600);
  if (!window.Create(L"Mconnect", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
