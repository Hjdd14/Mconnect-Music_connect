#ifndef RUNNER_FLOATING_LYRICS_WINDOW_H_
#define RUNNER_FLOATING_LYRICS_WINDOW_H_

#include <windows.h>

#include <string>

class FloatingLyricsWindow {
 public:
  FloatingLyricsWindow();
  ~FloatingLyricsWindow();

  bool Show(const std::wstring& text,
            const std::wstring& translation,
            int width,
            int height,
            int font_size,
            COLORREF text_color);
  bool Update(const std::wstring& text,
              const std::wstring& translation,
              int width,
              int height,
              int font_size,
              COLORREF text_color);
  void Hide();

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

  bool EnsureWindow();
  void ApplyBounds();
  void Paint();
};

#endif  // RUNNER_FLOATING_LYRICS_WINDOW_H_
