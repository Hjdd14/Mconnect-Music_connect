#include "floating_lyrics_channel.h"


#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#include "lyrics/lyrics_channel_args.h"

namespace {

constexpr char kChannelName[] = "com.mconnect.mconnect/floating_lyrics";

// Colours are unsigned: a fully opaque ARGB value has the high bit set, and
// treating that as an error made every opaque colour fall back to the default.
bool GetColorArgb(const flutter::EncodableMap& map,
                  const char* key,
                  std::uint32_t* argb) {
  const auto* value = lyrics::FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return false;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    *argb = static_cast<std::uint32_t>(*int32_value);
    return true;
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    *argb = static_cast<std::uint32_t>(*int64_value);
    return true;
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    *argb = static_cast<std::uint32_t>(*double_value);
    return true;
  }
  return false;
}

flutter::EncodableMap MonitorToMap(const lyrics::MonitorInfo& monitor) {
  flutter::EncodableMap entry;
  entry[flutter::EncodableValue("deviceName")] =
      flutter::EncodableValue(lyrics::Utf8FromWide(monitor.device_name));
  entry[flutter::EncodableValue("left")] =
      flutter::EncodableValue(static_cast<int32_t>(monitor.bounds.left));
  entry[flutter::EncodableValue("top")] =
      flutter::EncodableValue(static_cast<int32_t>(monitor.bounds.top));
  entry[flutter::EncodableValue("right")] =
      flutter::EncodableValue(static_cast<int32_t>(monitor.bounds.right));
  entry[flutter::EncodableValue("bottom")] =
      flutter::EncodableValue(static_cast<int32_t>(monitor.bounds.bottom));
  entry[flutter::EncodableValue("dpi")] =
      flutter::EncodableValue(static_cast<int32_t>(monitor.dpi));
  entry[flutter::EncodableValue("isPrimary")] =
      flutter::EncodableValue(monitor.is_primary);
  return entry;
}

std::vector<std::pair<std::wstring, std::wstring>> ReadSampleLines(
    const flutter::EncodableMap& map) {
  std::vector<std::pair<std::wstring, std::wstring>> lines;
  const flutter::EncodableList* list = lyrics::GetList(map, "sampleLines");
  if (list == nullptr) {
    return lines;
  }
  
  for (const auto& item : *list) {
    const auto* entry = std::get_if<flutter::EncodableMap>(&item);
    if (entry == nullptr) {
      continue;
    }
    const std::string raw_text = lyrics::GetString(*entry, "text");
    
    lines.emplace_back(lyrics::GetWideString(*entry, "text"),
                       lyrics::GetWideString(*entry, "translation"));
  }
  return lines;
}

}  // namespace

FloatingLyricsChannel::FloatingLyricsChannel(
    flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
  window_.SetEventListener([this](const std::string& event,
                                  const lyrics::EventArguments& args) {
    SendEventToFlutter(event, args);
  });
  // The taskbar strip has its own channel but no separate owner in the runner;
  // creating it next to the floating channel keeps one registration site.
  taskbar_channel_ = std::make_unique<TaskbarLyricsChannel>(messenger);
}

FloatingLyricsChannel::~FloatingLyricsChannel() = default;

void FloatingLyricsChannel::SendEventToFlutter(
    const std::string& event,
    const lyrics::EventArguments& args) {
  if (!channel_) {
    return;
  }
  if (event == "lockChanged") {
    bool locked = false;
    for (const auto& arg : args) {
      if (arg.first == "value" &&
          arg.second.kind == lyrics::ArgumentValue::Kind::kBoolean) {
        locked = arg.second.boolean;
      }
    }
    channel_->InvokeMethod(event,
                           std::make_unique<flutter::EncodableValue>(locked));
    return;
  }
  if (event == "positionChanged") {
    double value = 0.0;
    for (const auto& arg : args) {
      if (arg.first == "value" &&
          arg.second.kind == lyrics::ArgumentValue::Kind::kNumber) {
        value = arg.second.number;
      }
    }
    channel_->InvokeMethod(event,
                           std::make_unique<flutter::EncodableValue>(value));
    return;
  }
  if (args.empty()) {
    channel_->InvokeMethod(event, nullptr);
    return;
  }
  flutter::EncodableMap payload;
  for (const auto& arg : args) {
    switch (arg.second.kind) {
      case lyrics::ArgumentValue::Kind::kNumber:
        payload[flutter::EncodableValue(arg.first)] =
            flutter::EncodableValue(arg.second.number);
        break;
      case lyrics::ArgumentValue::Kind::kBoolean:
        payload[flutter::EncodableValue(arg.first)] =
            flutter::EncodableValue(arg.second.boolean);
        break;
      case lyrics::ArgumentValue::Kind::kText:
        payload[flutter::EncodableValue(arg.first)] =
            flutter::EncodableValue(arg.second.text);
        break;
      case lyrics::ArgumentValue::Kind::kNone:
        break;
    }
  }
  channel_->InvokeMethod(event,
                         std::make_unique<flutter::EncodableValue>(payload));
}

void FloatingLyricsChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "canDrawOverlays" || method == "openOverlaySettings") {
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "hide") {
    window_.Hide();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "resetPosition") {
    window_.ResetPosition();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "getMonitors") {
    std::vector<lyrics::MonitorInfo> monitors;
    lyrics::EnumerateMonitors(&monitors);
    flutter::EncodableList list;
    list.reserve(monitors.size());
    for (const auto& monitor : monitors) {
      list.push_back(flutter::EncodableValue(MonitorToMap(monitor)));
    }
    result->Success(flutter::EncodableValue(list));
    return;
  }

  const auto* arguments = lyrics::ArgumentsAsMap(call.arguments());

  if (method == "setInteractive") {
    const bool interactive =
        arguments != nullptr ? lyrics::GetBool(*arguments, "interactive", true)
                             : true;
    window_.SetInteractive(interactive);
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "configure") {
    if (arguments == nullptr) {
      result->Error("INVALID_ARGUMENTS", "Floating lyrics style is missing");
      return;
    }
    const lyrics::FloatingLyricsStyle style =
        lyrics::ReadFloatingStyle(*arguments, window_.style());
    result->Success(flutter::EncodableValue(window_.Configure(style)));
    return;
  }

  if (method == "preview") {
    if (arguments == nullptr) {
      result->Error("INVALID_ARGUMENTS", "Preview payload is missing");
      return;
    }
    const std::string animation =
        lyrics::GetString(*arguments, "animation", "fade");
    const int duration_ms = lyrics::GetInt(*arguments, "durationMs", 2600);
    result->Success(flutter::EncodableValue(
        window_.Preview(animation, ReadSampleLines(*arguments), duration_ms)));
    return;
  }

  if (method == "show" || method == "update") {
    if (arguments == nullptr) {
      result->Error("INVALID_ARGUMENTS", "Floating lyrics payload is missing");
      return;
    }
    lyrics::FloatingLyricsStyle style =
        lyrics::ReadFloatingStyle(*arguments, window_.style());
    // The legacy payload carries the overlay geometry and colours inline; a
    // signed 32 bit ARGB must survive the trip.
    std::uint32_t text_color = 0;
    if (GetColorArgb(*arguments, "textColor", &text_color)) {
      style.text_color = lyrics::ColorFromArgb(text_color);
    }
    std::uint32_t highlight_color = 0;
    if (GetColorArgb(*arguments, "highlightColor", &highlight_color)) {
      style.highlight_color = lyrics::ColorFromArgb(highlight_color);
    }
    std::uint32_t background_color = 0;
    if (GetColorArgb(*arguments, "backgroundColor", &background_color)) {
      style.background_color = lyrics::ColorFromArgb(background_color);
    }
    window_.Configure(style);

    lyrics::LyricsFrame frame = lyrics::ReadLyricsFrame(*arguments);
    frame.has_song =
        frame.has_song || lyrics::GetBool(*arguments, "hasSong", false);
    result->Success(flutter::EncodableValue(window_.ShowFrame(frame)));
    return;
  }

  result->NotImplemented();
}

