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
            bool locked);
  bool Update(const std::wstring& text,
              const std::wstring& translation,
              int width,
              int height,
              int font_size,
              COLORREF text_color,
              bool locked);
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
  int width_ = 420;
  int height_ = 112;
  int font_size_ = 24;
  COLORREF text_color_ = RGB(255, 255, 255);
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

  RECT GetTextRect(bool has_translation) const;
  RECT GetTranslationRect() const;
  RECT GetLockButtonRect() const;
  RECT GetCloseButtonRect() const;
  RECT GetResizeHandleRect() const;
  bool IsInLockButton(int x, int y) const;
  bool IsInCloseButton(int x, int y) const;
  bool IsInResizeHandle(int x, int y) const;
  bool IsMarqueeNeeded(HDC dc) const;
  void RefreshMarqueeTimer();
  int MarqueeOffset(int text_width, int rect_width) const;
  void DrawOutlinedText(HDC dc,
                        const std::wstring& text,
                        RECT rect,
                        int font_size,
                        bool bold,
                        COLORREF color,
                        bool marquee);
  void DrawControls(HDC dc);
  void UpdateHoverState(int x, int y);
};

#endif  // RUNNER_FLOATING_LYRICS_WINDOW_H_
