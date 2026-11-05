#ifndef RUNNER_TASKBAR_LYRICS_CHANNEL_H_
#define RUNNER_TASKBAR_LYRICS_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

#include "lyrics/taskbar_lyrics_window.h"

// `com.mconnect.mconnect/taskbar_lyrics` (docs/desktop-lyrics-protocol.md 4.2).
// Owns the taskbar strip and translates its native events back to Dart.
class TaskbarLyricsChannel {
 public:
  explicit TaskbarLyricsChannel(flutter::BinaryMessenger* messenger);
  ~TaskbarLyricsChannel();

  TaskbarLyricsChannel(const TaskbarLyricsChannel&) = delete;
  TaskbarLyricsChannel& operator=(const TaskbarLyricsChannel&) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  TaskbarLyricsWindow window_;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SendEventToFlutter(const std::string& event,
                          const lyrics::EventArguments& args);
};

#endif  // RUNNER_TASKBAR_LYRICS_CHANNEL_H_
