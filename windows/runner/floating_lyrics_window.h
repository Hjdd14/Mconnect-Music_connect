#ifndef RUNNER_FLOATING_LYRICS_WINDOW_H_
#define RUNNER_FLOATING_LYRICS_WINDOW_H_

#include <windows.h>

#include <functional>
#include <string>

class FloatingLyricsWindow {
 public:
  FloatingLyricsWindow();
  ~FloatingLyricsWindow();

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

  int GetWidth() const { return width_; }
  int GetHeight() const { return height_; }
  bool IsLocked() const { return is_locked_; }

  static LRESULT CALLBACK WndProc(HWND hwnd,
                                  UINT message,
                                  WPARAM wparam,
                                  LPARAM lparam);

 private:
  HWND window_ = nullptr;
  std::wstring text_;
  std::wstring translation_;
  // Upcoming lyric line, drawn under the pair as a dimmed preview. Empty when
  // the current line is the last visible one.
  std::wstring next_text_;
  int width_ = 420;
  int height_ = 112;
  int font_size_ = 24;
  COLORREF text_color_ = RGB(255, 255, 255);
  // Colour of the already-sung prefix of `text_`, mirroring the Android
  // overlay's `highlightColor` setting.
  COLORREF highlight_color_ = RGB(255, 212, 74);
  // Fraction (0..1) of `text_` playback has reached; drives the swept prefix.
  double highlight_progress_ = 0.0;
  bool is_locked_ = false;
  bool close_hovered_ = false;
  bool lock_hovered_ = false;
  bool resize_hovered_ = false;
  bool is_dragging_ = false;
  bool is_resizing_ = false;
  POINT drag_start_{};
  RECT drag_origin_{};
  DWORD marquee_started_at_ = 0;
  UINT_PTR marquee_timer_id_ = 0;
  std::function<void(const std::string&)> event_callback_;

  static constexpr UINT_PTR kMarqueeTimerId = 1;
  static constexpr UINT kMarqueeTimerMs = 33;
  static constexpr int kControlSize = 24;
  static constexpr int kControlMargin = 6;
  static constexpr int kControlGap = 4;
  static constexpr int kResizeHandleSize = 24;
  static constexpr int kMinWidth = 220;
  static constexpr int kMinHeight = 72;
  static constexpr int kMaxWidth = 900;
  static constexpr int kMaxHeight = 260;

  bool EnsureWindow();
  void ApplyBounds(bool preserve_position);
  void Paint(HDC dc);
  void StartMarqueeTimer();
  void StopMarqueeTimer();
  void ResetMarquee();
  void ToggleLock();
  void FinishResize();
  void SendEvent(const std::string& event);

  /// Vertical bands for the three lyric rows: the active line, its translation
  /// and the dimmed next line. A band is zero-height when its text is absent, so
  /// the active line never gives up room it does not have to.
  void ComputeTextRects(RECT* main_rect,
                        RECT* translation_rect,
                        RECT* next_rect) const;
  RECT GetLockButtonRect() const;
  RECT GetCloseButtonRect() const;
  RECT GetResizeHandleRect() const;
  bool IsInLockButton(int x, int y) const;
  bool IsInCloseButton(int x, int y) const;
  bool IsInResizeHandle(int x, int y) const;
  bool IsMarqueeNeeded(HDC dc) const;
  void RefreshMarqueeTimer();
  int MarqueeOffset(int text_width, int rect_width) const;
  /// Draws [text] with a black outline, optionally re-painting the first
  /// [highlight_characters] glyphs in [highlight_color].
  void DrawOutlinedText(HDC dc,
                        const std::wstring& text,
                        RECT rect,
                        int font_size,
                        bool bold,
                        COLORREF color,
                        bool marquee,
                        COLORREF highlight_color = CLR_INVALID,
                        int highlight_characters = 0);
  void DrawControls(HDC dc);
  void UpdateHoverState(int x, int y);
};

#endif  // RUNNER_FLOATING_LYRICS_WINDOW_H_
