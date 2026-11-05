#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <string>

#include "desktop/desktop_integration_channel.h"
#include "desktop/file_opener_channel.h"
#include "floating_lyrics_channel.h"
#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // The URI this process was launched with (a deep link / a file association),
  // handed to `takeInitialUri` once Dart asks. Must be called before Create.
  void SetInitialUri(std::wstring uri);

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  bool OnCloseRequested() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<FloatingLyricsChannel> floating_lyrics_channel_;
  std::unique_ptr<FileOpenerChannel> file_opener_channel_;
  std::unique_ptr<mconnect::desktop::DesktopIntegrationChannel>
      desktop_integration_channel_;
  std::wstring initial_uri_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
