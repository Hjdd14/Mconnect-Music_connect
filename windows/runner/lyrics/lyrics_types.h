#ifndef RUNNER_LYRICS_LYRICS_TYPES_H_
#define RUNNER_LYRICS_LYRICS_TYPES_H_

#include <windows.h>

#include <cstdint>
#include <functional>
#include <string>
#include <utility>
#include <vector>

// Shared data for the Windows desktop lyrics stack.
//
// This header is deliberately free of Flutter, Direct2D and GDI+ types: the
// channels translate the platform payload into these structs, and the renderer
// and windows consume them. Everything here follows
// docs/desktop-lyrics-protocol.md; enum names are part of that protocol and
// must keep matching the Dart side, so they are parsed from and printed to
// those exact strings.
namespace lyrics {

// Line transitions (LyricsLineTransition). kRandom is resolved to a concrete
// transition when it starts, so the catalog has 18 drawable animations.
enum class LineTransition {
  kNone,
  kFade,
  kFadeThrough,
  kSlideLeft,
  kSlideRight,
  kSlideUp,
  kSlideDown,
  kPushLeft,
  kPushRight,
  kScaleIn,
  kScaleOut,
  kWipeLeft,
  kWipeRight,
  kFlipX,
  kFlipY,
  kDropBounce,
  kSpringUp,
  kGlowSoft,
  kRandom,
};

// Window transitions (LyricsWindowTransition).
enum class WindowTransition {
  kNone,
  kFade,
  kSlideFromTop,
  kSlideFromBottom,
  kSlideFromLeft,
  kSlideFromRight,
  kPop,
};

enum class Easing { kLinear, kEaseOut, kEaseInOut, kOvershoot };
enum class BackgroundMode { kNone, kSolid, kGradient, kCover };
enum class LineMode {
  kCurrentOnly,
  kCurrentAndTranslation,
  kCurrentAndNext,
  kThreeLines,
};
enum class TranslationRule { kAuto, kAlways, kNever };
// Taskbar translation placement. `stacked` is the legacy two-line strip;
// `inline` keeps the strip one line tall; `hidden` leaves only the main line.
enum class TranslationLayout { kStacked, kInline, kHidden };
enum class HorizontalAlign { kLeft, kCenter, kRight };

inline constexpr int kLineTransitionCount = 18;
inline constexpr int kWindowTransitionCount = 7;

inline double ClampDouble(double value, double low, double high) {
  if (value < low) {
    return low;
  }
  if (value > high) {
    return high;
  }
  return value;
}

inline double Clamp01(double value) { return ClampDouble(value, 0.0, 1.0); }

inline int ClampInt(int value, int low, int high) {
  if (value < low) {
    return low;
  }
  if (value > high) {
    return high;
  }
  return value;
}

// Straight ARGB as sent by Dart, kept as four channels so the renderers can
// hand it to Direct2D or GDI+ without depending on either.
struct ArgbColor {
  unsigned char a = 0;
  unsigned char r = 0;
  unsigned char g = 0;
  unsigned char b = 0;
};

inline ArgbColor ColorFromArgb(std::uint32_t argb) {
  ArgbColor color;
  color.a = static_cast<unsigned char>((argb >> 24) & 0xffu);
  color.r = static_cast<unsigned char>((argb >> 16) & 0xffu);
  color.g = static_cast<unsigned char>((argb >> 8) & 0xffu);
  color.b = static_cast<unsigned char>(argb & 0xffu);
  return color;
}

inline ArgbColor WithAlpha(const ArgbColor& color, double factor) {
  ArgbColor result = color;
  const double alpha = static_cast<double>(color.a) * Clamp01(factor);
  result.a = static_cast<unsigned char>(ClampDouble(alpha, 0.0, 255.0));
  return result;
}

inline bool IsVisible(const ArgbColor& color) { return color.a != 0; }

struct LyricsFrame {
  std::wstring text;
  std::wstring translation;
  std::wstring next_text;
  std::wstring next_translation;
  std::wstring song_title;
  std::wstring artist_name;
  std::wstring album_name;
  std::wstring cover_url;
  int line_index = 0;
  double progress = 0.0;
  double highlight_progress = 0.0;
  double highlight_rate = 0.0;
  std::vector<double> word_segments;
  bool is_playing = false;
  bool has_song = false;
  long long revision = 0;
};

struct FloatingLyricsStyle {
  bool enabled = false;
  ArgbColor text_color = {255, 255, 255, 255};
  ArgbColor highlight_color = {255, 255, 212, 74};
  ArgbColor background_color = {0, 0, 0, 0};
  ArgbColor background_color2 = {0, 0, 0, 0};
  ArgbColor stroke_color = {255, 0, 0, 0};
  double font_size = 23.0;
  double stroke_width = 0.7;
  double shadow_opacity = 0.78;
  double shadow_blur = 8.0;
  // Logical (device independent) pixels. The window multiplies by the monitor
  // scale when it sizes itself so a 23pt lyric stays 23pt on a 150% display.
  double width = 320.0;
  double height = 92.0;
  double position_y = 160.0;
  double position_x = -1.0;      // normalised 0..1, < 0 means centred
  double position_y_ratio = -1.0;  // normalised 0..1, < 0 means use position_y
  bool is_locked = false;
  std::wstring monitor_device_name;
  LineTransition line_animation = LineTransition::kFade;
  int animation_duration_ms = 220;
  Easing easing = Easing::kEaseOut;
  WindowTransition window_animation = WindowTransition::kFade;
  BackgroundMode background_mode = BackgroundMode::kNone;
  double background_opacity = 0.55;
  double corner_radius = 16.0;
  std::wstring font_family;
  int font_weight = 600;
  HorizontalAlign text_align = HorizontalAlign::kCenter;
  LineMode line_mode = LineMode::kCurrentAndTranslation;
  TranslationRule show_translation = TranslationRule::kAuto;
  double letter_spacing = 0.0;
  double line_height = 1.2;
  double padding = 12.0;
  bool show_controls = true;
  // Taskbar-only: how the translation sits next to the main line. The
  // floating window keeps its own stacked layout.
  TranslationLayout translation_layout = TranslationLayout::kStacked;
  bool click_through = false;
  bool always_on_top = true;
  bool hide_in_fullscreen = true;
  bool reduce_motion = true;
  bool word_highlight = true;
  std::wstring cover_image_path;
};

struct TaskbarLyricsStyle {
  bool enabled = false;
  std::wstring monitor_device_name = L"primary";
  HorizontalAlign anchor = HorizontalAlign::kCenter;
  bool anchor_auto = true;
  double offset_x = 0.0;
  double width = 560.0;
  double height = 0.0;  // 0 = fill the taskbar height
  double font_size = 16.0;
  std::wstring font_family;
  int font_weight = 600;
  ArgbColor text_color = {255, 255, 255, 255};
  ArgbColor highlight_color = {255, 255, 212, 74};
  BackgroundMode background_mode = BackgroundMode::kSolid;
  ArgbColor background_color = {255, 0, 0, 0};
  double background_opacity = 0.35;
  LineMode line_mode = LineMode::kCurrentAndTranslation;
  TranslationLayout translation_layout = TranslationLayout::kStacked;
  LineTransition line_animation = LineTransition::kSlideLeft;
  int animation_duration_ms = 200;
  Easing easing = Easing::kEaseOut;
  WindowTransition window_animation = WindowTransition::kFade;
  bool click_through = true;
  bool follow_auto_hide = true;
  bool hide_in_fullscreen = true;
  bool marquee = true;
  double edge_padding = 8.0;
  double corner_radius = 8.0;
  bool debug_geometry = false;
  // Honours the system/settings "reduce motion" switch for the taskbar strip
  // too: the floating overlay already reads it, so the strip must not fade and
  // slide when the user asked for calm.
  bool reduce_motion = false;
};

struct MonitorInfo {
  std::wstring device_name;
  RECT bounds = {};
  UINT dpi = 96;
  bool is_primary = false;
};

// A single native event argument, so one callback can carry the typed maps the
// protocol defines without dragging Flutter's encodable types into the
// renderer and window layers.
struct ArgumentValue {
  enum class Kind { kNone, kNumber, kBoolean, kText };

  Kind kind = Kind::kNone;
  double number = 0.0;
  bool boolean = false;
  std::string text;

  static ArgumentValue Number(double value) {
    ArgumentValue argument;
    argument.kind = Kind::kNumber;
    argument.number = value;
    return argument;
  }
  static ArgumentValue Boolean(bool value) {
    ArgumentValue argument;
    argument.kind = Kind::kBoolean;
    argument.boolean = value;
    return argument;
  }
  static ArgumentValue Text(std::string value) {
    ArgumentValue argument;
    argument.kind = Kind::kText;
    argument.text = std::move(value);
    return argument;
  }
};

using EventArguments = std::vector<std::pair<std::string, ArgumentValue>>;
using EventListener =
    std::function<void(const std::string&, const EventArguments&)>;

inline const char* LineTransitionName(LineTransition transition) {
  switch (transition) {
    case LineTransition::kNone:
      return "none";
    case LineTransition::kFade:
      return "fade";
    case LineTransition::kFadeThrough:
      return "fadeThrough";
    case LineTransition::kSlideLeft:
      return "slideLeft";
    case LineTransition::kSlideRight:
      return "slideRight";
    case LineTransition::kSlideUp:
      return "slideUp";
    case LineTransition::kSlideDown:
      return "slideDown";
    case LineTransition::kPushLeft:
      return "pushLeft";
    case LineTransition::kPushRight:
      return "pushRight";
    case LineTransition::kScaleIn:
      return "scaleIn";
    case LineTransition::kScaleOut:
      return "scaleOut";
    case LineTransition::kWipeLeft:
      return "wipeLeft";
    case LineTransition::kWipeRight:
      return "wipeRight";
    case LineTransition::kFlipX:
      return "flipX";
    case LineTransition::kFlipY:
      return "flipY";
    case LineTransition::kDropBounce:
      return "dropBounce";
    case LineTransition::kSpringUp:
      return "springUp";
    case LineTransition::kGlowSoft:
      return "glowSoft";
    case LineTransition::kRandom:
      return "random";
  }
  return "fade";
}

inline const char* WindowTransitionName(WindowTransition transition) {
  switch (transition) {
    case WindowTransition::kNone:
      return "none";
    case WindowTransition::kFade:
      return "fade";
    case WindowTransition::kSlideFromTop:
      return "slideFromTop";
    case WindowTransition::kSlideFromBottom:
      return "slideFromBottom";
    case WindowTransition::kSlideFromLeft:
      return "slideFromLeft";
    case WindowTransition::kSlideFromRight:
      return "slideFromRight";
    case WindowTransition::kPop:
      return "pop";
  }
  return "fade";
}

inline const char* EasingName(Easing easing) {
  switch (easing) {
    case Easing::kLinear:
      return "linear";
    case Easing::kEaseOut:
      return "easeOut";
    case Easing::kEaseInOut:
      return "easeInOut";
    case Easing::kOvershoot:
      return "overshoot";
  }
  return "easeOut";
}

inline LineTransition ParseLineTransition(const std::string& name) {
  for (int index = 0; index <= static_cast<int>(LineTransition::kRandom);
       ++index) {
    const auto candidate = static_cast<LineTransition>(index);
    if (name == LineTransitionName(candidate)) {
      return candidate;
    }
  }
  return LineTransition::kFade;
}

inline WindowTransition ParseWindowTransition(const std::string& name) {
  for (int index = 0; index <= static_cast<int>(WindowTransition::kPop);
       ++index) {
    const auto candidate = static_cast<WindowTransition>(index);
    if (name == WindowTransitionName(candidate)) {
      return candidate;
    }
  }
  return WindowTransition::kFade;
}

inline Easing ParseEasing(const std::string& name) {
  for (int index = 0; index <= static_cast<int>(Easing::kOvershoot); ++index) {
    const auto candidate = static_cast<Easing>(index);
    if (name == EasingName(candidate)) {
      return candidate;
    }
  }
  return Easing::kEaseOut;
}

inline BackgroundMode ParseBackgroundMode(const std::string& name) {
  if (name == "solid") {
    return BackgroundMode::kSolid;
  }
  if (name == "gradient") {
    return BackgroundMode::kGradient;
  }
  if (name == "cover") {
    return BackgroundMode::kCover;
  }
  return BackgroundMode::kNone;
}

inline LineMode ParseLineMode(const std::string& name) {
  if (name == "currentOnly") {
    return LineMode::kCurrentOnly;
  }
  if (name == "currentAndNext") {
    return LineMode::kCurrentAndNext;
  }
  if (name == "threeLines") {
    return LineMode::kThreeLines;
  }
  return LineMode::kCurrentAndTranslation;
}

inline TranslationLayout ParseTranslationLayout(const std::string& name) {
  if (name == "inline") {
    return TranslationLayout::kInline;
  }
  if (name == "hidden") {
    return TranslationLayout::kHidden;
  }
  return TranslationLayout::kStacked;
}

inline TranslationRule ParseTranslationRule(const std::string& name) {
  if (name == "always") {
    return TranslationRule::kAlways;
  }
  if (name == "never") {
    return TranslationRule::kNever;
  }
  return TranslationRule::kAuto;
}

inline HorizontalAlign ParseHorizontalAlign(const std::string& name) {
  if (name == "left") {
    return HorizontalAlign::kLeft;
  }
  if (name == "right") {
    return HorizontalAlign::kRight;
  }
  return HorizontalAlign::kCenter;
}

inline std::string Utf8FromWide(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()),
                                       nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    return std::string();
  }
  std::string result(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

inline std::wstring WideFromUtf8(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()),
                                       nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

}  // namespace lyrics

#endif  // RUNNER_LYRICS_LYRICS_TYPES_H_
