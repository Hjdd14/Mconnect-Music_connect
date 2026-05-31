#include "floating_lyrics_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cstdint>
#include <string>

namespace {

constexpr char kChannelName[] = "com.mconnect.mconnect/floating_lyrics";

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr,
                                       0);
  if (size <= 0) {
    return L"";
  }
  std::wstring result(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), size);
  return result;
}

const flutter::EncodableValue* FindValue(const flutter::EncodableMap& map,
                                         const char* key) {
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) {
    return nullptr;
  }
  return &it->second;
}

std::string GetString(const flutter::EncodableMap& map, const char* key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return "";
  }
  if (const auto* string_value = std::get_if<std::string>(value)) {
    return *string_value;
  }
  return "";
}

int GetInt(const flutter::EncodableMap& map, const char* key, int fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return fallback;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return *int32_value;
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return static_cast<int>(*int64_value);
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    return static_cast<int>(*double_value);
  }
  return fallback;
}

COLORREF GetColor(const flutter::EncodableMap& map,
                  const char* key,
                  COLORREF fallback) {
  const int argb = GetInt(map, key, -1);
  if (argb < 0) {
    return fallback;
  }
  return RGB((argb >> 16) & 0xff, (argb >> 8) & 0xff, argb & 0xff);
}

const flutter::EncodableMap* ArgumentsAsMap(
    const flutter::EncodableValue* arguments) {
  if (arguments == nullptr || arguments->IsNull()) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(arguments);
}

}  // namespace

FloatingLyricsChannel::FloatingLyricsChannel(
    flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

FloatingLyricsChannel::~FloatingLyricsChannel() = default;

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

  if (method == "show" || method == "update") {
    const auto* arguments = ArgumentsAsMap(call.arguments());
    if (arguments == nullptr) {
      result->Error("INVALID_ARGUMENTS", "Floating lyrics payload is missing");
      return;
    }

    const std::wstring text = Utf8ToWide(GetString(*arguments, "text"));
    const std::wstring translation =
        Utf8ToWide(GetString(*arguments, "translation"));
    const int width = GetInt(*arguments, "width", 420);
    const int height = GetInt(*arguments, "height", 112);
    const int font_size = GetInt(*arguments, "fontSize", 24);
    const COLORREF text_color =
        GetColor(*arguments, "textColor", RGB(255, 255, 255));

    const bool ok = method == "show"
                        ? window_.Show(text, translation, width, height,
                                       font_size, text_color)
                        : window_.Update(text, translation, width, height,
                                         font_size, text_color);
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  result->NotImplemented();
}
