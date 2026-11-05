#include "lyrics_animation.h"

#include <windows.h>

#include <algorithm>
#include <cmath>

namespace lyrics {
namespace {

double ClampUnit(double value) {
  if (value < 0.0) {
    return 0.0;
  }
  if (value > 1.0) {
    return 1.0;
  }
  return value;
}

// easeOutBack: overshoots past 1 before settling, which is what the protocol's
// overshoot easing and the spring/drop transitions rely on.
double EaseOutBack(double progress) {
  constexpr double kC1 = 1.70158;
  constexpr double kC3 = kC1 + 1.0;
  const double shifted = progress - 1.0;
  return 1.0 + kC3 * shifted * shifted * shifted +
         kC1 * shifted * shifted;
}

double SmoothStep(double edge0, double edge1, double value) {
  if (edge1 <= edge0) {
    return value >= edge1 ? 1.0 : 0.0;
  }
  const double t = ClampUnit((value - edge0) / (edge1 - edge0));
  return t * t * (3.0 - 2.0 * t);
}

}  // namespace

long long NowMilliseconds() {
  return static_cast<long long>(GetTickCount64());
}

double ApplyEasing(Easing easing, double progress) {
  const double t = ClampUnit(progress);
  switch (easing) {
    case Easing::kLinear:
      return t;
    case Easing::kEaseOut: {
      const double inverse = 1.0 - t;
      return 1.0 - inverse * inverse * inverse;
    }
    case Easing::kEaseInOut:
      if (t < 0.5) {
        return 4.0 * t * t * t;
      } else {
        const double shifted = -2.0 * t + 2.0;
        return 1.0 - (shifted * shifted * shifted) / 2.0;
      }
    case Easing::kOvershoot:
      return EaseOutBack(t);
  }
  return t;
}

LineTransition ResolveRandomTransition(unsigned int seed) {
  // xorshift keeps the pick cheap and reproducible; the range covers the
  // concrete transitions only (kFade..kGlowSoft), never kNone or kRandom.
  unsigned int state = seed == 0u ? 0x9e3779b9u : seed;
  state ^= state << 13;
  state ^= state >> 17;
  state ^= state << 5;
  const int first = static_cast<int>(LineTransition::kFade);
  const int last = static_cast<int>(LineTransition::kGlowSoft);
  const int span = last - first + 1;
  return static_cast<LineTransition>(first + static_cast<int>(state % span));
}

LineTransitionFrame ComputeLineTransition(LineTransition transition,
                                           double progress) {
  LineTransitionFrame frame;
  const double t = ClampUnit(progress);
  const double remaining = 1.0 - t;

  switch (transition) {
    case LineTransition::kNone:
      frame.new_alpha = 1.0;
      frame.has_old = false;
      return frame;
    case LineTransition::kFade:
      frame.new_alpha = t;
      frame.has_old = true;
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kFadeThrough:
      // The outgoing line is gone before the incoming one appears, so the two
      // never blend into an unreadable smear.
      frame.new_alpha = SmoothStep(0.35, 1.0, t);
      frame.has_old = true;
      frame.old_alpha = 1.0 - ClampUnit(t / 0.35);
      return frame;
    case LineTransition::kSlideLeft:
      frame.new_dx = remaining;
      frame.new_alpha = std::min(1.0, t * 3.0);
      frame.has_old = true;
      frame.old_dx = -t;
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kSlideRight:
      frame.new_dx = -remaining;
      frame.new_alpha = std::min(1.0, t * 3.0);
      frame.has_old = true;
      frame.old_dx = t;
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kSlideUp:
      frame.new_dy = remaining;
      frame.new_alpha = std::min(1.0, t * 3.0);
      frame.has_old = true;
      frame.old_dy = -t;
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kSlideDown:
      frame.new_dy = -remaining;
      frame.new_alpha = std::min(1.0, t * 3.0);
      frame.has_old = true;
      frame.old_dy = t;
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kPushLeft:
      frame.new_dx = remaining;
      frame.has_old = true;
      frame.old_dx = -t;
      frame.old_alpha = 1.0;
      return frame;
    case LineTransition::kPushRight:
      frame.new_dx = -remaining;
      frame.has_old = true;
      frame.old_dx = t;
      frame.old_alpha = 1.0;
      return frame;
    case LineTransition::kScaleIn:
      frame.new_scale_x = 0.86 + 0.14 * t;
      frame.new_scale_y = frame.new_scale_x;
      frame.new_alpha = t;
      frame.has_old = true;
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kScaleOut:
      frame.new_scale_x = 1.14 - 0.14 * t;
      frame.new_scale_y = frame.new_scale_x;
      frame.new_alpha = std::min(1.0, t * 1.4);
      frame.has_old = true;
      frame.old_scale_x = 1.0 - 0.08 * t;
      frame.old_scale_y = frame.old_scale_x;
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kWipeLeft:
      frame.new_clip = t;
      frame.clip_from_left = true;
      frame.has_old = true;
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kWipeRight:
      frame.new_clip = t;
      frame.clip_from_left = false;
      frame.has_old = true;
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kFlipX:
      frame.new_scale_x = std::max(0.04, std::fabs(2.0 * t - 1.0));
      frame.new_alpha = t;
      frame.has_old = true;
      frame.old_scale_x = std::max(0.04, std::fabs(2.0 * t - 1.0));
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kFlipY:
      frame.new_scale_y = std::max(0.04, std::fabs(2.0 * t - 1.0));
      frame.new_alpha = t;
      frame.has_old = true;
      frame.old_scale_y = std::max(0.04, std::fabs(2.0 * t - 1.0));
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kDropBounce:
      frame.new_dy = -0.35 * remaining * remaining;
      frame.new_alpha = std::min(1.0, t * 4.0);
      frame.has_old = true;
      frame.old_alpha = 1.0 - std::min(1.0, t * 3.0);
      return frame;
    case LineTransition::kSpringUp:
      frame.new_dy = 0.30 * remaining * remaining;
      frame.new_scale_x = 0.94 + 0.06 * t;
      frame.new_scale_y = frame.new_scale_x;
      frame.new_alpha = std::min(1.0, t * 4.0);
      frame.has_old = true;
      frame.old_alpha = 1.0 - std::min(1.0, t * 3.0);
      return frame;
    case LineTransition::kGlowSoft:
      frame.new_scale_x = 1.0 + 0.03 * remaining;
      frame.new_scale_y = frame.new_scale_x;
      frame.new_alpha = t;
      frame.new_glow = true;
      frame.has_old = true;
      frame.old_alpha = remaining;
      return frame;
    case LineTransition::kRandom:
      // Resolved before the transition starts; a raw frame here must still
      // draw something readable.
      frame.new_alpha = t;
      frame.has_old = true;
      frame.old_alpha = remaining;
      return frame;
  }
  frame.new_alpha = 1.0;
  return frame;
}

WindowTransitionFrame ComputeWindowTransition(WindowTransition transition,
                                               double progress) {
  WindowTransitionFrame frame;
  const double t = ClampUnit(progress);
  const double remaining = 1.0 - t;
  switch (transition) {
    case WindowTransition::kNone:
      return frame;
    case WindowTransition::kFade:
      frame.alpha = t;
      return frame;
    case WindowTransition::kSlideFromTop:
      frame.dy = -remaining;
      frame.alpha = t;
      return frame;
    case WindowTransition::kSlideFromBottom:
      frame.dy = remaining;
      frame.alpha = t;
      return frame;
    case WindowTransition::kSlideFromLeft:
      frame.dx = -remaining;
      frame.alpha = t;
      return frame;
    case WindowTransition::kSlideFromRight:
      frame.dx = remaining;
      frame.alpha = t;
      return frame;
    case WindowTransition::kPop:
      frame.scale = 0.86 + 0.14 * t;
      frame.alpha = std::min(1.0, t * 1.6);
      return frame;
  }
  return frame;
}

void LineAnimator::Configure(LineTransition transition,
                             int duration_ms,
                             Easing easing,
                             bool reduce_motion) {
  transition_ = transition;
  resolved_ = transition == LineTransition::kRandom
                  ? ResolveRandomTransition(
                        static_cast<unsigned int>(NowMilliseconds()))
                  : transition;
  easing_ = easing;
  duration_ms_ = std::max(0, duration_ms);
  reduce_motion_ = reduce_motion;
}

void LineAnimator::Start(const std::wstring& previous_text,
                         const std::wstring& previous_translation,
                         long long now_ms) {
  previous_text_ = previous_text;
  previous_translation_ = previous_translation;
  start_ms_ = now_ms;
  // reduce_motion turns the transition into a hard cut: the user asked for no
  // movement, and a zero duration is the only duration that guarantees it.
  active_ = !reduce_motion_ && duration_ms_ > 0 &&
            resolved_ != LineTransition::kNone;
}

double LineAnimator::Progress(long long now_ms) const {
  if (!active_) {
    return 1.0;
  }
  const double elapsed = static_cast<double>(now_ms - start_ms_);
  return ClampUnit(elapsed / static_cast<double>(duration_ms_));
}

LineTransitionFrame LineAnimator::Frame(long long now_ms) const {
  if (!active_) {
    LineTransitionFrame frame;
    frame.new_alpha = 1.0;
    return frame;
  }
  return ComputeLineTransition(resolved_,
                               ApplyEasing(easing_, Progress(now_ms)));
}

void LineAnimator::Stop() {
  active_ = false;
  previous_text_.clear();
  previous_translation_.clear();
}

void WindowAnimator::Configure(WindowTransition transition,
                               int duration_ms,
                               Easing easing,
                               bool reduce_motion) {
  transition_ = transition;
  duration_ms_ = std::max(0, duration_ms);
  easing_ = easing;
  reduce_motion_ = reduce_motion;
}

void WindowAnimator::Start(bool showing, long long now_ms) {
  showing_ = showing;
  start_ms_ = now_ms;
  active_ = !reduce_motion_ && duration_ms_ > 0 &&
            transition_ != WindowTransition::kNone;
}

double WindowAnimator::Progress(long long now_ms) const {
  if (!active_) {
    return showing_ ? 1.0 : 0.0;
  }
  const double elapsed = static_cast<double>(now_ms - start_ms_);
  const double raw = ClampUnit(elapsed / static_cast<double>(duration_ms_));
  const double eased = ApplyEasing(easing_, showing_ ? raw : 1.0 - raw);
  // The hide direction must never overshoot: a frame drawn past 1 would paint
  // the window outside its own bitmap.
  return ClampUnit(eased);
}

WindowTransitionFrame WindowAnimator::Frame(long long now_ms) const {
  return ComputeWindowTransition(transition_, Progress(now_ms));
}

void WindowAnimator::Stop() { active_ = false; }

}  // namespace lyrics
