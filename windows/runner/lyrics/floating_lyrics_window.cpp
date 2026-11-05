#include "floating_lyrics_window.h"

#include <windowsx.h>

#include <algorithm>
#include <cmath>

#include "lyrics_renderer.h"

namespace {

constexpr const wchar_t kClassName[] = L"MCONNECT_FLOATING_LYRICS_WINDOW";
constexpr double kMinLogicalWidth = 140.0;
constexpr double kMaxLogicalWidth = 900.0;
constexpr double kMinLogicalHeight = 48.0;
constexpr double kMaxLogicalHeight = 260.0;
constexpr double kMinFontSize = 12.0;
constexpr double kMaxFontSize = 56.0;
constexpr double kMarqueePauseMs = 700.0;
constexpr double kMarqueePixelsPerMs = 0.045;

lyrics::ArgbColor FromColorRef(COLORREF color) {
  lyrics::ArgbColor result;
  result.a = 255;
  result.r = GetRValue(color);
  result.g = GetGValue(color);
  result.b = GetBValue(color);
  return result;
}

const lyrics::ArgbColor kHighlightPalette[] = {
    {255, 255, 212, 74},
    {255, 74, 168, 255},
    {255, 124, 227, 139},
    {255, 255, 143, 177},
};
constexpr int kHighlightPaletteSize =
    static_cast<int>(sizeof(kHighlightPalette) / sizeof(kHighlightPalette[0]));

}  // namespace

FloatingLyricsWindow::FloatingLyricsWindow() {
  line_animator_.Configure(lyrics::LineTransition::kFade, 220,
                           lyrics::Easing::kEaseOut, true);
  window_animator_.Configure(lyrics::WindowTransition::kFade, 220,
                             lyrics::Easing::kEaseOut, true);
}

FloatingLyricsWindow::~FloatingLyricsWindow() { Destroy(); }

void FloatingLyricsWindow::SetEventCallback(
    std::function<void(const std::string&)> callback) {
  legacy_event_callback_ = std::move(callback);
}

void FloatingLyricsWindow::Emit(const std::string& name,
                                const lyrics::EventArguments& args) {
  LyricsWindowBase::Emit(name, args);
  // The pre-protocol Dart side only knows event names, so keep that callback
  // working alongside the typed listener the channel installs.
  if (legacy_event_callback_) {
    legacy_event_callback_(name);
  }
}

bool FloatingLyricsWindow::renderer_fallback() const {
  return renderer()->kind() == lyrics::RendererKind::kGdiPlus;
}

bool FloatingLyricsWindow::EnsureCreated() {
  if (hwnd() != nullptr) {
    return true;
  }
  const double scale = dpi_scale();
  const int width_px = std::max(
      1, static_cast<int>(std::lround(style_.width * scale)));
  const int height_px = std::max(
      1, static_cast<int>(std::lround(style_.height * scale)));
  if (!Create(kClassName, L"Mconnect Floating Lyrics", width_px, height_px)) {
    return false;
  }
  UpdateClickThrough();
  return true;
}

bool FloatingLyricsWindow::Show(const std::wstring& text,
                                const std::wstring& translation,
                                int width,
                                int height,
                                int font_size,
                                COLORREF text_color,
                                bool locked,
                                const std::wstring& next_text,
                                COLORREF highlight_color,
                                double highlight_progress) {
  style_.width = lyrics::ClampDouble(static_cast<double>(width),
                                     kMinLogicalWidth, kMaxLogicalWidth);
  style_.height = lyrics::ClampDouble(static_cast<double>(height),
                                      kMinLogicalHeight, kMaxLogicalHeight);
  style_.font_size = lyrics::ClampDouble(static_cast<double>(font_size),
                                         kMinFontSize, kMaxFontSize);
  style_.text_color = FromColorRef(text_color);
  style_.highlight_color = FromColorRef(highlight_color);
  style_.is_locked = locked;
  is_locked_ = locked;

  lyrics::LyricsFrame frame = frame_;
  frame.text = text;
  frame.translation = translation;
  frame.next_text = next_text;
  frame.highlight_progress = highlight_progress;
  frame.has_song = frame.has_song || !text.empty();
  return ApplyFrame(frame, true);
}

bool FloatingLyricsWindow::Update(const std::wstring& text,
                                  const std::wstring& translation,
                                  int width,
                                  int height,
                                  int font_size,
                                  COLORREF text_color,
                                  bool locked,
                                  const std::wstring& next_text,
                                  COLORREF highlight_color,
                                  double highlight_progress) {
  return Show(text, translation, width, height, font_size, text_color, locked,
              next_text, highlight_color, highlight_progress);
}

bool FloatingLyricsWindow::ShowFrame(const lyrics::LyricsFrame& frame) {
  // Stale frames (an older revision arriving after a newer one) are dropped so
  // a slow platform thread cannot rewind the line.
  if (frame.revision > 0 && frame_.revision > 0 &&
      frame.revision < frame_.revision) {
    return true;
  }
  return ApplyFrame(frame, true);
}

bool FloatingLyricsWindow::ApplyFrame(const lyrics::LyricsFrame& frame,
                                      bool show) {
  const long long now = lyrics::NowMilliseconds();
  const bool text_changed = frame.text != frame_.text ||
                            frame.translation != frame_.translation ||
                            frame.next_text != frame_.next_text;
  if (text_changed) {
    line_animator_.Start(frame_.text, frame_.translation, now);
    ResetMarquee(now);
  }
  frame_ = frame;
  frame_received_at_ = now;
  if (!EnsureCreated()) {
    return false;
  }
  ApplyLayout();
  if (show) {
    shown_ = true;
    if (!visible()) {
      window_animator_.Start(true, now);
      ShowNoActivate();
      hidden_for_fullscreen_ = false;
    }
    if (!ready_reported_) {
      ready_reported_ = true;
      Emit("ready");
    }
  }
  RequestFrame();
  return true;
}

bool FloatingLyricsWindow::Configure(const lyrics::FloatingLyricsStyle& style) {
  style_ = style;
  is_locked_ = style.is_locked;
  line_animator_.Configure(style.line_animation, style.animation_duration_ms,
                           style.easing, style.reduce_motion);
  window_animator_.Configure(style.window_animation,
                             style.animation_duration_ms, style.easing,
                             style.reduce_motion);
  if (!EnsureCreated()) {
    return false;
  }
  UpdateClickThrough();
  SetTopmost(style.always_on_top);
  ApplyLayout();
  RequestFrame();
  return true;
}

bool FloatingLyricsWindow::Preview(
    const std::string& animation,
    const std::vector<std::pair<std::wstring, std::wstring>>& sample_lines,
    int duration_ms) {
  if (sample_lines.empty()) {
    return false;
  }
  const long long now = lyrics::NowMilliseconds();
  preview_lines_ = sample_lines;
  preview_animation_ = animation;
  preview_index_ = 0;
  preview_started_at_ = now;
  preview_until_ = now + std::max(600, duration_ms);
  line_animator_.Configure(lyrics::ParseLineTransition(animation),
                           std::max(80, style_.animation_duration_ms),
                           style_.easing, style_.reduce_motion);
  // A preview must be visible even when the app never sent a frame, so open
  // the window with the sample text instead of waiting for playback.
  if (!EnsureCreated()) {
    return false;
  }
  ApplyLayout();
  shown_ = true;
  if (!visible()) {
    window_animator_.Start(true, now);
    ShowNoActivate();
  }
  RequestFrame();
  return true;
}

void FloatingLyricsWindow::ResetPosition() {
  style_.position_x = -1.0;
  style_.position_y_ratio = -1.0;
  style_.position_y = 80.0;
  if (hwnd() != nullptr) {
    ApplyLayout();
    RequestFrame();
  }
}

void FloatingLyricsWindow::SetInteractive(bool interactive) {
  interactive_ = interactive;
  if (hwnd() != nullptr) {
    UpdateClickThrough();
  }
}

void FloatingLyricsWindow::Hide() {
  shown_ = false;
  hidden_for_fullscreen_ = false;
  if (!visible()) {
    LyricsWindowBase::Hide();
    return;
  }
  const long long now = lyrics::NowMilliseconds();
  window_animator_.Start(false, now);
  if (!window_animator_.active()) {
    LyricsWindowBase::Hide();
    return;
  }
  RequestFrame();
}

int FloatingLyricsWindow::GetWidth() const {
  return static_cast<int>(std::lround(style_.width));
}

int FloatingLyricsWindow::GetHeight() const {
  return static_cast<int>(std::lround(style_.height));
}

bool FloatingLyricsWindow::IsLocked() const { return style_.is_locked; }

LRESULT CALLBACK FloatingLyricsWindow::WndProc(HWND hwnd,
                                              UINT message,
                                              WPARAM wparam,
                                              LPARAM lparam) {
  return LyricsWindowBase::WindowProc(hwnd, message, wparam, lparam);
}

void FloatingLyricsWindow::UpdateClickThrough() {
  // A click-through overlay can never be unlocked or closed again, so the
  // explicit style flag wins over the interactive default.
  SetClickThrough(!interactive_ || style_.click_through);
}

lyrics::MonitorInfo FloatingLyricsWindow::ResolveMonitor() const {
  std::vector<lyrics::MonitorInfo> monitors;
  lyrics::EnumerateMonitors(&monitors);
  const lyrics::MonitorInfo* found =
      lyrics::FindMonitor(monitors, style_.monitor_device_name);
  if (found != nullptr) {
    return *found;
  }
  lyrics::MonitorInfo fallback;
  fallback.bounds = RECT{0, 0, GetSystemMetrics(SM_CXSCREEN),
                         GetSystemMetrics(SM_CYSCREEN)};
  fallback.dpi = 96;
  fallback.is_primary = true;
  return fallback;
}

void FloatingLyricsWindow::ApplyLayout() {
  if (dragging_ || resizing_) return;
  if (hwnd() == nullptr) {
    return;
  }
  const lyrics::MonitorInfo monitor = ResolveMonitor();
  const double scale = dpi_scale();
  const int window_width = std::max(
      1, static_cast<int>(std::lround(style_.width * scale)));
  const int window_height = std::max(
      1, static_cast<int>(std::lround(style_.height * scale)));
  const int monitor_width = monitor.bounds.right - monitor.bounds.left;
  const int monitor_height = monitor.bounds.bottom - monitor.bounds.top;

  int x = monitor.bounds.left + (monitor_width - window_width) / 2;
  if (style_.position_x >= 0.0) {
    x = monitor.bounds.left +
        static_cast<int>(std::lround(
            static_cast<double>(monitor_width - window_width) *
            lyrics::Clamp01(style_.position_x)));
  }
  int y = monitor.bounds.top + static_cast<int>(std::lround(80.0 * scale));
  if (style_.position_y_ratio >= 0.0) {
    y = monitor.bounds.top +
        static_cast<int>(std::lround(
            static_cast<double>(monitor_height - window_height) *
            lyrics::Clamp01(style_.position_y_ratio)));
  } else if (style_.position_y > 0.0) {
    y = monitor.bounds.top +
        static_cast<int>(std::lround(style_.position_y * scale));
  }
  x = lyrics::ClampInt(x, monitor.bounds.left,
                       monitor.bounds.right - window_width);
  y = lyrics::ClampInt(y, monitor.bounds.top,
                       monitor.bounds.bottom - window_height);
  SetBounds(x, y, window_width, window_height, visible());
}

void FloatingLyricsWindow::ResetMarquee(long long now_ms) {
  marquee_started_at_ = now_ms;
  marquee_active_ = false;
}

double FloatingLyricsWindow::ComputeMarqueeOffset(const std::wstring& text,
                                                  long long now_ms) {
  const double scale = dpi_scale();
  const int window_width = std::max(1, width());
  const int window_height = std::max(1, height());
  const lyrics::ControlLayout layout = lyrics::ComputeControlLayout(
      style_, window_width, window_height, scale, frame_.has_song);
  const double area_width =
      static_cast<double>(layout.lyric_area.right - layout.lyric_area.left);
  const double font_size = std::max(11.0, style_.font_size * scale);
  const double text_width = renderer()->MeasureLineWidth(
      style_, text, font_size, style_.letter_spacing * scale);
  marquee_active_ = area_width > 1.0 && text_width > area_width + 1.0;
  if (!marquee_active_) {
    return 0.0;
  }
  const double elapsed = static_cast<double>(now_ms - marquee_started_at_);
  if (elapsed <= kMarqueePauseMs) {
    return 0.0;
  }
  const double distance = text_width + area_width + 48.0 * scale;
  const double travelled =
      (elapsed - kMarqueePauseMs) * kMarqueePixelsPerMs * scale;
  return std::fmod(travelled, distance);
}

double FloatingLyricsWindow::ComputeHighlightProgress(long long now_ms) const {
  if (preview_until_ > 0) {
    return 0.0;
  }
  double progress = frame_.highlight_progress;
  if (frame_.is_playing && frame_.highlight_rate > 0.0 &&
      frame_received_at_ > 0) {
    progress += frame_.highlight_rate *
                static_cast<double>(now_ms - frame_received_at_);
  }
  return lyrics::Clamp01(progress);
}

const lyrics::LyricsFrame& FloatingLyricsWindow::EffectiveFrame(
    long long now_ms) {
  if (preview_until_ <= 0 || preview_lines_.empty()) {
    return frame_;
  }
  if (now_ms >= preview_until_) {
    preview_until_ = 0;
    preview_started_at_ = 0;
    preview_index_ = 0;
    preview_lines_.clear();
    preview_animation_.clear();
    line_animator_.Stop();
    return frame_;
  }
  const std::size_t count = preview_lines_.size();
  const long long total = preview_until_ - preview_started_at_;
  const long long step = std::max<long long>(1, total / static_cast<long long>(count));
  const std::size_t raw = static_cast<std::size_t>(
      std::max<long long>(0, (now_ms - preview_started_at_) / step));
  const std::size_t index = std::min(count - 1, raw);
  if (index != preview_index_) {
    line_animator_.Start(preview_lines_[preview_index_].first,
                         preview_lines_[preview_index_].second, now_ms);
    preview_index_ = index;
    ResetMarquee(now_ms);
  }
  preview_frame_ = lyrics::LyricsFrame();
  preview_frame_.text = preview_lines_[index].first;
  preview_frame_.translation = preview_lines_[index].second;
  preview_frame_.next_text = preview_lines_[(index + 1) % count].first;
  preview_frame_.has_song = true;
  preview_frame_.is_playing = true;
  
  return preview_frame_;
}

bool FloatingLyricsWindow::BuildScene(lyrics::RenderScene* scene) {
  const long long now = lyrics::NowMilliseconds();
  const lyrics::LyricsFrame& current = EffectiveFrame(now);
  scene->style = style_;
  scene->frame = current;
  scene->highlight_progress = ComputeHighlightProgress(now);
  scene->word_segments = current.word_segments;
  scene->compact = false;
  scene->show_transport = style_.show_controls && current.has_song;
  scene->marquee_offset = ComputeMarqueeOffset(current.text, now);
  scene->transition_active = line_animator_.active();
  if (scene->transition_active) {
    scene->transition = line_animator_.Frame(now);
    scene->previous_text = line_animator_.previous_text();
    scene->previous_translation = line_animator_.previous_translation();
  }
  scene->window = window_animator_.Frame(now);
  scene->hovered_action = hovered_action();
  return true;
}

void FloatingLyricsWindow::OnFrameTick(long long now_ms) {
  EffectiveFrame(now_ms);

  if (line_animator_.active() && line_animator_.Progress(now_ms) >= 0.999) {
    line_animator_.Stop();
  }
  if (window_animator_.active()) {
    const double progress = window_animator_.Progress(now_ms);
    if (!window_animator_.showing() && progress <= 0.001) {
      window_animator_.Stop();
      LyricsWindowBase::Hide();
      return;
    }
    if (window_animator_.showing() && progress >= 0.999) {
      window_animator_.Stop();
    }
  }

  // hideInFullscreen: a game or a video player owns the screen, so the overlay
  // must get out of the way without being told by Dart.
  const bool watch_fullscreen = shown_ && style_.hide_in_fullscreen;
  if (watch_fullscreen) {
    UpdateFullscreenVisibility();
  }

  const bool line_running = line_animator_.active();
  const bool window_running = window_animator_.active();
  const bool sweeping = preview_until_ <= 0 && frame_.is_playing &&
                        frame_.highlight_rate > 0.0 &&
                        ComputeHighlightProgress(now_ms) < 1.0;
  const bool previewing = preview_until_ > 0;
  // A studio preview is transient. Once its window is over and no real song
  // owns the overlay, hide instead of leaving an empty controls-only strip on
  // the desktop.
  if (!previewing && frame_.text.empty() && shown_) {
    shown_ = false;
    LyricsWindowBase::Hide();
    StopTimer();
    return;
  }
  if (!line_running && !window_running && !marquee_active_ && !sweeping &&
      !previewing && !watch_fullscreen) {
    // Nothing moves until the next frame arrives: stop burning a timer here.
    if (visible()) {
      RenderNow();
    }
    StopTimer();
    return;
  }
  UINT interval = 500;
  if (line_running || window_running) {
    interval = 16;
  } else if (marquee_active_ || sweeping || previewing) {
    interval = 33;
  }
  StartTimer(interval);
}

void FloatingLyricsWindow::UpdateFullscreenVisibility() {
  if (hwnd() == nullptr || !shown_) {
    return;
  }
  const RECT monitor = ResolveMonitor().bounds;
  bool covers = false;
  const HWND foreground = GetForegroundWindow();
  if (foreground != nullptr && foreground != hwnd() &&
      IsWindowVisible(foreground) != FALSE) {
    RECT rect = {};
    if (GetWindowRect(foreground, &rect) != FALSE) {
      covers = rect.left <= monitor.left && rect.top <= monitor.top &&
               rect.right >= monitor.right && rect.bottom >= monitor.bottom;
    }
  }
  if (covers) {
    if (visible()) {
      LyricsWindowBase::Hide();
    }
    hidden_for_fullscreen_ = true;
    return;
  }
  if (hidden_for_fullscreen_) {
    hidden_for_fullscreen_ = false;
    ShowNoActivate();
  }
}

bool FloatingLyricsWindow::CanDragNow() const {
  return interactive_ && !style_.is_locked;
}

std::string FloatingLyricsWindow::HitTestAction(int x, int y) const {
  const lyrics::ControlLayout layout = lyrics::ComputeControlLayout(
      style_, std::max(1, width()), std::max(1, height()), dpi_scale(),
      frame_.has_song);
  const auto inside = [x, y](const RECT& rect) {
    return x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;
  };
  if (inside(layout.close_rect)) {
    return "close";
  }
  if (inside(layout.lock_rect)) {
    return "lock";
  }
  for (const auto& control : layout.transport) {
    if (inside(control.rect)) {
      return control.action;
    }
  }
  return std::string();
}

bool FloatingLyricsWindow::OnAction(const std::string& action, int x, int y) {
  (void)x;
  (void)y;
  if (action == "close") {
    Hide();
    Emit("closedByUser");
    return true;
  }
  if (action == "lock") {
    style_.is_locked = !style_.is_locked;
    is_locked_ = style_.is_locked;
    Emit("lockChanged",
         {{"value", lyrics::ArgumentValue::Boolean(style_.is_locked)}});
    RequestFrame();
    return true;
  }
  if (action == "playPause" || action == "previous" || action == "next") {
    Emit("controlRequested",
         {{"action", lyrics::ArgumentValue::Text(action)}});
    return true;
  }
  return false;
}

void FloatingLyricsWindow::OnDragFinished() {
  const RECT rect = bounds();
  const lyrics::MonitorInfo monitor = ResolveMonitor();
  const int monitor_width = monitor.bounds.right - monitor.bounds.left;
  const int monitor_height = monitor.bounds.bottom - monitor.bounds.top;
  const double x_ratio =
      monitor_width > 0
          ? static_cast<double>(rect.left - monitor.bounds.left) /
                static_cast<double>(monitor_width)
          : 0.0;
  const double y_ratio =
      monitor_height > 0
          ? static_cast<double>(rect.top - monitor.bounds.top) /
                static_cast<double>(monitor_height)
          : 0.0;
  style_.position_x = lyrics::Clamp01(x_ratio);
  style_.position_y_ratio = lyrics::Clamp01(y_ratio);
  style_.position_y = static_cast<double>(rect.top - monitor.bounds.top);
  Emit("moveEnded",
       {{"xRatio", lyrics::ArgumentValue::Number(style_.position_x)},
        {"yRatio", lyrics::ArgumentValue::Number(style_.position_y_ratio)},
        {"monitorDeviceName",
         lyrics::ArgumentValue::Text(lyrics::Utf8FromWide(monitor.device_name))}});
  Emit("positionChanged",
       {{"value", lyrics::ArgumentValue::Number(style_.position_y)}});
  RequestFrame();
}

void FloatingLyricsWindow::OnSizeSettled() {
  const double scale = dpi_scale();
  if (scale <= 0.0) {
    return;
  }
  style_.width = lyrics::ClampDouble(static_cast<double>(width()) / scale,
                                     kMinLogicalWidth, kMaxLogicalWidth);
  style_.height = lyrics::ClampDouble(static_cast<double>(height()) / scale,
                                      kMinLogicalHeight, kMaxLogicalHeight);
  Emit("windowResized",
       {{"width", lyrics::ArgumentValue::Number(style_.width)},
        {"height", lyrics::ArgumentValue::Number(style_.height)}});
}

void FloatingLyricsWindow::OnDpiChanged(UINT dpi, int width, int height) {
  (void)dpi;
  (void)width;
  (void)height;
  ApplyLayout();
  RequestFrame();
}

void FloatingLyricsWindow::EmitStyleChanged() {
  const unsigned long long argb =
      (static_cast<unsigned long long>(style_.highlight_color.a) << 24) |
      (static_cast<unsigned long long>(style_.highlight_color.r) << 16) |
      (static_cast<unsigned long long>(style_.highlight_color.g) << 8) |
      static_cast<unsigned long long>(style_.highlight_color.b);
  Emit("styleChanged",
       {{"highlightColor",
         lyrics::ArgumentValue::Number(static_cast<double>(argb))},
        {"fontSize", lyrics::ArgumentValue::Number(style_.font_size)}});
}

void FloatingLyricsWindow::CycleHighlightColor() {
  highlight_color_index_ = (highlight_color_index_ + 1) % kHighlightPaletteSize;
  style_.highlight_color = kHighlightPalette[highlight_color_index_];
  EmitStyleChanged();
  RequestFrame();
}

void FloatingLyricsWindow::AdjustFontSize(double delta) {
  style_.font_size = lyrics::ClampDouble(style_.font_size + delta, kMinFontSize,
                                         kMaxFontSize);
  EmitStyleChanged();
  ApplyLayout();
  RequestFrame();
}

bool FloatingLyricsWindow::OnWindowMessage(UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam,
                                           LRESULT* result) {
  (void)lparam;
  switch (message) {
    case WM_MOUSEWHEEL:
      if ((GET_KEYSTATE_WPARAM(wparam) & MK_CONTROL) != 0) {
        AdjustFontSize(GET_WHEEL_DELTA_WPARAM(wparam) > 0 ? 1.0 : -1.0);
        *result = 0;
        return true;
      }
      return false;
    case WM_RBUTTONUP:
      CycleHighlightColor();
      *result = 0;
      return true;
    case WM_LBUTTONDBLCLK:
      // Double click on the body toggles the lock, a habit carried over from
      // the previous overlay.
      style_.is_locked = !style_.is_locked;
      is_locked_ = style_.is_locked;
      Emit("lockChanged",
           {{"value", lyrics::ArgumentValue::Boolean(style_.is_locked)}});
      RequestFrame();
      *result = 0;
      return true;
    default:
      return false;
  }
}

