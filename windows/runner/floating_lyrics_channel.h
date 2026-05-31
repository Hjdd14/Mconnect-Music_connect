#ifndef RUNNER_FLOATING_LYRICS_CHANNEL_H_
#define RUNNER_FLOATING_LYRICS_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

#include "floating_lyrics_window.h"

class FloatingLyricsChannel {
 public:
  explicit FloatingLyricsChannel(flutter::BinaryMessenger* messenger);
  ~FloatingLyricsChannel();

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  FloatingLyricsWindow window_;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

#endif  // RUNNER_FLOATING_LYRICS_CHANNEL_H_
