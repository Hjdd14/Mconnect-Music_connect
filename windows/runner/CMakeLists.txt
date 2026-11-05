cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "floating_lyrics_channel.cpp"
  "taskbar_lyrics_channel.cpp"
  "lyrics/floating_lyrics_window.cpp"
  "lyrics/lyrics_animation.cpp"
  "lyrics/lyrics_renderer.cpp"
  "lyrics/lyrics_window_base.cpp"
  "lyrics/taskbar_geometry.cpp"
  "lyrics/taskbar_lyrics_window.cpp"
  # MConnect parity channels (desktop/file_opener_channel.*). Kept in their own
  # block so a merge of the parity branch is a one line addition here.
  "desktop/file_opener_channel.cpp"
  # Desktop integration: SMTC / tray / window state / single instance /
  # hotkeys / prevent-sleep (docs/desktop-lyrics-protocol.md section 4.3).
  "desktop/desktop_integration_channel.cpp"
  "desktop/single_instance.cpp"
  "desktop/smtc_session.cpp"
  "desktop/window_state_store.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)

# Desktop lyrics: Direct2D + DirectWrite draw into a 32bpp DIB that is presented
# with UpdateLayeredWindow; GDI+ is the per-pixel fallback, the shell APIs read
# the taskbar geometry, shcore supplies the per-monitor DPI.
#
# Desktop integration (desktop/*): shell32 (Shell_NotifyIconW,
# SHGetKnownFolderPath, SHCreateDirectoryExW), dwmapi (DwmGetColorizationColor),
# shlwapi, ole32/oleaut32 (CoTaskMemFree and the projection's COM plumbing),
# windowsapp (the WinRT activation factory behind SMTC), user32 (tray window
# messages, RegisterHotKey, SetThreadExecutionState is kernel32).
target_link_libraries(${BINARY_NAME} PRIVATE
  "d2d1.lib"
  "dwrite.lib"
  "dwmapi.lib"
  "shell32.lib"
  "shlwapi.lib"
  "shcore.lib"
  "ole32.lib"
  "oleaut32.lib"
  "uuid.lib"
  "windowsapp.lib"
  "gdi32.lib"
  "gdiplus.lib"
  "user32.lib"
)

# === C++/WinRT projection headers ===
#
# The SMTC session (desktop/smtc_session.cpp) obtains its
# SystemMediaTransportControls through ISystemMediaTransportControlsInterop, i.e.
# through the C++/WinRT projection headers that ship inside the Windows SDK at
# `Include/<version>/cppwinrt/winrt`. CMake does not put that directory on the
# include path, so it is located here.
#
# When the headers are missing the source is compiled without
# MCONNECT_HAS_CPPWINRT and reports the session as unavailable: media keys and
# the media flyout are lost, playback is not.
set(MCONNECT_CPPWINRT_INCLUDE_DIR "" CACHE PATH
    "Directory holding the C++/WinRT projection headers (SDK .../Include/<version>/cppwinrt)")

set(_mconnect_cppwinrt_include "")
if(MCONNECT_CPPWINRT_INCLUDE_DIR)
  set(_mconnect_cppwinrt_include "${MCONNECT_CPPWINRT_INCLUDE_DIR}")
else()
  set(_mconnect_cppwinrt_candidates "")

  # A developer shell exports the SDK root; use it first.
  if(DEFINED ENV{WindowsSdkDir} AND NOT "$ENV{WindowsSdkDir}" STREQUAL "")
    file(GLOB _mconnect_cppwinrt_sdk "$ENV{WindowsSdkDir}/Include/*/cppwinrt")
    list(APPEND _mconnect_cppwinrt_candidates ${_mconnect_cppwinrt_sdk})
  endif()

  # Otherwise look at the standard SDK install locations. The literal roots are
  # kept as a fallback because a VS-generator configure does not need (and often
  # does not have) a developer prompt.
  # `$ENV{ProgramFiles(x86)}` cannot be written at all: CMake rejects the
  # parentheses inside a variable name, which is why the 32-bit default root is
  # spelled out literally (it is the installation path on every default SDK
  # setup). An undefined environment variable globs nothing, which is fine.
  set(_mconnect_kit_roots "C:/Program Files (x86)/Windows Kits"
                          "C:/Program Files/Windows Kits"
                          "$ENV{ProgramFiles}/Windows Kits"
                          "$ENV{ProgramW6432}/Windows Kits")
  foreach(_mconnect_kit_root ${_mconnect_kit_roots})
    file(GLOB _mconnect_cppwinrt_kits
      "${_mconnect_kit_root}/*/Include/*/cppwinrt")
    list(APPEND _mconnect_cppwinrt_candidates ${_mconnect_cppwinrt_kits})
  endforeach()

  if(_mconnect_cppwinrt_candidates)
    list(REMOVE_DUPLICATES _mconnect_cppwinrt_candidates)
    # The path carries the SDK version number, so sorting leaves the newest last.
    list(SORT _mconnect_cppwinrt_candidates)
    list(GET _mconnect_cppwinrt_candidates -1 _mconnect_cppwinrt_include)
  endif()
endif()

if(_mconnect_cppwinrt_include AND
   EXISTS "${_mconnect_cppwinrt_include}/winrt/impl/windows.media.0.h")
  message(STATUS "C++/WinRT projection headers: ${_mconnect_cppwinrt_include}")
  target_include_directories(${BINARY_NAME} PRIVATE "${_mconnect_cppwinrt_include}")
  target_compile_definitions(${BINARY_NAME} PRIVATE "MCONNECT_HAS_CPPWINRT=1")
  # C++/WinRT still pulls <experimental/coroutine> out of the MSVC STL, which
  # now fails with a static_assert unless the deprecation warning is silenced.
  # Same definition windows/CMakeLists.txt already applies to just_audio_windows.
  target_compile_definitions(${BINARY_NAME} PRIVATE
    "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")
else()
  message(STATUS "C++/WinRT projection headers not found: SMTC stays disabled")
endif()

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# === 以管理员身份启动 ===
#
# Shell_NotifyIcon 通过窗口消息交给资源管理器，UIPI 只允许完整性等级不低于 shell
# 的进程发这条消息。普通启动（Medium）会被 Explorer（Medium）拒绝并返回
# ERROR_ACCESS_DENIED(5)，托盘图标永远不出现；提权后进程为 High，注册正常。
#
# 这一项必须走链接器的 /MANIFESTUAC，而不是写进 runner.exe.manifest：link.exe
# 默认已经生成自己的 trustInfo 片段，再加一份会让合并 manifests 的 mt.exe 失败
# （LNK1327）。
target_link_options(${BINARY_NAME} PRIVATE
  "/MANIFESTUAC:level='requireAdministrator' uiAccess='false'")

add_dependencies(${BINARY_NAME} flutter_assemble)
