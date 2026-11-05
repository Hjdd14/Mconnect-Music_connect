#ifndef RUNNER_LYRICS_TASKBAR_LYRICS_WINDOW_H_
#define RUNNER_LYRICS_TASKBAR_LYRICS_WINDOW_H_

#include <windows.h>

#include <string>
#include <utility>
#include <vector>

#include "lyrics_animation.h"
#include "lyrics_types.h"
#include "lyrics_window_base.h"
#include "taskbar_geometry.h"

// The taskbar lyrics strip: a click-through layered window parked inside the
// free band of the real Windows taskbar (between the task list and the
// notification area), with a fallback strip just above the bar when the band is
// too narrow.
class TaskbarLyricsWindow : public lyrics::LyricsWindowBase {
 public:
  TaskbarLyricsWindow();
  ~TaskbarLyricsWindow() override;

  bool Configure(const lyrics::TaskbarLyricsStyle& style);
  bool ShowFrame(const lyrics::LyricsFrame& frame);
  void Hide();
  bool Preview(const std::string& animation,
               const std::vector<std::pair<std::wstring, std::wstring>>&
                   sample_lines,
               int duration_ms);

  // Re-probes the shell taskbar and re-places the strip. Called on
  // TaskbarCreated, WM_SETTINGCHANGE, WM_DISPLAYCHANGE and the WinEvent hook.
  bool RefreshGeometry();
  std::vector<lyrics::TaskbarGeometry> TaskbarInfo();

  const lyrics::TaskbarLyricsStyle& style() const { return style_; }
  const lyrics::TaskbarGeometry& geometry() const { return geometry_; }
  bool renderer_fallback() const;

 protected:
  bool BuildScene(lyrics::RenderScene* scene) override;
  void OnFrameTick(long long now_ms) override;
  void OnSystemChange(UINT message) override;
  // The strip lives inside the taskbar, so a drag slides it *along* the bar
  // (OnDragFinished turns the new rectangle into an offsetX the settings keep).
  // Click-through wins: a strip the user cannot click must not steal taskbar
  // drags either.
  bool CanDragNow() const override { return !style_.click_through; }
  bool CanResizeNow() const override { return false; }
  void OnDragFinished() override;
  std::string HitTestAction(int x, int y) const override;
  bool OnWindowMessage(UINT message,
                       WPARAM wparam,
                       LPARAM lparam,
                       LRESULT* result) override;
  void Emit(const std::string& name,
            const lyrics::EventArguments& args = {}) override;

 private:
  bool EnsureCreated();
  void InstallTaskbarHooks();
  // Owns the strip to the shell taskbar: an owned window is always painted
  // above its owner, which is the only reliable way to stay visible on top of
  // Shell_TrayWnd (both are topmost and Explorer re-raises its own window).
  void AdoptTaskbarOwner();
  // Reports the live rectangle so the studio can show numbers that move with
  // the sliders instead of leaving the user to guess whether anything happened.
  void EmitPlacement(const RECT& rect, bool visible);
  void RemoveTaskbarHooks();
  bool ApplyFrame(const lyrics::LyricsFrame& frame, bool show);
  void ApplyPlacement();
  void UpdateVisibilityForState();
  double ComputeMarqueeOffset(const std::wstring& text, long long now_ms);
  const lyrics::LyricsFrame& EffectiveFrame(long long now_ms);
  HMONITOR ResolveMonitorHandle() const;
  bool TaskbarBandHidden() const;

  lyrics::TaskbarLyricsStyle style_;
  lyrics::TaskbarGeometry geometry_;
  lyrics::LyricsFrame frame_;
  lyrics::LyricsFrame preview_frame_;
  lyrics::LineAnimator line_animator_;
  lyrics::WindowAnimator window_animator_;
  HWINEVENTHOOK event_hook_ = nullptr;
  UINT taskbar_created_message_ = 0;
  std::vector<std::pair<std::wstring, std::wstring>> preview_lines_;
  std::string preview_animation_;
  long long preview_started_at_ = 0;
  long long preview_until_ = 0;
  std::size_t preview_index_ = 0;
  long long frame_received_at_ = 0;
  long long marquee_started_at_ = 0;
  bool marquee_active_ = false;
  bool hidden_for_state_ = false;
  bool state_reported_ = false;
  bool space_insufficient_ = false;
  bool shown_ = false;
  // True while the exit animation is playing: the strip is already "not shown"
  // but still on screen, and its tick must keep running until the fade ends.
  bool closing_ = false;
  // False when there is no taskbar (or no rectangle big enough to draw in). The
  // window then stays hidden instead of keeping its create-time geometry.
  bool placement_valid_ = false;
  long long last_poll_ms_ = 0;
  RECT last_placement_ = {};
  RECT last_free_rect_ = {};
  RECT last_taskbar_rect_ = {};
  RECT last_emitted_placement_ = {};
  bool placement_emitted_ = false;
  HWND owner_taskbar_ = nullptr;
};

#endif  // RUNNER_LYRICS_TASKBAR_LYRICS_WINDOW_H_
