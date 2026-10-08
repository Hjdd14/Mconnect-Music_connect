#include "floating_lyrics_window.h"

#include <windowsx.h>

#include <algorithm>

namespace {

constexpr const wchar_t kClassName[] = L"MCONNECT_FLOATING_LYRICS_WINDOW";
constexpr COLORREF kTransparentColor = RGB(1, 1, 1);

int ClampInt(int value, int min_value, int max_value) {
  return std::max(min_value, std::min(value, max_value));
}

double ClampProgress(double value) {
  if (value < 0.0) {
    return 0.0;
  }
  if (value > 1.0) {
    return 1.0;
  }
  return value;
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
  window_class.lpszClassName = kClassName;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hbrBackground = CreateSolidBrush(kTransparentColor);
  window_class.lpfnWndProc = FloatingLyricsWindow::WndProc;
  RegisterClassW(&window_class);
  registered = true;
}

int TextWidth(HDC dc, const std::wstring& text) {
  if (text.empty()) {
    return 0;
  }
  SIZE size{};
  GetTextExtentPoint32W(dc, text.c_str(), static_cast<int>(text.size()),
                        &size);
  return size.cx;
}

/// Scales [color] toward black. The overlay is transparent, so "dimmer" has to
/// be expressed by the glyph colour itself (the outline keeps it legible).
COLORREF DimColor(COLORREF color, double factor) {
  const auto scale = [factor](BYTE channel) {
    return static_cast<BYTE>(channel * factor);
  };
  return RGB(scale(GetRValue(color)), scale(GetGValue(color)),
             scale(GetBValue(color)));
}

void PaintOutlinedGlyphRun(HDC dc,
                           const std::wstring& text,
                           int x,
                           int y,
                           COLORREF text_color) {
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(0, 0, 0));
  static constexpr POINT offsets[] = {
      {-1, -1}, {0, -1}, {1, -1}, {-1, 0},
      {1, 0},   {-1, 1}, {0, 1},  {1, 1},
  };
  for (const auto& offset : offsets) {
    TextOutW(dc, x + offset.x, y + offset.y, text.c_str(),
             static_cast<int>(text.size()));
  }

  SetTextColor(dc, text_color);
  TextOutW(dc, x, y, text.c_str(), static_cast<int>(text.size()));
}

}  // namespace

FloatingLyricsWindow::FloatingLyricsWindow() = default;

FloatingLyricsWindow::~FloatingLyricsWindow() {
  StopMarqueeTimer();
  if (window_ != nullptr) {
    DestroyWindow(window_);
    window_ = nullptr;
  }
}

void FloatingLyricsWindow::SetEventCallback(
    std::function<void(const std::string&)> callback) {
  event_callback_ = std::move(callback);
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
  text_ = text;
  translation_ = translation;
  next_text_ = next_text;
  width_ = ClampInt(width, kMinWidth, kMaxWidth);
  height_ = ClampInt(height, kMinHeight, kMaxHeight);
  font_size_ = ClampInt(font_size, 14, 56);
  text_color_ = text_color;
  highlight_color_ = highlight_color;
  highlight_progress_ = ClampProgress(highlight_progress);
  is_locked_ = locked;

  if (!EnsureWindow()) {
    return false;
  }

  ResetMarquee();
  ApplyBounds(false);
  ShowWindow(window_, SW_SHOWNOACTIVATE);
  RefreshMarqueeTimer();
  InvalidateRect(window_, nullptr, TRUE);
  return true;
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
  const bool text_changed = text != text_ || translation != translation_ ||
                            next_text != next_text_;
  text_ = text;
  translation_ = translation;
  next_text_ = next_text;
  font_size_ = ClampInt(font_size, 14, 56);
  text_color_ = text_color;
  highlight_color_ = highlight_color;
  highlight_progress_ = ClampProgress(highlight_progress);
  is_locked_ = locked;

  if (!EnsureWindow()) {
    return false;
  }

  if (!IsWindowVisible(window_)) {
    width_ = ClampInt(width, kMinWidth, kMaxWidth);
    height_ = ClampInt(height, kMinHeight, kMaxHeight);
    ApplyBounds(false);
    ShowWindow(window_, SW_SHOWNOACTIVATE);
  } else {
    ApplyBounds(true);
  }

  if (text_changed) {
    ResetMarquee();
  }
  RefreshMarqueeTimer();
  InvalidateRect(window_, nullptr, TRUE);
  return true;
}

void FloatingLyricsWindow::Hide() {
  StopMarqueeTimer();
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
      WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW, kClassName,
      L"Mconnect Floating Lyrics", WS_POPUP, 0, 0, width_, height_, nullptr,
      nullptr, GetModuleHandle(nullptr), this);
  if (window_ == nullptr) {
    return false;
  }

  SetLayeredWindowAttributes(window_, kTransparentColor, 255, LWA_COLORKEY);
  return true;
}

void FloatingLyricsWindow::ApplyBounds(bool preserve_position) {
  if (window_ == nullptr) {
    return;
  }

  if (preserve_position && IsWindowVisible(window_)) {
    RECT rect{};
    GetWindowRect(window_, &rect);
    SetWindowPos(window_, HWND_TOPMOST, rect.left, rect.top, width_, height_,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    return;
  }

  const int screen_width = GetSystemMetrics(SM_CXSCREEN);
  const int x = std::max(0, (screen_width - width_) / 2);
  SetWindowPos(window_, HWND_TOPMOST, x, 80, width_, height_,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void FloatingLyricsWindow::Paint(HDC dc) {
  RECT rect{};
  GetClientRect(window_, &rect);

  HDC buffer_dc = CreateCompatibleDC(dc);
  HBITMAP buffer_bitmap =
      CreateCompatibleBitmap(dc, rect.right - rect.left, rect.bottom - rect.top);
  HBITMAP old_bitmap =
      static_cast<HBITMAP>(SelectObject(buffer_dc, buffer_bitmap));

  HBRUSH background = CreateSolidBrush(kTransparentColor);
  FillRect(buffer_dc, &rect, background);
  DeleteObject(background);

  const bool has_translation = !translation_.empty();
  RECT main_rect{};
  RECT translation_rect{};
  RECT next_rect{};
  ComputeTextRects(&main_rect, &translation_rect, &next_rect);

  // The already-sung prefix is re-painted in the highlight colour, clipped to
  // the width of those glyphs. A marquee (text wider than the window) has no
  // meaningful prefix geometry, so the sweep is skipped there.
  HFONT measure_font = CreateLyricsFont(font_size_, true);
  HFONT previous_font = static_cast<HFONT>(SelectObject(buffer_dc, measure_font));
  const int main_text_width = TextWidth(buffer_dc, text_);
  SelectObject(buffer_dc, previous_font);
  DeleteObject(measure_font);
  const bool is_marqueeing =
      main_text_width > (main_rect.right - main_rect.left);
  const int highlight_characters =
      is_marqueeing || text_.empty()
          ? 0
          : static_cast<int>(highlight_progress_ * text_.size() + 0.5);

  DrawOutlinedText(buffer_dc, text_, main_rect, font_size_, true, text_color_,
                   true, highlight_color_, highlight_characters);
  if (has_translation) {
    DrawOutlinedText(buffer_dc, translation_, translation_rect,
                     std::max(12, font_size_ - 7), false,
                     DimColor(text_color_, 0.9), true);
  }
  if (!next_text_.empty() && next_rect.bottom > next_rect.top) {
    DrawOutlinedText(buffer_dc, next_text_, next_rect,
                     std::max(11, font_size_ - 9), false,
                     DimColor(text_color_, 0.6), true);
  }
  DrawControls(buffer_dc);

  BitBlt(dc, 0, 0, rect.right - rect.left, rect.bottom - rect.top, buffer_dc,
         0, 0, SRCCOPY);
  SelectObject(buffer_dc, old_bitmap);
  DeleteObject(buffer_bitmap);
  DeleteDC(buffer_dc);
}

void FloatingLyricsWindow::StartMarqueeTimer() {
  if (window_ == nullptr || marquee_timer_id_ != 0) {
    return;
  }
  marquee_timer_id_ = SetTimer(window_, kMarqueeTimerId, kMarqueeTimerMs,
                               nullptr);
}

void FloatingLyricsWindow::StopMarqueeTimer() {
  if (window_ != nullptr && marquee_timer_id_ != 0) {
    KillTimer(window_, marquee_timer_id_);
  }
  marquee_timer_id_ = 0;
}

void FloatingLyricsWindow::ResetMarquee() {
  marquee_started_at_ = GetTickCount();
}

void FloatingLyricsWindow::ToggleLock() {
  is_locked_ = !is_locked_;
  SendEvent("lockChanged");
  InvalidateRect(window_, nullptr, TRUE);
}

void FloatingLyricsWindow::FinishResize() {
  RECT rect{};
  GetWindowRect(window_, &rect);
  width_ = ClampInt(rect.right - rect.left, kMinWidth, kMaxWidth);
  height_ = ClampInt(rect.bottom - rect.top, kMinHeight, kMaxHeight);
  SendEvent("windowResized");
}

void FloatingLyricsWindow::SendEvent(const std::string& event) {
  if (event_callback_) {
    event_callback_(event);
  }
}

void FloatingLyricsWindow::ComputeTextRects(RECT* main_rect,
                                            RECT* translation_rect,
                                            RECT* next_rect) const {
  const int left = kControlMargin;
  const int right = width_ - kControlMargin;
  const int top = kControlMargin + kControlSize + 2;
  const int bottom = height_ - kControlMargin;
  const int available = std::max(0, bottom - top);

  int main_height = font_size_ + 10;
  int translation_height = translation_.empty()
                               ? 0
                               : std::max(12, font_size_ - 7) + 6;
  int next_height = 0;
  if (!next_text_.empty()) {
    const int candidate = std::max(11, font_size_ - 9) + 4;
    // The preview line gives way first: it must never squeeze the line being
    // sung, which is what the user is actually reading.
    if (available - main_height - translation_height >= candidate) {
      next_height = candidate;
    }
  }

  const int total = main_height + translation_height + next_height;
  if (total > available) {
    const int deficit = total - available;
    const int translation_cut =
        std::min(deficit, std::max(0, translation_height - 12));
    translation_height -= translation_cut;
    const int remaining = deficit - translation_cut;
    main_height = std::max(font_size_ / 2, main_height - remaining);
  }

  const int stack_height = main_height + translation_height + next_height;
  const int cursor_start = top + std::max(0, (available - stack_height) / 2);

  int cursor = cursor_start;
  main_rect->left = left;
  main_rect->right = right;
  main_rect->top = cursor;
  main_rect->bottom = cursor + main_height;
  cursor += main_height;

  translation_rect->left = left + 8;
  translation_rect->right = right - 8;
  translation_rect->top = cursor;
  translation_rect->bottom = cursor + translation_height;
  cursor += translation_height;

  next_rect->left = left + 8;
  next_rect->right = right - 8;
  next_rect->top = cursor;
  next_rect->bottom = cursor + next_height;
}

RECT FloatingLyricsWindow::GetLockButtonRect() const {
  RECT rect{};
  rect.left = kControlMargin;
  rect.top = kControlMargin;
  rect.right = rect.left + kControlSize;
  rect.bottom = rect.top + kControlSize;
  return rect;
}

RECT FloatingLyricsWindow::GetCloseButtonRect() const {
  RECT rect{};
  rect.right = width_ - kControlMargin;
  rect.top = kControlMargin;
  rect.left = rect.right - kControlSize;
  rect.bottom = rect.top + kControlSize;
  return rect;
}

RECT FloatingLyricsWindow::GetResizeHandleRect() const {
  RECT rect{};
  rect.right = width_ - kControlMargin;
  rect.bottom = height_ - kControlMargin;
  rect.left = rect.right - kResizeHandleSize;
  rect.top = rect.bottom - kResizeHandleSize;
  return rect;
}

bool FloatingLyricsWindow::IsInLockButton(int x, int y) const {
  const RECT rect = GetLockButtonRect();
  return x >= rect.left && x <= rect.right && y >= rect.top &&
         y <= rect.bottom;
}

bool FloatingLyricsWindow::IsInCloseButton(int x, int y) const {
  const RECT rect = GetCloseButtonRect();
  return x >= rect.left && x <= rect.right && y >= rect.top &&
         y <= rect.bottom;
}

bool FloatingLyricsWindow::IsInResizeHandle(int x, int y) const {
  if (is_locked_) {
    return false;
  }
  const RECT rect = GetResizeHandleRect();
  return x >= rect.left && x <= rect.right && y >= rect.top &&
         y <= rect.bottom;
}

bool FloatingLyricsWindow::IsMarqueeNeeded(HDC dc) const {
  RECT main_rect{};
  RECT translation_rect{};
  RECT next_rect{};
  ComputeTextRects(&main_rect, &translation_rect, &next_rect);

  HFONT font = CreateLyricsFont(font_size_, true);
  HFONT old_font = static_cast<HFONT>(SelectObject(dc, font));
  bool needed = TextWidth(dc, text_) > main_rect.right - main_rect.left;
  SelectObject(dc, old_font);
  DeleteObject(font);
  if (!needed && !translation_.empty()) {
    HFONT translation_font =
        CreateLyricsFont(std::max(12, font_size_ - 7), false);
    old_font = static_cast<HFONT>(SelectObject(dc, translation_font));
    needed = TextWidth(dc, translation_) >
             translation_rect.right - translation_rect.left;
    SelectObject(dc, old_font);
    DeleteObject(translation_font);
  }
  return needed;
}

void FloatingLyricsWindow::RefreshMarqueeTimer() {
  if (window_ == nullptr) {
    return;
  }
  HDC dc = GetDC(window_);
  const bool needed = dc != nullptr && IsMarqueeNeeded(dc);
  if (dc != nullptr) {
    ReleaseDC(window_, dc);
  }
  if (needed) {
    StartMarqueeTimer();
  } else {
    StopMarqueeTimer();
  }
}

int FloatingLyricsWindow::MarqueeOffset(int text_width, int rect_width) const {
  if (text_width <= rect_width) {
    return (rect_width - text_width) / 2;
  }

  constexpr int delay_ms = 350;
  constexpr int gap = 72;
  constexpr double pixels_per_second = 96.0;
  const DWORD elapsed = GetTickCount() - marquee_started_at_;
  if (elapsed < delay_ms) {
    return rect_width;
  }
  const int distance = text_width + rect_width + gap;
  const int traveled = static_cast<int>(
      ((elapsed - delay_ms) * pixels_per_second / 1000.0));
  return rect_width - (traveled % distance);
}

void FloatingLyricsWindow::DrawOutlinedText(HDC dc,
                                            const std::wstring& text,
                                            RECT rect,
                                            int font_size,
                                            bool bold,
                                            COLORREF color,
                                            bool marquee,
                                            COLORREF highlight_color,
                                            int highlight_characters) {
  if (text.empty()) {
    return;
  }

  HFONT font = CreateLyricsFont(font_size, bold);
  HFONT old_font = static_cast<HFONT>(SelectObject(dc, font));
  SetBkMode(dc, TRANSPARENT);

  const int text_width = TextWidth(dc, text);
  const int rect_width = rect.right - rect.left;
  TEXTMETRICW metrics{};
  GetTextMetricsW(dc, &metrics);
  const int text_height = metrics.tmHeight;
  const int available_height = static_cast<int>(rect.bottom - rect.top);
  const int y = rect.top + std::max(0, (available_height - text_height) / 2);

  HRGN clip = CreateRectRgn(rect.left, rect.top, rect.right, rect.bottom);
  SelectClipRgn(dc, clip);

  const int x = (marquee && text_width > rect_width)
                    ? rect.left + MarqueeOffset(text_width, rect_width)
                    : rect.left + std::max(0, (rect_width - text_width) / 2);

  if (marquee && text_width > rect_width) {
    PaintOutlinedGlyphRun(dc, text, x, y, color);
    if (x + text_width + 80 < rect.right) {
      PaintOutlinedGlyphRun(dc, text, x + text_width + 80, y, color);
    }
  } else {
    PaintOutlinedGlyphRun(dc, text, x, y, color);
  }

  // Re-paint the already-sung prefix in the highlight colour. The outline pass
  // above already drew the black halo, so this pass only replaces the glyph
  // fill and needs no second outline.
  if (highlight_color != CLR_INVALID && highlight_characters > 0 &&
      highlight_characters <= static_cast<int>(text.size())) {
    const std::wstring prefix = text.substr(0, highlight_characters);
    const int prefix_width = TextWidth(dc, prefix);
    if (prefix_width > 0) {
      const int saved = SaveDC(dc);
      HRGN prefix_clip =
          CreateRectRgn(x, rect.top, x + prefix_width, rect.bottom);
      SelectClipRgn(dc, prefix_clip);
      SetTextColor(dc, highlight_color);
      TextOutW(dc, x, y, prefix.c_str(), static_cast<int>(prefix.size()));
      RestoreDC(dc, saved);
      DeleteObject(prefix_clip);
    }
  }

  SelectClipRgn(dc, nullptr);
  DeleteObject(clip);
  SelectObject(dc, old_font);
  DeleteObject(font);
}

void FloatingLyricsWindow::DrawControls(HDC dc) {
  SetBkMode(dc, TRANSPARENT);

  const RECT lock_rect = GetLockButtonRect();
  const COLORREF lock_bg =
      lock_hovered_ ? RGB(58, 58, 58) : RGB(32, 32, 32);
  HBRUSH lock_brush = CreateSolidBrush(lock_bg);
  FillRect(dc, &lock_rect, lock_brush);
  DeleteObject(lock_brush);

  HPEN lock_pen = CreatePen(PS_SOLID, 1,
                            is_locked_ ? RGB(255, 190, 92) : RGB(90, 90, 90));
  HPEN old_pen = static_cast<HPEN>(SelectObject(dc, lock_pen));
  HBRUSH old_brush =
      static_cast<HBRUSH>(SelectObject(dc, GetStockObject(NULL_BRUSH)));
  Rectangle(dc, lock_rect.left, lock_rect.top, lock_rect.right,
            lock_rect.bottom);
  SelectObject(dc, old_pen);
  SelectObject(dc, old_brush);
  DeleteObject(lock_pen);

  SetTextColor(dc, is_locked_ ? RGB(255, 210, 130) : RGB(224, 224, 224));
  HFONT control_font = CreateLyricsFont(10, true);
  HFONT old_font = static_cast<HFONT>(SelectObject(dc, control_font));
  RECT lock_text = lock_rect;
  DrawTextW(dc, is_locked_ ? L"锁" : L"移", -1, &lock_text,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(dc, old_font);
  DeleteObject(control_font);

  const RECT close_rect = GetCloseButtonRect();
  const COLORREF close_bg =
      close_hovered_ ? RGB(190, 45, 45) : RGB(32, 32, 32);
  HBRUSH close_brush = CreateSolidBrush(close_bg);
  FillRect(dc, &close_rect, close_brush);
  DeleteObject(close_brush);

  HPEN close_pen = CreatePen(PS_SOLID, 1,
                             close_hovered_ ? RGB(255, 130, 130)
                                            : RGB(90, 90, 90));
  old_pen = static_cast<HPEN>(SelectObject(dc, close_pen));
  old_brush = static_cast<HBRUSH>(SelectObject(dc, GetStockObject(NULL_BRUSH)));
  Rectangle(dc, close_rect.left, close_rect.top, close_rect.right,
            close_rect.bottom);
  SelectObject(dc, old_pen);
  SelectObject(dc, old_brush);
  DeleteObject(close_pen);

  SetTextColor(dc, RGB(232, 232, 232));
  control_font = CreateLyricsFont(13, true);
  old_font = static_cast<HFONT>(SelectObject(dc, control_font));
  RECT close_text = close_rect;
  DrawTextW(dc, L"X", -1, &close_text,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(dc, old_font);
  DeleteObject(control_font);

  if (!is_locked_) {
    const RECT resize_rect = GetResizeHandleRect();
    HPEN resize_pen = CreatePen(
        PS_SOLID, 2, resize_hovered_ ? RGB(255, 212, 74) : RGB(235, 235, 235));
    old_pen = static_cast<HPEN>(SelectObject(dc, resize_pen));
    for (int i = 0; i < 3; i++) {
      const int offset = 5 + i * 5;
      MoveToEx(dc, resize_rect.right - offset, resize_rect.bottom - 3,
               nullptr);
      LineTo(dc, resize_rect.right - 3, resize_rect.bottom - offset);
    }
    SelectObject(dc, old_pen);
    DeleteObject(resize_pen);
  }
}

void FloatingLyricsWindow::UpdateHoverState(int x, int y) {
  const bool next_close = IsInCloseButton(x, y);
  const bool next_lock = IsInLockButton(x, y);
  const bool next_resize = IsInResizeHandle(x, y);
  if (close_hovered_ == next_close && lock_hovered_ == next_lock &&
      resize_hovered_ == next_resize) {
    return;
  }
  close_hovered_ = next_close;
  lock_hovered_ = next_lock;
  resize_hovered_ = next_resize;
  InvalidateRect(window_, nullptr, FALSE);
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

  if (that == nullptr) {
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

  switch (message) {
    case WM_ERASEBKGND:
      return 1;

    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(hwnd, &paint);
      that->Paint(dc);
      EndPaint(hwnd, &paint);
      return 0;
    }

    case WM_TIMER:
      if (wparam == kMarqueeTimerId && IsWindowVisible(hwnd)) {
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }
      break;

    case WM_MOUSEMOVE: {
      const int x = GET_X_LPARAM(lparam);
      const int y = GET_Y_LPARAM(lparam);
      that->UpdateHoverState(x, y);

      if (that->is_dragging_ || that->is_resizing_) {
        POINT point{x, y};
        ClientToScreen(hwnd, &point);
        const int dx = point.x - that->drag_start_.x;
        const int dy = point.y - that->drag_start_.y;
        if (that->is_dragging_) {
          RECT next = that->drag_origin_;
          OffsetRect(&next, dx, dy);
          SetWindowPos(hwnd, HWND_TOPMOST, next.left, next.top, 0, 0,
                       SWP_NOSIZE | SWP_NOACTIVATE);
        } else {
          const int next_width = ClampInt(
              that->drag_origin_.right - that->drag_origin_.left + dx,
              kMinWidth, kMaxWidth);
          const int next_height = ClampInt(
              that->drag_origin_.bottom - that->drag_origin_.top + dy,
              kMinHeight, kMaxHeight);
          that->width_ = next_width;
          that->height_ = next_height;
          SetWindowPos(hwnd, HWND_TOPMOST, that->drag_origin_.left,
                       that->drag_origin_.top, next_width, next_height,
                       SWP_NOACTIVATE);
          InvalidateRect(hwnd, nullptr, TRUE);
        }
        return 0;
      }

      TRACKMOUSEEVENT track{};
      track.cbSize = sizeof(TRACKMOUSEEVENT);
      track.dwFlags = TME_LEAVE;
      track.hwndTrack = hwnd;
      TrackMouseEvent(&track);
      return 0;
    }

    case WM_MOUSELEAVE:
      that->close_hovered_ = false;
      that->lock_hovered_ = false;
      that->resize_hovered_ = false;
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;

    case WM_SETCURSOR:
      if (LOWORD(lparam) == HTCLIENT && that->resize_hovered_) {
        SetCursor(LoadCursor(nullptr, IDC_SIZENWSE));
        return TRUE;
      }
      break;

    case WM_LBUTTONDOWN: {
      const int x = GET_X_LPARAM(lparam);
      const int y = GET_Y_LPARAM(lparam);
      if (that->IsInCloseButton(x, y)) {
        that->Hide();
        that->SendEvent("closedByUser");
        return 0;
      }
      if (that->IsInLockButton(x, y)) {
        that->ToggleLock();
        return 0;
      }
      if (that->IsInResizeHandle(x, y)) {
        that->is_resizing_ = true;
      } else if (!that->is_locked_) {
        that->is_dragging_ = true;
      }
      if (that->is_dragging_ || that->is_resizing_) {
        POINT point{x, y};
        ClientToScreen(hwnd, &point);
        that->drag_start_ = point;
        GetWindowRect(hwnd, &that->drag_origin_);
        SetCapture(hwnd);
        return 0;
      }
      break;
    }

    case WM_LBUTTONUP:
      if (that->is_dragging_ || that->is_resizing_) {
        const bool resized = that->is_resizing_;
        that->is_dragging_ = false;
        that->is_resizing_ = false;
        ReleaseCapture();
        if (resized) {
          that->FinishResize();
        }
        return 0;
      }
      break;

    case WM_GETMINMAXINFO: {
      auto info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = kMinWidth;
      info->ptMinTrackSize.y = kMinHeight;
      info->ptMaxTrackSize.x = kMaxWidth;
      info->ptMaxTrackSize.y = kMaxHeight;
      return 0;
    }
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}
