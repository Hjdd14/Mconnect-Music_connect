#include "taskbar_lyrics_window.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr const wchar_t kClassName[] = L"MCONNECT_TASKBAR_LYRICS_WINDOW";
// Posted by the WinEvent hook and by TaskbarCreated; WM_APP keeps it clear of
// every window message the runner already uses.
constexpr UINT kTaskbarChangedMessage = WM_APP + 1;
constexpr double kMarqueePauseMs = 600.0;
constexpr double kMarqueePixelsPerMs = 0.05;
constexpr long long kStatePollMs = 500;

HWND g_taskbar_window = nullptr;

void CALLBACK TaskbarEventProc(HWINEVENTHOOK hook,
                               DWORD event,
                               HWND hwnd,
                               LONG id_object,
                               LONG id_child,
                               DWORD event_thread,
                               DWORD event_time) {
  (void)hook;
  (void)event;
  (void)hwnd;
  (void)id_object;
  (void)id_child;
  (void)event_thread;
  (void)event_time;
  if (g_taskbar_window != nullptr) {
    PostMessageW(g_taskbar_window, kTaskbarChangedMessage, 0, 0);
  }
}

bool RectEquals(const RECT& left, const RECT& right) {
  return left.left == right.left && left.top == right.top &&
         left.right == right.right && left.bottom == right.bottom;
}

// The taskbar style has fewer knobs than the floating overlay; this is the one
// translation point into the shared renderer style.
lyrics::FloatingLyricsStyle ToRendererStyle(
    const lyrics::TaskbarLyricsStyle& style) {
  lyrics::FloatingLyricsStyle result;
  result.enabled = style.enabled;
  result.text_color = style.text_color;
  result.highlight_color = style.highlight_color;
  result.background_color = style.background_color;
  result.background_color2 = style.background_color;
  result.background_mode = style.background_mode;
  result.background_opacity = style.background_opacity;
  result.font_size = style.font_size;
  result.font_family = style.font_family;
  result.font_weight = style.font_weight;
  result.line_mode = style.line_mode;
  result.translation_layout = style.translation_layout;
  result.show_translation = lyrics::TranslationRule::kAuto;
  result.line_animation = style.line_animation;
  result.animation_duration_ms = style.animation_duration_ms;
  result.easing = style.easing;
  result.window_animation = style.window_animation;
  result.corner_radius = style.corner_radius;
  result.click_through = style.click_through;
  result.word_highlight = true;
  // A strip two pixels from the bar edge still needs room for the outline; the
  // shadow would smear over the taskbar buttons.
  result.stroke_width = 0.8;
  result.shadow_opacity = 0.0;
  result.padding = 3.0;
  result.show_controls = false;
  result.show_translation = lyrics::TranslationRule::kAuto;
  result.line_height = 1.05;
  result.reduce_motion = style.reduce_motion;
  return result;
}

bool ForegroundCoversMonitor(const RECT& monitor) {
  const HWND foreground = GetForegroundWindow();
  if (foreground == nullptr || IsWindowVisible(foreground) == FALSE) {
    return false;
  }
  RECT rect = {};
  if (GetWindowRect(foreground, &rect) == FALSE) {
    return false;
  }
  return rect.left <= monitor.left && rect.top <= monitor.top &&
         rect.right >= monitor.right && rect.bottom >= monitor.bottom;
}

}  // namespace

TaskbarLyricsWindow::TaskbarLyricsWindow() {
  draggable_ = true;
  resizable_ = false;
  line_animator_.Configure(lyrics::LineTransition::kSlideLeft, 200,
                           lyrics::Easing::kEaseOut, false);
  window_animator_.Configure(lyrics::WindowTransition::kFade, 200,
                             lyrics::Easing::kEaseOut, false);
}

TaskbarLyricsWindow::~TaskbarLyricsWindow() {
  RemoveTaskbarHooks();
  Destroy();
}

void TaskbarLyricsWindow::Emit(const std::string& name,
                               const lyrics::EventArguments& args) {
  LyricsWindowBase::Emit(name, args);
}

bool TaskbarLyricsWindow::renderer_fallback() const {
  return renderer()->kind() == lyrics::RendererKind::kGdiPlus;
}

bool TaskbarLyricsWindow::EnsureCreated() {
  if (hwnd() != nullptr) {
    return true;
  }
  if (!Create(kClassName, L"Mconnect Taskbar Lyrics", 200, 24)) {
    return false;
  }
  SetClickThrough(style_.click_through);
  InstallTaskbarHooks();
  AdoptTaskbarOwner();
  // The geometry math is pure, and a wrong answer here is invisible except as
  // "the sliders do nothing". Run the cases in Release too, once, and report a
  // failure to Dart so it can be seen in the lyrics studio instead of only in
  // a debugger.
  static bool self_test_ran = false;
  if (!self_test_ran) {
    self_test_ran = true;
    std::wstring failure;
    if (!lyrics::RunTaskbarGeometrySelfTest(&failure)) {
      const std::wstring message =
          L"mconnect: taskbar geometry self test failed: " + failure + L"\n";
      OutputDebugStringW(message.c_str());
      Emit("geometrySelfTestFailed",
           {{"reason",
             lyrics::ArgumentValue::Text(lyrics::Utf8FromWide(failure))}});
    }
  }
  return true;
}

void TaskbarLyricsWindow::InstallTaskbarHooks() {
  if (taskbar_created_message_ == 0) {
    // Explorer broadcasts this when it restarts, which invalidates every
    // rectangle we cached.
    taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  }
  if (event_hook_ == nullptr && hwnd() != nullptr) {
    g_taskbar_window = hwnd();
    const HWND taskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
    owner_taskbar_ = taskbar;
    DWORD process_id = 0;
    const DWORD thread_id = GetWindowThreadProcessId(taskbar, &process_id);
    // The shell resizes and moves the bar without telling anyone; its own
    // location events are the only reliable signal.
    event_hook_ = SetWinEventHook(EVENT_OBJECT_LOCATIONCHANGE,
                                  EVENT_OBJECT_LOCATIONCHANGE, nullptr,
                                  TaskbarEventProc, process_id, thread_id,
                                  WINEVENT_OUTOFCONTEXT);
  }
}

void TaskbarLyricsWindow::RemoveTaskbarHooks() {
  if (event_hook_ != nullptr) {
    UnhookWinEvent(event_hook_);
    event_hook_ = nullptr;
  }
  g_taskbar_window = nullptr;
}

HMONITOR TaskbarLyricsWindow::ResolveMonitorHandle() const {
  const std::wstring& name = style_.monitor_device_name;
  if (!name.empty() && name != L"primary") {
    std::vector<lyrics::MonitorInfo> monitors;
    lyrics::EnumerateMonitors(&monitors);
    for (const auto& monitor : monitors) {
      if (monitor.device_name == name) {
        RECT bounds = monitor.bounds;
        return MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST);
      }
    }
  }
  return MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
}

bool TaskbarLyricsWindow::TaskbarBandHidden() const {
  if (!style_.follow_auto_hide || !geometry_.auto_hide) {
    return false;
  }
  switch (geometry_.edge) {
    case lyrics::TaskbarEdge::kBottom:
      return geometry_.taskbar_rect.top >= geometry_.monitor.bottom;
    case lyrics::TaskbarEdge::kTop:
      return geometry_.taskbar_rect.bottom <= geometry_.monitor.top;
    case lyrics::TaskbarEdge::kLeft:
      return geometry_.taskbar_rect.right <= geometry_.monitor.left;
    case lyrics::TaskbarEdge::kRight:
      return geometry_.taskbar_rect.left >= geometry_.monitor.right;
  }
  return false;
}

bool TaskbarLyricsWindow::Configure(
    const lyrics::TaskbarLyricsStyle& style) {
  style_ = style;
  line_animator_.Configure(style.line_animation, style.animation_duration_ms,
                           style.easing, style.reduce_motion);
  window_animator_.Configure(style.window_animation,
                             style.animation_duration_ms, style.easing,
                             style.reduce_motion);
  if (!EnsureCreated()) {
    return false;
  }
  SetClickThrough(style_.click_through);
  RefreshGeometry();
  RequestFrame();
  return true;
}

bool TaskbarLyricsWindow::ShowFrame(const lyrics::LyricsFrame& frame) {
  if (frame.revision > 0 && frame_.revision > 0 &&
      frame.revision < frame_.revision) {
    return true;
  }
  return ApplyFrame(frame, true);
}

bool TaskbarLyricsWindow::ApplyFrame(const lyrics::LyricsFrame& frame,
                                     bool show) {
  const long long now = lyrics::NowMilliseconds();
  const bool text_changed = frame.text != frame_.text ||
                            frame.translation != frame_.translation;
  if (text_changed) {
    line_animator_.Start(frame_.text, frame_.translation, now);
    marquee_started_at_ = now;
  }
  frame_ = frame;
  frame_received_at_ = now;
  if (!EnsureCreated()) {
    return false;
  }
  if (show) {
    shown_ = true;
    closing_ = false;
  }
  RefreshGeometry();
  if (show) {
    const bool should_hide = !placement_valid_ ||
                             (style_.hide_in_fullscreen &&
                              ForegroundCoversMonitor(geometry_.monitor));
    if (should_hide) {
      hidden_for_state_ = true;
      if (visible()) {
        LyricsWindowBase::Hide();
      }
    } else {
      hidden_for_state_ = false;
      // The entrance plays once per show: a frame that arrives while the strip
      // is already on screen must not restart the fade on every tick.
      if (!visible()) {
        window_animator_.Start(true, now);
      }
      ShowNoActivate();
    }
  }
  RequestFrame();
  return true;
}

void TaskbarLyricsWindow::Hide() {
  shown_ = false;
  hidden_for_state_ = false;
  if (!visible()) {
    closing_ = false;
    window_animator_.Stop();
    LyricsWindowBase::Hide();
    return;
  }
  const long long now = lyrics::NowMilliseconds();
  window_animator_.Start(false, now);
  if (!window_animator_.active()) {
    // Reduce motion (or a zero duration) already resolved to "gone".
    closing_ = false;
    LyricsWindowBase::Hide();
    return;
  }
  // The exit plays on the frame timer; OnFrameTick finishes it with the real
  // LyricsWindowBase::Hide() so the fade-out is seen instead of cut off.
  closing_ = true;
  RequestFrame();
}

bool TaskbarLyricsWindow::Preview(
    const std::string& animation,
    const std::vector<std::pair<std::wstring, std::wstring>>& sample_lines,
    int duration_ms) {
  if (sample_lines.empty()) {
    return false;
  }
  if (!EnsureCreated()) {
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
  shown_ = true;
  closing_ = false;
  RefreshGeometry();
  if (placement_valid_) {
    ShowNoActivate();
  }
  RequestFrame();
  return true;
}

bool TaskbarLyricsWindow::RefreshGeometry() {
  if (hwnd() == nullptr) {
    return false;
  }
  const HMONITOR monitor = ResolveMonitorHandle();
  lyrics::TaskbarGeometry next;
  if (!lyrics::ProbeTaskbar(monitor, &next)) {
    MONITORINFO info = {};
    info.cbSize = sizeof(MONITORINFO);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info) != FALSE) {
      next.monitor = info.rcMonitor;
      next.taskbar_rect = RECT{info.rcMonitor.left, info.rcMonitor.bottom,
                               info.rcMonitor.right, info.rcMonitor.bottom};
      next.free_rect = info.rcMonitor;
      next.edge = lyrics::TaskbarEdge::kBottom;
      next.thickness = 0;
      next.found = false;
      next.dpi = dpi();
    }
  }

  const bool changed = !RectEquals(last_free_rect_, next.free_rect) ||
                       !RectEquals(last_taskbar_rect_, next.taskbar_rect) ||
                       geometry_.found != next.found ||
                       geometry_.auto_hide != next.auto_hide ||
                       geometry_.edge != next.edge;
  geometry_ = next;
  ApplyPlacement();
  const RECT placement = bounds();
  const bool moved = !RectEquals(last_placement_, placement);
  last_placement_ = placement;
  last_free_rect_ = next.free_rect;
  last_taskbar_rect_ = next.taskbar_rect;

  if (changed || moved || !state_reported_) {
    state_reported_ = true;
    Emit("geometryChanged");
    Emit("taskbarStateChanged",
         {{"autoHide",
           lyrics::ArgumentValue::Boolean(geometry_.auto_hide)},
          {"edge", lyrics::ArgumentValue::Text(
                       lyrics::TaskbarEdgeName(geometry_.edge))},
          {"spaceInsufficient",
           lyrics::ArgumentValue::Boolean(space_insufficient_)}});
  }
  return geometry_.found;
}

void TaskbarLyricsWindow::AdoptTaskbarOwner() {
  if (hwnd() == nullptr) {
    return;
  }
  HWND taskbar = owner_taskbar_;
  if (taskbar == nullptr || IsWindow(taskbar) == FALSE) {
    taskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
  }
  if (taskbar == nullptr) {
    return;
  }
  owner_taskbar_ = taskbar;
  // The taskbar and this strip are both topmost, so plain z-order is decided
  // by whoever raised itself last -- and Explorer raises Shell_TrayWnd on its
  // own schedule, which is what painted over the strip. An *owned* window is
  // kept above its owner by Windows itself, so the strip stays visible without
  // a per-frame race.
  SetWindowLongPtrW(hwnd(), GWLP_HWNDPARENT,
                    reinterpret_cast<LONG_PTR>(taskbar));
}

void TaskbarLyricsWindow::EmitPlacement(const RECT& rect, bool visible) {
  if (placement_emitted_ && visible &&
      rect.left == last_emitted_placement_.left &&
      rect.top == last_emitted_placement_.top &&
      rect.right == last_emitted_placement_.right &&
      rect.bottom == last_emitted_placement_.bottom) {
    return;
  }
  placement_emitted_ = true;
  last_emitted_placement_ = visible ? rect : RECT{};
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  Emit("taskbarPlacement",
       {{"left", lyrics::ArgumentValue::Number(rect.left)},
        {"top", lyrics::ArgumentValue::Number(rect.top)},
        {"width", lyrics::ArgumentValue::Number(width)},
        {"height", lyrics::ArgumentValue::Number(height)},
        {"visible", lyrics::ArgumentValue::Boolean(visible)}});
}

void TaskbarLyricsWindow::OnDragFinished() {
  if (hwnd() == nullptr) {
    return;
  }
  const RECT rect = bounds();
  const RECT band = geometry_.free_rect;
  const bool vertical = geometry_.edge == lyrics::TaskbarEdge::kLeft ||
                        geometry_.edge == lyrics::TaskbarEdge::kRight;
  const double scale = dpi_scale() > 0.0 ? dpi_scale() : 1.0;
  // A drag may go anywhere; the strip still belongs to the taskbar, so the
  // new position is stored as an offset inside the free band (horizontal bars
  // slide along x, vertical bars along y).
  double offset = vertical ? (rect.top - band.top) / scale
                           : (rect.left - band.left) / scale;
  if (offset < -4000.0) offset = -4000.0;
  if (offset > 4000.0) offset = 4000.0;
  // Keep the local style in sync before the Dart round trip, otherwise the
  // next frame would re-place the strip at the old offset and visibly snap it
  // back under the cursor.
  style_.offset_x = offset;
  Emit("dragOffset",
       {{"offsetX", lyrics::ArgumentValue::Number(offset)},
        {"width", lyrics::ArgumentValue::Number((rect.right - rect.left) / scale)},
        {"height",
         lyrics::ArgumentValue::Number((rect.bottom - rect.top) / scale)}});
  RefreshGeometry();
}
void TaskbarLyricsWindow::ApplyPlacement() {
  if (dragging_ || resizing_) return;
  if (hwnd() == nullptr) {
    return;
  }
  const double scale = dpi_scale();
  const int requested_height =
      style_.height > 0.0
          ? static_cast<int>(std::lround(style_.height * scale))
          : 0;
  const lyrics::TaskbarLyricsPlacement placement =
      lyrics::PlaceTaskbarLyrics(geometry_, style_, scale, requested_height);
  space_insufficient_ = placement.space_insufficient;
  const RECT rect = placement.rect;
  // No taskbar, or a rectangle too small to draw in: hide. Keeping the window
  // where Create() left it (top-left, 200x24) is what made a missing taskbar
  // look like a stray strip on the desktop.
  if (!placement.visible || rect.right - rect.left < 8 ||
      rect.bottom - rect.top < 8) {
    placement_valid_ = false;
    last_placement_ = RECT{};
    EmitPlacement(RECT{}, false);
    if (visible()) {
      LyricsWindowBase::Hide();
    }
    return;
  }
  placement_valid_ = true;
  SetBounds(rect.left, rect.top, rect.right - rect.left,
            rect.bottom - rect.top, visible());
  // Second line of defence after the owner relationship: re-assert topmost on
  // every placement, because a shell restart or a theme change can reshuffle
  // the topmost band while the strip sits still.
  SetWindowPos(hwnd(), HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  EmitPlacement(rect, true);
}

void TaskbarLyricsWindow::UpdateVisibilityForState() {
  if (!shown_ || closing_ || hwnd() == nullptr) {
    return;
  }
  const bool fullscreen = style_.hide_in_fullscreen &&
                          ForegroundCoversMonitor(geometry_.monitor);
  // Without a taskbar rectangle there is nothing to show: showing the window
  // anyway would park it at its create-time position.
  const bool should_hide =
      fullscreen || TaskbarBandHidden() || !placement_valid_;
  if (should_hide) {
    if (visible()) {
      LyricsWindowBase::Hide();
    }
    hidden_for_state_ = true;
    return;
  }
  if (hidden_for_state_ || !visible()) {
    hidden_for_state_ = false;
    ShowNoActivate();
  }
}

std::vector<lyrics::TaskbarGeometry> TaskbarLyricsWindow::TaskbarInfo() {
  return lyrics::ProbeAllTaskbars();
}

double TaskbarLyricsWindow::ComputeMarqueeOffset(const std::wstring& text,
                                                 long long now_ms) {
  const double scale = dpi_scale();
  const lyrics::FloatingLyricsStyle renderer_style = ToRendererStyle(style_);
  const int window_width = std::max(1, width());
  const double area_width = static_cast<double>(window_width) - 8.0;
  const double font_size = std::max(9.0, style_.font_size * scale);
  const double text_width = renderer()->MeasureLineWidth(
      renderer_style, text, font_size, 0.0);
  marquee_active_ =
      style_.marquee && area_width > 1.0 && text_width > area_width + 1.0;
  if (!marquee_active_) {
    return 0.0;
  }
  const double elapsed = static_cast<double>(now_ms - marquee_started_at_);
  if (elapsed <= kMarqueePauseMs) {
    return 0.0;
  }
  const double distance = text_width + area_width + 32.0 * scale;
  const double travelled =
      (elapsed - kMarqueePauseMs) * kMarqueePixelsPerMs * scale;
  return std::fmod(travelled, distance);
}

const lyrics::LyricsFrame& TaskbarLyricsWindow::EffectiveFrame(
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
  const long long step =
      std::max<long long>(1, total / static_cast<long long>(count));
  const std::size_t raw = static_cast<std::size_t>(
      std::max<long long>(0, (now_ms - preview_started_at_) / step));
  const std::size_t index = std::min(count - 1, raw);
  if (index != preview_index_) {
    line_animator_.Start(preview_lines_[preview_index_].first,
                         preview_lines_[preview_index_].second, now_ms);
    preview_index_ = index;
    marquee_started_at_ = now_ms;
  }
  preview_frame_ = lyrics::LyricsFrame();
  preview_frame_.text = preview_lines_[index].first;
  preview_frame_.translation = preview_lines_[index].second;
  preview_frame_.next_text = preview_lines_[(index + 1) % count].first;
  preview_frame_.has_song = true;
  preview_frame_.is_playing = true;
  return preview_frame_;
}

bool TaskbarLyricsWindow::BuildScene(lyrics::RenderScene* scene) {
  const long long now = lyrics::NowMilliseconds();
  const lyrics::LyricsFrame& current = EffectiveFrame(now);
  const double scale = dpi_scale() > 0.0 ? dpi_scale() : 1.0;
  lyrics::FloatingLyricsStyle renderer_style = ToRendererStyle(style_);
  renderer_style.width = static_cast<double>(width()) / scale;
  renderer_style.height = static_cast<double>(height()) / scale;
  if (style_.debug_geometry) {
    // "Debug geometry" is the switch a user flips when the strip seems to be
    // missing: give the window an unmistakable tint so its real rectangle is
    // visible without a debugger attached.
    renderer_style.background_mode = lyrics::BackgroundMode::kSolid;
    renderer_style.background_opacity = 0.30;
    renderer_style.corner_radius = 0.0;
  }
  scene->style = renderer_style;
  scene->frame = current;
  double progress = current.highlight_progress;
  if (preview_until_ <= 0 && current.is_playing &&
      current.highlight_rate > 0.0 && frame_received_at_ > 0) {
    progress += current.highlight_rate *
                static_cast<double>(now - frame_received_at_);
  }
  scene->highlight_progress = lyrics::Clamp01(progress);
  scene->word_segments = current.word_segments;
  scene->compact = true;
  scene->show_transport = false;
  scene->marquee_offset = ComputeMarqueeOffset(current.text, now);
  scene->transition_active = line_animator_.active();
  if (scene->transition_active) {
    scene->transition = line_animator_.Frame(now);
    scene->previous_text = line_animator_.previous_text();
    scene->previous_translation = line_animator_.previous_translation();
  }
  scene->window = window_animator_.Frame(now);
  return true;
}

void TaskbarLyricsWindow::OnFrameTick(long long now_ms) {
  EffectiveFrame(now_ms);
  if (line_animator_.active() && line_animator_.Progress(now_ms) >= 0.999) {
    line_animator_.Stop();
  }
  if (window_animator_.active()) {
    const double progress = window_animator_.Progress(now_ms);
    if (!window_animator_.showing() && progress <= 0.001) {
      // The exit finished: only now does the window disappear, so the fade-out
      // is actually seen instead of being cut off at its first frame.
      window_animator_.Stop();
      closing_ = false;
      shown_ = false;
      LyricsWindowBase::Hide();
      StopTimer();
      return;
    }
    if (window_animator_.showing() && progress >= 0.999) {
      window_animator_.Stop();
    }
  }

  if (preview_until_ <= 0 && frame_.text.empty() && shown_) {
    Hide();
    // Hide() may have started the exit animation; that keeps the timer alive.
    if (!closing_) {
      StopTimer();
      return;
    }
  }

  // A closing strip is already "not shown" but still animating, so the early
  // return waits for both flags to say there is nothing left to draw.
  if (!shown_ && !closing_) {
    StopTimer();
    return;
  }

  // Auto-hide taskbars and fullscreen windows change without a message we can
  // rely on, so poll on a slow tick; the fast animation ticks skip the probe.
  if (shown_ && now_ms - last_poll_ms_ >= kStatePollMs) {
    last_poll_ms_ = now_ms;
    UpdateVisibilityForState();
    if (shown_ && !closing_) {
      RefreshGeometry();
      UpdateVisibilityForState();
    }
  }
  const bool line_running = line_animator_.active();
  const bool window_running = window_animator_.active();
  const bool sweeping = preview_until_ <= 0 && frame_.is_playing &&
                        frame_.highlight_rate > 0.0;
  const bool previewing = preview_until_ > 0;
  UINT interval = static_cast<UINT>(kStatePollMs);
  if (line_running || window_running) {
    interval = 16;
  } else if (marquee_active_ || sweeping || previewing) {
    interval = 33;
  }
  StartTimer(interval);
}

void TaskbarLyricsWindow::OnSystemChange(UINT message) {
  switch (message) {
    case WM_SETTINGCHANGE:
    case WM_DISPLAYCHANGE:
    case WM_THEMECHANGED:
      // DPI, taskbar position, auto-hide and monitor layout all land here.
      RefreshGeometry();
      UpdateVisibilityForState();
      RequestFrame();
      break;
    default:
      break;
  }
}

std::string TaskbarLyricsWindow::HitTestAction(int x, int y) const {
  (void)x;
  (void)y;
  // The strip is click-through by default and has no controls of its own.
  return std::string();
}

bool TaskbarLyricsWindow::OnWindowMessage(UINT message,
                                          WPARAM wparam,
                                          LPARAM lparam,
                                          LRESULT* result) {
  (void)wparam;
  (void)lparam;
  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    // Explorer restarted: the bar handle and every rectangle are new.
    RemoveTaskbarHooks();
    InstallTaskbarHooks();
    RefreshGeometry();
    RequestFrame();
    *result = 0;
    return true;
  }
  if (message == kTaskbarChangedMessage) {
    RefreshGeometry();
    UpdateVisibilityForState();
    RequestFrame();
    *result = 0;
    return true;
  }
  return false;
}

