#ifndef RUNNER_FLOATING_LYRICS_CHANNEL_H_
#define RUNNER_FLOATING_LYRICS_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

#include "lyrics/floating_lyrics_window.h"
#include "taskbar_lyrics_channel.h"

// `com.mconnect.mconnect/floating_lyrics`.
//
// Keeps the methods the Dart side has always used (canDrawOverlays,
// openOverlaySettings, show, update, hide) and adds the protocol methods
// configure/preview/resetPosition/getMonitors/setInteractive. The taskbar
// channel is created here as well so the runner keeps a single registration
// point for both desktop lyrics surfaces.
class FloatingLyricsChannel {
 public:
  explicit FloatingLyricsChannel(flutter::BinaryMessenger* messenger);
  ~FloatingLyricsChannel();

  FloatingLyricsChannel(const FloatingLyricsChannel&) = delete;
  FloatingLyricsChannel& operator=(const FloatingLyricsChannel&) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<TaskbarLyricsChannel> taskbar_channel_;
  FloatingLyricsWindow window_;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SendEventToFlutter(const std::string& event,
                          const lyrics::EventArguments& args);
};

#endif  // RUNNER_FLOATING_LYRICS_CHANNEL_H_
