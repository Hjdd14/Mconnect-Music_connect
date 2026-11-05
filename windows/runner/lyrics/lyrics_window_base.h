#ifndef RUNNER_LYRICS_LYRICS_WINDOW_BASE_H_
#define RUNNER_LYRICS_LYRICS_WINDOW_BASE_H_

#include <windows.h>

#include <string>
#include <vector>

#include "lyrics_renderer.h"
#include "lyrics_types.h"

namespace lyrics {

// Monitor enumeration in physical pixels. The device name is the one Windows
// uses in MONITORINFOEX (\\.\DISPLAY1), which is what the Dart side stores.
bool EnumerateMonitors(std::vector<MonitorInfo>* monitors);
const MonitorInfo* FindMonitor(const std::vector<MonitorInfo>& monitors,
                               const std::wstring& device_name);
UINT MonitorDpi(HMONITOR monitor);
std::wstring MonitorDeviceName(HMONITOR monitor);

// Base for the two layered lyric windows: creation, the per-pixel layered
// surface, the frame timer, hit testing (including click-through), dragging,
// resizing and DPI changes. Subclasses only describe what to draw and which
// controls exist.
class LyricsWindowBase {
 public:
  LyricsWindowBase();
  virtual ~LyricsWindowBase();

  bool Create(const wchar_t* class_name,
              const wchar_t* title,
              int width,
              int height);
  void Destroy();

  void ShowNoActivate();
  void Hide();
  bool visible() const;
  HWND hwnd() const { return hwnd_; }

  RECT bounds() const;
  void SetBounds(int x, int y, int width, int height, bool show);
  int width() const { return width_; }
  int height() const { return height_; }
  UINT dpi() const { return dpi_; }
  double dpi_scale() const { return dpi_scale_; }

  void SetEventListener(EventListener listener);
  void SetTopmost(bool topmost);
  void SetClickThrough(bool click_through);
  bool click_through() const { return click_through_; }

  // Marks one composition + present as due; starts the frame timer if needed.
  void RequestFrame();
  void RenderNow();
  void StartTimer(UINT interval_ms);
  void StopTimer();

  const std::string& hovered_action() const { return hovered_action_; }
  LyricsRenderer* renderer() { return &renderer_; }
  const LyricsRenderer* renderer() const { return &renderer_; }

  static LRESULT CALLBACK WindowProc(HWND hwnd,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam);

 protected:
  // Fills everything but width/height, which the base always sets from the
  // current window size. Returning false skips the frame.
  virtual bool BuildScene(RenderScene* scene) = 0;
  virtual void OnFrameTick(long long now_ms) {}
  virtual bool CanDragNow() const { return draggable_; }
  virtual bool CanResizeNow() const {
    return resizable_ && !is_locked_;
  }
  virtual std::string HitTestAction(int x, int y) const { return std::string(); }
  virtual bool OnAction(const std::string& action, int x, int y) { return false; }
  virtual void OnMouseMove(int x, int y) {}
  virtual void OnDragFinished() {}
  virtual void OnSizeSettled() {}
  virtual void OnDpiChanged(UINT dpi, int width, int height) {}
  virtual void OnSystemChange(UINT message) {}
  // Subclass-specific messages (wheel, context menu, ...). Returning true means
  // the message was handled and `result` is the window procedure result.
  virtual bool OnWindowMessage(UINT message,
                               WPARAM wparam,
                               LPARAM lparam,
                               LRESULT* result) {
    return false;
  }

  virtual void Emit(const std::string& name, const EventArguments& args = {});

  bool draggable_ = true;
  bool resizable_ = true;
  bool is_locked_ = false;
  HWND hwnd_ = nullptr;
  // True while the user owns the window geometry: a drag (mouse capture) or a
  // modal move/size loop. Subclasses skip their programmatic layout then, or a
  // frame arriving mid-gesture snaps the window back under the cursor.
  bool dragging_ = false;
  bool resizing_ = false;

 private:
  LRESULT HandleMessage(HWND hwnd,
                        UINT message,
                        WPARAM wparam,
                        LPARAM lparam);
  void BeginDrag(int x, int y);
  void UpdateHover(int x, int y);

  LyricsRenderer renderer_;
  EventListener listener_;
  std::string hovered_action_;
  std::wstring class_name_;
  int width_ = 100;
  int height_ = 100;
  UINT dpi_ = 96;
  double dpi_scale_ = 1.0;
  UINT_PTR timer_id_ = 0;
  UINT timer_interval_ = 0;
  bool click_through_ = false;
  bool topmost_ = true;
  bool render_ready_ = false;
  bool tracking_mouse_ = false;
  POINT drag_cursor_ = {};
  RECT drag_rect_ = {};

  static constexpr UINT_PTR kFrameTimerId = 1;
  static constexpr UINT kFrameIntervalMs = 16;
};

}  // namespace lyrics

#endif  // RUNNER_LYRICS_LYRICS_WINDOW_BASE_H_
