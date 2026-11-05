#ifndef RUNNER_DESKTOP_FILE_OPENER_CHANNEL_H_
#define RUNNER_DESKTOP_FILE_OPENER_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

// Windows counterpart of the Android `com.mconnect.mconnect/file_opener`
// handler in `MainActivity.kt`. Before it existed, `FileOpener.openFolder` on
// Windows threw `MissingPluginException` and the download page showed a raw
// exception string in a snackbar, so "open the folder" was dead on desktop.
//
// Contract (identical to Android, so one Dart implementation serves both):
// - `openFile(path)`   opens the file with its default handler
//   (`ShellExecuteW` verb "open").
// - `openFolder(path)` opens the folder in Explorer (verb "explore", falling
//   back to "open" when no explorer verb is registered).
// - both answer `true` on success and an error (`INVALID_PATH` /
//   `OPEN_FAILED` + a message Dart can display verbatim) otherwise.
// - a path is validated first: non-empty, not absurdly long, absolute, still
//   present on disk, and of the expected kind. A path that does not exist must
//   not reach `ShellExecuteW`, which would otherwise open a shell error dialog
//   owned by no window.
//
// MERGE NOTE (native-lyrics owns `windows/runner/CMakeLists.txt` and
// `flutter_window.*`): register this the same way `FloatingLyricsChannel` is
// registered, i.e. in `FlutterWindow::OnCreate`, after the view/engine exist:
//
//   file_opener_channel_ = std::make_unique<FileOpenerChannel>(
//       flutter_controller_->engine()->messenger());
//
// and add `desktop/file_opener_channel.cpp` to the `add_executable` source
// list in `windows/runner/CMakeLists.txt`.
class FileOpenerChannel {
 public:
  explicit FileOpenerChannel(flutter::BinaryMessenger* messenger);
  ~FileOpenerChannel();

  FileOpenerChannel(const FileOpenerChannel&) = delete;
  FileOpenerChannel& operator=(const FileOpenerChannel&) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

#endif  // RUNNER_DESKTOP_FILE_OPENER_CHANNEL_H_
