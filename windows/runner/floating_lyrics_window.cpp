#include "floating_lyrics_window.h"

#include <algorithm>

namespace {

constexpr const wchar_t kFloatingLyricsClassName[] =
    L"MCONNECT_FLOATING_LYRICS_WINDOW";
constexpr COLORREF kTransparentColor = RGB(1, 1, 1);

int ClampInt(int value, int min_value, int max_value) {
  return std::max(min_value, std::min(value, max_value));
}

HFONT CreateLyricsFont(int size, bool bold) {
  return CreateFontW(-size, 0, 0, 0, bold ? FW_SEMIBOLD : FW_NORMAL, FALSE,
                     FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                     CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                     DEFAULT_PITCH | FF_SWISS, L"Microsoft YaHei UI");
}

void RegisterFloatingLyricsWindowClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASSW window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kFloatingLyricsClassName;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hbrBackground = nullptr;
  window_class.lpfnWndProc = FloatingLyricsWindow::WndProc;
  RegisterClassW(&window_class);
  registered = true;
}

}  // namespace

FloatingLyricsWindow::FloatingLyricsWindow() = default;

FloatingLyricsWindow::~FloatingLyricsWindow() {
  if (window_ != nullptr) {
    DestroyWindow(window_);
    window_ = nullptr;
  }
}

bool FloatingLyricsWindow::Show(const std::wstring& text,
                                const std::wstring& translation,
                                int width,
                                int height,
                                int font_size,
                                COLORREF text_color) {
  if (!Update(text, translation, width, height, font_size, text_color)) {
    return false;
  }
  ShowWindow(window_, SW_SHOWNOACTIVATE);
  UpdateWindow(window_);
  return true;
}

bool FloatingLyricsWindow::Update(const std::wstring& text,
                                  const std::wstring& translation,
                                  int width,
                                  int height,
                                  int font_size,
                                  COLORREF text_color) {
  text_ = text;
  translation_ = translation;
  width_ = ClampInt(width, 220, 900);
  height_ = ClampInt(height, 72, 260);
  font_size_ = ClampInt(font_size, 14, 56);
  text_color_ = text_color;

  if (!EnsureWindow()) {
    return false;
  }
  ApplyBounds();
  InvalidateRect(window_, nullptr, TRUE);
  return true;
}

void FloatingLyricsWindow::Hide() {
  if (window_ != nullptr) {
    ShowWindow(window_, SW_HIDE);
  }
}

bool FloatingLyricsWindow::EnsureWindow() {
  if (window_ != nullptr) {
    return true;
  }

  RegisterFloatingLyricsWindowClass();
  window_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW,
      kFloatingLyricsClassName, L"Mconnect Floating Lyrics", WS_POPUP, 0, 0,
      width_, height_, nullptr, nullptr, GetModuleHandle(nullptr), this);
  if (window_ == nullptr) {
    return false;
  }

  SetLayeredWindowAttributes(window_, kTransparentColor, 255, LWA_COLORKEY);
  return true;
}

void FloatingLyricsWindow::ApplyBounds() {
  const int screen_width = GetSystemMetrics(SM_CXSCREEN);
  const int x = std::max(0, (screen_width - width_) / 2);
  const int y = 80;
  SetWindowPos(window_, HWND_TOPMOST, x, y, width_, height_,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void FloatingLyricsWindow::Paint() {
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(window_, &paint);
  RECT rect{};
  GetClientRect(window_, &rect);

  HBRUSH background = CreateSolidBrush(kTransparentColor);
  FillRect(dc, &rect, background);
  DeleteObject(background);

  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, text_color_);

  RECT text_rect = rect;
  text_rect.left += 18;
  text_rect.right -= 18;
  text_rect.top += 12;
  text_rect.bottom -= translation_.empty() ? 12 : (height_ / 3);

  HFONT lyric_font = CreateLyricsFont(font_size_, true);
  HFONT old_font = static_cast<HFONT>(SelectObject(dc, lyric_font));
  DrawTextW(dc, text_.c_str(), -1, &text_rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
  SelectObject(dc, old_font);
  DeleteObject(lyric_font);

  if (!translation_.empty()) {
    RECT translation_rect = rect;
    translation_rect.left += 18;
    translation_rect.right -= 18;
    translation_rect.top = text_rect.bottom - 2;
    translation_rect.bottom -= 10;
    SetTextColor(dc, RGB(220, 220, 220));
    HFONT translation_font =
        CreateLyricsFont(std::max(12, font_size_ - 6), false);
    old_font = static_cast<HFONT>(SelectObject(dc, translation_font));
    DrawTextW(dc, translation_.c_str(), -1, &translation_rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    SelectObject(dc, old_font);
    DeleteObject(translation_font);
  }

  EndPaint(window_, &paint);
}

LRESULT CALLBACK FloatingLyricsWindow::WndProc(HWND hwnd,
                                               UINT message,
                                               WPARAM wparam,
                                               LPARAM lparam) {
  FloatingLyricsWindow* that = nullptr;
  if (message == WM_NCCREATE) {
    auto create_struct = reinterpret_cast<CREATESTRUCTW*>(lparam);
    that = static_cast<FloatingLyricsWindow*>(create_struct->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(that));
  } else {
    that = reinterpret_cast<FloatingLyricsWindow*>(
        GetWindowLongPtr(hwnd, GWLP_USERDATA));
  }

  if (that != nullptr && message == WM_PAINT) {
    that->Paint();
    return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}
