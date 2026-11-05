#include "taskbar_lyrics_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <string>
#include <utility>
#include <vector>

#include "lyrics/lyrics_channel_args.h"

namespace {

constexpr char kChannelName[] = "com.mconnect.mconnect/taskbar_lyrics";

flutter::EncodableMap RectToMap(const RECT& rect) {
  flutter::EncodableMap map;
  map[flutter::EncodableValue("left")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.left));
  map[flutter::EncodableValue("top")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.top));
  map[flutter::EncodableValue("right")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.right));
  map[flutter::EncodableValue("bottom")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.bottom));
  return map;
}

flutter::EncodableMap TaskbarInfoToMap(const lyrics::TaskbarGeometry& geometry) {
  flutter::EncodableMap map;
  map[flutter::EncodableValue("monitor")] =
      flutter::EncodableValue(lyrics::Utf8FromWide(geometry.monitor_name));
  map[flutter::EncodableValue("edge")] = flutter::EncodableValue(
      std::string(lyrics::TaskbarEdgeName(geometry.edge)));
  map[flutter::EncodableValue("thickness")] =
      flutter::EncodableValue(static_cast<int32_t>(geometry.thickness));
  map[flutter::EncodableValue("taskbarRect")] =
      flutter::EncodableValue(RectToMap(geometry.taskbar_rect));
  map[flutter::EncodableValue("freeRect")] =
      flutter::EncodableValue(RectToMap(geometry.free_rect));
  map[flutter::EncodableValue("trayRect")] =
      flutter::EncodableValue(RectToMap(geometry.tray_rect));
  map[flutter::EncodableValue("taskListRect")] =
      flutter::EncodableValue(RectToMap(geometry.task_list_rect));
  map[flutter::EncodableValue("dpi")] =
      flutter::EncodableValue(static_cast<int32_t>(geometry.dpi));
  map[flutter::EncodableValue("autoHide")] =
      flutter::EncodableValue(geometry.auto_hide);
  map[flutter::EncodableValue("found")] = flutter::EncodableValue(geometry.found);
  return map;
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
    lines.emplace_back(lyrics::GetWideString(*entry, "text"),
                       lyrics::GetWideString(*entry, "translation"));
  }
  return lines;
}

}  // namespace

TaskbarLyricsChannel::TaskbarLyricsChannel(
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
}

TaskbarLyricsChannel::~TaskbarLyricsChannel() = default;

// Exported events: geometryChanged, taskbarStateChanged{autoHide,edge,
// spaceInsufficient}, positionChanged{offsetX,width} and closedByUser.
void TaskbarLyricsChannel::SendEventToFlutter(
    const std::string& event,
    const lyrics::EventArguments& args) {
  if (!channel_) {
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
  channel_->InvokeMethod(
      event, std::make_unique<flutter::EncodableValue>(payload));
}

void TaskbarLyricsChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "refreshGeometry") {
    result->Success(flutter::EncodableValue(window_.RefreshGeometry()));
    return;
  }

  if (method == "getTaskbarInfo") {
    const std::vector<lyrics::TaskbarGeometry> infos = window_.TaskbarInfo();
    flutter::EncodableList list;
    list.reserve(infos.size());
    for (const auto& info : infos) {
      list.push_back(flutter::EncodableValue(TaskbarInfoToMap(info)));
    }
    result->Success(flutter::EncodableValue(list));
    return;
  }

  if (method == "hide") {
    window_.Hide();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  const auto* arguments = lyrics::ArgumentsAsMap(call.arguments());

  if (method == "configure") {
    if (arguments == nullptr) {
      result->Error("INVALID_ARGUMENTS", "Taskbar style payload is missing");
      return;
    }
    const lyrics::TaskbarLyricsStyle style =
        lyrics::ReadTaskbarStyle(*arguments, window_.style());
    result->Success(flutter::EncodableValue(window_.Configure(style)));
    return;
  }

  if (method == "show" || method == "update") {
    if (arguments == nullptr) {
      result->Error("INVALID_ARGUMENTS", "Taskbar frame payload is missing");
      return;
    }
    const lyrics::LyricsFrame frame = lyrics::ReadLyricsFrame(*arguments);
    result->Success(flutter::EncodableValue(window_.ShowFrame(frame)));
    return;
  }

  if (method == "preview") {
    if (arguments == nullptr) {
      result->Error("INVALID_ARGUMENTS", "Preview payload is missing");
      return;
    }
    const std::string animation =
        lyrics::GetString(*arguments, "animation", "slideLeft");
    const int duration_ms = lyrics::GetInt(*arguments, "durationMs", 2600);
    result->Success(flutter::EncodableValue(
        window_.Preview(animation, ReadSampleLines(*arguments), duration_ms)));
    return;
  }

  result->NotImplemented();
}

