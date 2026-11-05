#ifndef RUNNER_LYRICS_LYRICS_CHANNEL_ARGS_H_
#define RUNNER_LYRICS_LYRICS_CHANNEL_ARGS_H_

#include <flutter/encodable_value.h>

#include <cstdint>
#include <string>
#include <vector>

#include "lyrics_types.h"

// Translation from the platform payload into the shared lyrics structs.
//
// Every reader is defensive: a missing key keeps the value from the base style
// and a value of the wrong type falls back instead of throwing, because the
// protocol promises that an unknown or malformed field must never crash the
// native side.
namespace lyrics {

inline const flutter::EncodableValue* FindValue(const flutter::EncodableMap& map,
                                                const char* key) {
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) {
    return nullptr;
  }
  return &it->second;
}

inline bool HasKey(const flutter::EncodableMap& map, const char* key) {
  const auto* value = FindValue(map, key);
  return value != nullptr && !value->IsNull();
}

inline const flutter::EncodableMap* ArgumentsAsMap(
    const flutter::EncodableValue* arguments) {
  if (arguments == nullptr || arguments->IsNull()) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(arguments);
}

inline const flutter::EncodableList* GetList(const flutter::EncodableMap& map,
                                             const char* key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableList>(value);
}

inline std::string GetString(const flutter::EncodableMap& map,
                             const char* key,
                             const std::string& fallback = std::string()) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return fallback;
  }
  if (const auto* string_value = std::get_if<std::string>(value)) {
    return *string_value;
  }
  return fallback;
}

inline std::wstring GetWideString(const flutter::EncodableMap& map,
                                  const char* key,
                                  const std::wstring& fallback = std::wstring()) {
  if (!HasKey(map, key)) {
    return fallback;
  }
  return WideFromUtf8(GetString(map, key));
}

inline int GetInt(const flutter::EncodableMap& map,
                  const char* key,
                  int fallback) {
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

inline double GetDouble(const flutter::EncodableMap& map,
                        const char* key,
                        double fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return fallback;
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    return *double_value;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return static_cast<double>(*int32_value);
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return static_cast<double>(*int64_value);
  }
  return fallback;
}

inline bool GetBool(const flutter::EncodableMap& map,
                    const char* key,
                    bool fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return fallback;
  }
  if (const auto* bool_value = std::get_if<bool>(value)) {
    return *bool_value;
  }
  return fallback;
}

// Colours arrive as 32 bit ARGB, sometimes already truncated to a negative
// signed int by a codec; the high bit is data, not an error.
inline bool GetColorArgb(const flutter::EncodableMap& map,
                         const char* key,
                         std::uint32_t* argb) {
  const auto* value = FindValue(map, key);
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

inline ArgbColor GetColor(const flutter::EncodableMap& map,
                          const char* key,
                          const ArgbColor& fallback) {
  std::uint32_t argb = 0;
  if (!GetColorArgb(map, key, &argb)) {
    return fallback;
  }
  return ColorFromArgb(argb);
}

inline std::vector<double> GetDoubleList(const flutter::EncodableMap& map,
                                         const char* key) {
  std::vector<double> result;
  const flutter::EncodableList* list = GetList(map, key);
  if (list == nullptr) {
    return result;
  }
  result.reserve(list->size());
  for (const auto& item : *list) {
    if (const auto* double_value = std::get_if<double>(&item)) {
      result.push_back(*double_value);
    } else if (const auto* int32_value = std::get_if<int32_t>(&item)) {
      result.push_back(static_cast<double>(*int32_value));
    } else if (const auto* int64_value = std::get_if<int64_t>(&item)) {
      result.push_back(static_cast<double>(*int64_value));
    }
  }
  return result;
}

inline LyricsFrame ReadLyricsFrame(const flutter::EncodableMap& map) {
  LyricsFrame frame;
  frame.text = GetWideString(map, "text");
  frame.translation = GetWideString(map, "translation");
  frame.next_text = GetWideString(map, "nextText");
  frame.next_translation = GetWideString(map, "nextTranslation");
  frame.song_title = GetWideString(map, "songTitle");
  frame.artist_name = GetWideString(map, "artistName");
  frame.album_name = GetWideString(map, "albumName");
  frame.cover_url = GetWideString(map, "coverUrl");
  frame.line_index = GetInt(map, "lineIndex", 0);
  frame.progress = Clamp01(GetDouble(map, "progress", 0.0));
  frame.highlight_progress =
      Clamp01(GetDouble(map, "highlightProgress", 0.0));
  frame.highlight_rate = std::max(0.0, GetDouble(map, "highlightRate", 0.0));
  frame.is_playing = GetBool(map, "isPlaying", false);
  frame.has_song = GetBool(map, "hasSong", false);
  frame.revision = static_cast<long long>(GetInt(map, "revision", 0));
  frame.word_segments = GetDoubleList(map, "wordSegments");
  // The protocol caps the segment table at 32 cumulative boundaries.
  if (frame.word_segments.size() > 32) {
    frame.word_segments.resize(32);
  }
  return frame;
}

inline FloatingLyricsStyle ReadFloatingStyle(const flutter::EncodableMap& map,
                                             FloatingLyricsStyle base) {
  base.enabled = GetBool(map, "enabled", base.enabled);
  base.text_color = GetColor(map, "textColor", base.text_color);
  base.highlight_color = GetColor(map, "highlightColor", base.highlight_color);
  base.background_color = GetColor(map, "backgroundColor", base.background_color);
  base.background_color2 =
      GetColor(map, "backgroundColor2", base.background_color2);
  base.stroke_color = GetColor(map, "strokeColor", base.stroke_color);
  base.font_size = ClampDouble(GetDouble(map, "fontSize", base.font_size), 12.0,
                               56.0);
  base.stroke_width =
      ClampDouble(GetDouble(map, "strokeWidth", base.stroke_width), 0.0, 6.0);
  base.shadow_opacity = Clamp01(
      GetDouble(map, "shadowOpacity", base.shadow_opacity));
  base.shadow_blur = ClampDouble(GetDouble(map, "shadowBlur", base.shadow_blur),
                                 0.0, 48.0);
  base.width = ClampDouble(GetDouble(map, "width", base.width), 140.0, 900.0);
  base.height = ClampDouble(GetDouble(map, "height", base.height), 48.0, 260.0);
  base.position_y = GetDouble(map, "positionY", base.position_y);
  if (HasKey(map, "positionX")) {
    base.position_x = GetDouble(map, "positionX", base.position_x);
  }
  if (HasKey(map, "positionYRatio")) {
    base.position_y_ratio = GetDouble(map, "positionYRatio", base.position_y_ratio);
  }
  base.is_locked = GetBool(map, "isLocked", base.is_locked);
  base.monitor_device_name =
      GetWideString(map, "monitorDeviceName", base.monitor_device_name);
  base.line_animation =
      ParseLineTransition(GetString(map, "lineAnimation",
                                    LineTransitionName(base.line_animation)));
  base.animation_duration_ms =
      ClampInt(GetInt(map, "animationDurationMs", base.animation_duration_ms), 0,
               1000);
  base.easing = ParseEasing(
      GetString(map, "easing", EasingName(base.easing)));
  base.window_animation = ParseWindowTransition(
      GetString(map, "windowAnimation",
                 WindowTransitionName(base.window_animation)));
  base.background_mode = ParseBackgroundMode(
      GetString(map, "backgroundMode", "none"));
  base.background_opacity =
      Clamp01(GetDouble(map, "backgroundOpacity", base.background_opacity));
  base.corner_radius =
      ClampDouble(GetDouble(map, "cornerRadius", base.corner_radius), 0.0, 48.0);
  base.font_family = GetWideString(map, "fontFamily", base.font_family);
  base.font_weight =
      ClampInt(GetInt(map, "fontWeight", base.font_weight), 100, 900);
  base.text_align = ParseHorizontalAlign(
      GetString(map, "textAlign", "center"));
  base.line_mode = ParseLineMode(GetString(map, "lineMode",
                                           "currentAndTranslation"));
  base.show_translation = ParseTranslationRule(
      GetString(map, "showTranslation", "auto"));
  base.letter_spacing =
      ClampDouble(GetDouble(map, "letterSpacing", base.letter_spacing), -5.0,
                  20.0);
  base.line_height = ClampDouble(
      GetDouble(map, "lineHeight", base.line_height), 0.8, 3.0);
  base.padding =
      ClampDouble(GetDouble(map, "padding", base.padding), 0.0, 64.0);
  base.show_controls = GetBool(map, "showControls", base.show_controls);
  base.click_through = GetBool(map, "clickThrough", base.click_through);
  base.always_on_top = GetBool(map, "alwaysOnTop", base.always_on_top);
  base.hide_in_fullscreen =
      GetBool(map, "hideInFullscreen", base.hide_in_fullscreen);
  base.reduce_motion = GetBool(map, "reduceMotion", base.reduce_motion);
  base.word_highlight = GetBool(map, "wordHighlight", base.word_highlight);
  base.cover_image_path =
      GetWideString(map, "coverImagePath", base.cover_image_path);
  return base;
}

inline TaskbarLyricsStyle ReadTaskbarStyle(const flutter::EncodableMap& map,
                                           TaskbarLyricsStyle base) {
  base.enabled = GetBool(map, "enabled", base.enabled);
  base.monitor_device_name =
      GetWideString(map, "monitorDeviceName", base.monitor_device_name);
  const std::string anchor = GetString(map, "anchor", "auto");
  base.anchor_auto = anchor == "auto";
  base.anchor = ParseHorizontalAlign(anchor);
  base.offset_x = GetDouble(map, "offsetX", base.offset_x);
  base.width = ClampDouble(GetDouble(map, "width", base.width), 0.0, 4000.0);
  base.height = ClampDouble(GetDouble(map, "height", base.height), 0.0, 200.0);
  base.font_size =
      ClampDouble(GetDouble(map, "fontSize", base.font_size), 8.0, 40.0);
  base.font_family = GetWideString(map, "fontFamily", base.font_family);
  base.font_weight =
      ClampInt(GetInt(map, "fontWeight", base.font_weight), 100, 900);
  base.text_color = GetColor(map, "textColor", base.text_color);
  base.highlight_color = GetColor(map, "highlightColor", base.highlight_color);
  base.background_mode = ParseBackgroundMode(
      GetString(map, "backgroundMode", "solid"));
  base.background_color =
      GetColor(map, "backgroundColor", base.background_color);
  // Dart sends backgroundOpacity (lib/core/lyrics/lyrics_overlay_config.dart);
  // the old "opacity" key stays as a fallback so a stale caller still dims the
  // strip instead of silently keeping the default.
  base.background_opacity = Clamp01(GetDouble(
      map, HasKey(map, "backgroundOpacity") ? "backgroundOpacity" : "opacity",
      base.background_opacity));
  base.reduce_motion = GetBool(map, "reduceMotion", base.reduce_motion);
  base.line_mode = ParseLineMode(GetString(map, "lineMode", "auto"));
  base.translation_layout = ParseTranslationLayout(
      GetString(map, "translationLayout", "stacked"));
  base.line_animation = ParseLineTransition(
      GetString(map, "lineAnimation", "slideLeft"));
  base.animation_duration_ms =
      ClampInt(GetInt(map, "animationDurationMs", base.animation_duration_ms), 0,
               1000);
  base.easing = ParseEasing(
      GetString(map, "easing", EasingName(base.easing)));
  base.window_animation = ParseWindowTransition(
      GetString(map, "windowAnimation", "fade"));
  base.click_through = GetBool(map, "clickThrough", base.click_through);
  base.follow_auto_hide = GetBool(map, "followAutoHide", base.follow_auto_hide);
  base.hide_in_fullscreen =
      GetBool(map, "hideInFullscreen", base.hide_in_fullscreen);
  base.marquee = GetBool(map, "marquee", base.marquee);
  base.edge_padding =
      ClampDouble(GetDouble(map, "edgePadding", base.edge_padding), 0.0, 48.0);
  base.corner_radius =
      ClampDouble(GetDouble(map, "cornerRadius", base.corner_radius), 0.0, 32.0);
  base.debug_geometry = GetBool(map, "debugGeometry", base.debug_geometry);
  return base;
}

}  // namespace lyrics

#endif  // RUNNER_LYRICS_LYRICS_CHANNEL_ARGS_H_
