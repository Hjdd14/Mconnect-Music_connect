#ifndef RUNNER_LYRICS_FLOATING_LYRICS_WINDOW_H_
#define RUNNER_LYRICS_FLOATING_LYRICS_WINDOW_H_

#include <windows.h>

#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "lyrics_animation.h"
#include "lyrics_types.h"
#include "lyrics_window_base.h"

// The desktop floating lyrics overlay.
//
// The class name and the Show/Update/Hide/SetEventCallback signatures are the
// contract the Dart side has used since the first Windows release, so they stay
// exactly as they are while everything behind them is the layered
// Direct2D/DirectWrite implementation. The protocol methods (Configure, Preview,
// ...) are additive.
class FloatingLyricsWindow : public lyrics::LyricsWindowBase {
 public:
  FloatingLyricsWindow();
  ~FloatingLyricsWindow() override;

  void SetEventCallback(std::function<void(const std::string&)> callback);

  bool Show(const std::wstring& text,
            const std::wstring& translation,
            int width,
            int height,
            int font_size,
            COLORREF text_color,
            bool locked,
            const std::wstring& next_text = L"",
            COLORREF highlight_color = RGB(255, 212, 74),
            double highlight_progress = 0.0);
  bool Update(const std::wstring& text,
              const std::wstring& translation,
              int width,
              int height,
              int font_size,
              COLORREF text_color,
              bool locked,
              const std::wstring& next_text = L"",
              COLORREF highlight_color = RGB(255, 212, 74),
              double highlight_progress = 0.0);
  void Hide();

  int GetWidth() const;
  int GetHeight() const;
  bool IsLocked() const;

  static LRESULT CALLBACK WndProc(HWND hwnd,
                                  UINT message,
                                  WPARAM wparam,
                                  LPARAM lparam);

  // Protocol surface (docs/desktop-lyrics-protocol.md 4.1).
  bool Configure(const lyrics::FloatingLyricsStyle& style);
  bool ShowFrame(const lyrics::LyricsFrame& frame);
  bool Preview(const std::string& animation,
               const std::vector<std::pair<std::wstring, std::wstring>>&
                   sample_lines,
               int duration_ms);
  void ResetPosition();
  void SetInteractive(bool interactive);

  const lyrics::FloatingLyricsStyle& style() const { return style_; }
  bool renderer_fallback() const;

 protected:
  bool BuildScene(lyrics::RenderScene* scene) override;
  void OnFrameTick(long long now_ms) override;
  bool CanDragNow() const override;
  std::string HitTestAction(int x, int y) const override;
  bool OnAction(const std::string& action, int x, int y) override;
  void OnDragFinished() override;
  void OnSizeSettled() override;
  void OnDpiChanged(UINT dpi, int width, int height) override;
  bool OnWindowMessage(UINT message,
                       WPARAM wparam,
                       LPARAM lparam,
                       LRESULT* result) override;
  void Emit(const std::string& name,
            const lyrics::EventArguments& args = {}) override;

 private:
  bool EnsureCreated();
  bool ApplyFrame(const lyrics::LyricsFrame& frame, bool show);
  void ApplyLayout();
  void UpdateClickThrough();
  void ResetMarquee(long long now_ms);
  double ComputeMarqueeOffset(const std::wstring& text, long long now_ms);
  double ComputeHighlightProgress(long long now_ms) const;
  lyrics::MonitorInfo ResolveMonitor() const;
  void UpdateFullscreenVisibility();
  void EmitStyleChanged();
  void CycleHighlightColor();
  void AdjustFontSize(double delta);
  const lyrics::LyricsFrame& EffectiveFrame(long long now_ms);

  lyrics::FloatingLyricsStyle style_;
  lyrics::LyricsFrame frame_;
  lyrics::LyricsFrame preview_frame_;
  lyrics::LineAnimator line_animator_;
  lyrics::WindowAnimator window_animator_;
  std::function<void(const std::string&)> legacy_event_callback_;
  std::vector<std::pair<std::wstring, std::wstring>> preview_lines_;
  std::string preview_animation_;
  long long preview_started_at_ = 0;
  long long preview_until_ = 0;
  std::size_t preview_index_ = 0;
  long long frame_received_at_ = 0;
  long long marquee_started_at_ = 0;
  bool marquee_active_ = false;
  bool ready_reported_ = false;
  bool shown_ = false;
  bool hidden_for_fullscreen_ = false;
  bool interactive_ = true;
  int highlight_color_index_ = 0;
};

#endif  // RUNNER_LYRICS_FLOATING_LYRICS_WINDOW_H_
