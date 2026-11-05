#ifndef RUNNER_LYRICS_LYRICS_ANIMATION_H_
#define RUNNER_LYRICS_LYRICS_ANIMATION_H_

#include <string>

#include "lyrics_types.h"

namespace lyrics {

// Eased progress in [0, 1] (overshoot may briefly exceed 1 before settling).
double ApplyEasing(Easing easing, double progress);

// What the renderer must do to the outgoing and incoming lyric line. Offsets
// are normalised against the text block, so the renderer decides how many
// pixels a full-width slide covers at the current size and DPI.
struct LineTransitionFrame {
  double new_alpha = 1.0;
  double new_dx = 0.0;
  double new_dy = 0.0;
  double new_scale_x = 1.0;
  double new_scale_y = 1.0;
  // 1 reveals the whole incoming line; lower values reveal it from the
  // clip_from_left edge (wipe transitions).
  double new_clip = 1.0;
  bool clip_from_left = true;
  bool new_glow = false;
  bool has_old = false;
  double old_alpha = 0.0;
  double old_dx = 0.0;
  double old_dy = 0.0;
  double old_scale_x = 1.0;
  double old_scale_y = 1.0;
};

// progress is the eased progress of the line change.
LineTransitionFrame ComputeLineTransition(LineTransition transition,
                                           double progress);

// Window entrance/exit. Offsets are fractions of the window size, scale is
// applied around the window centre.
struct WindowTransitionFrame {
  double alpha = 1.0;
  double dx = 0.0;
  double dy = 0.0;
  double scale = 1.0;
};

WindowTransitionFrame ComputeWindowTransition(WindowTransition transition,
                                               double progress);

// Turns the protocol's random into one concrete line transition. Stable for a
// given seed so a redraw of the same frame cannot pick a different animation.
LineTransition ResolveRandomTransition(unsigned int seed);

constexpr int kDefaultLineDurationMs = 220;
constexpr int kDefaultWindowDurationMs = 220;

// Wall clock in milliseconds; the animators take it as a parameter so they stay
// deterministic and free of Win32 calls.
long long NowMilliseconds();

class LineAnimator {
 public:
  void Configure(LineTransition transition,
                 int duration_ms,
                 Easing easing,
                 bool reduce_motion);
  // previous_text is what was on screen when the line changed; the transition
  // animates it out while the new frame animates in.
  void Start(const std::wstring& previous_text,
             const std::wstring& previous_translation,
             long long now_ms);
  bool active() const { return active_; }
  // Eased 0..1; 1 while inactive.
  double Progress(long long now_ms) const;
  LineTransitionFrame Frame(long long now_ms) const;
  void Stop();

  LineTransition transition() const { return transition_; }
  LineTransition resolved_transition() const { return resolved_; }
  int duration_ms() const { return duration_ms_; }
  const std::wstring& previous_text() const { return previous_text_; }
  const std::wstring& previous_translation() const {
    return previous_translation_;
  }

 private:
  LineTransition transition_ = LineTransition::kFade;
  LineTransition resolved_ = LineTransition::kFade;
  Easing easing_ = Easing::kEaseOut;
  int duration_ms_ = kDefaultLineDurationMs;
  bool reduce_motion_ = true;
  bool active_ = false;
  long long start_ms_ = 0;
  std::wstring previous_text_;
  std::wstring previous_translation_;
};

class WindowAnimator {
 public:
  void Configure(WindowTransition transition,
                 int duration_ms,
                 Easing easing,
                 bool reduce_motion);
  void Start(bool showing, long long now_ms);
  bool active() const { return active_; }
  bool showing() const { return showing_; }
  // 1 means fully shown; a hide animation walks this back to 0.
  double Progress(long long now_ms) const;
  WindowTransitionFrame Frame(long long now_ms) const;
  void Stop();

  WindowTransition transition() const { return transition_; }
  int duration_ms() const { return duration_ms_; }

 private:
  WindowTransition transition_ = WindowTransition::kFade;
  Easing easing_ = Easing::kEaseOut;
  int duration_ms_ = kDefaultWindowDurationMs;
  bool reduce_motion_ = true;
  bool active_ = false;
  bool showing_ = true;
  long long start_ms_ = 0;
};

}  // namespace lyrics

#endif  // RUNNER_LYRICS_LYRICS_ANIMATION_H_
