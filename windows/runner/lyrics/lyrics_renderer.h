#ifndef RUNNER_LYRICS_LYRICS_RENDERER_H_
#define RUNNER_LYRICS_LYRICS_RENDERER_H_

#include <windows.h>

#include <memory>
#include <string>
#include <vector>

#include "lyrics_animation.h"
#include "lyrics_types.h"

namespace lyrics {

enum class RendererKind { kDirect2D, kGdiPlus };

// One interactive control: the rectangle the window hit-tests and the action
// name the window reports. Keeping this in one place means a control can never
// be drawn somewhere the user cannot click.
struct ControlRect {
  RECT rect = {};
  std::string action;
};

struct ControlLayout {
  RECT lock_rect = {};
  RECT close_rect = {};
  RECT resize_rect = {};
  RECT lyric_area = {};
  std::vector<ControlRect> transport;
};

ControlLayout ComputeControlLayout(const FloatingLyricsStyle& style,
                                   int width,
                                   int height,
                                   double dpi_scale,
                                   bool has_song);

// Everything one frame needs. Passed by value into the renderer so a draw can
// never observe half-updated state while the window changes it.
struct RenderScene {
  int width = 0;
  int height = 0;
  double dpi_scale = 1.0;
  FloatingLyricsStyle style;
  LyricsFrame frame;
  LineTransitionFrame transition;
  bool transition_active = false;
  std::wstring previous_text;
  std::wstring previous_translation;
  WindowTransitionFrame window;
  double marquee_offset = 0.0;
  std::string hovered_action;
  // Taskbar mode: a single strip without the floating window's controls.
  bool compact = false;
  bool show_transport = false;
  double highlight_progress = 0.0;
  std::vector<double> word_segments;
};

// Draws one frame into a top-down 32bpp premultiplied DIB and pushes it to the
// layered window with UpdateLayeredWindow. Direct2D + DirectWrite is the primary
// path; GDI+ takes over per-pixel when Direct2D cannot be created or its render
// target is lost, because a silent blank overlay is worse than a simpler one.
class LyricsRenderer {
 public:
  LyricsRenderer();
  ~LyricsRenderer();

  bool Initialize(HWND hwnd);
  void Shutdown();

  // Recreates the DIB when the window size changed; cheap otherwise.
  bool EnsureSurface(int width, int height);
  bool Render(const RenderScene& scene);

  RendererKind kind() const { return kind_; }
  const std::wstring& fallback_reason() const { return fallback_reason_; }
  int surface_width() const { return surface_width_; }
  int surface_height() const { return surface_height_; }

  // Width of one line at the given physical font size, used to decide whether
  // the active line has to scroll.
  double MeasureLineWidth(const FloatingLyricsStyle& style,
                          const std::wstring& text,
                          double font_size,
                          double letter_spacing);

  // Owns the Direct2D/DirectWrite objects; defined in the .cpp so this header
  // stays free of COM and SDK render types.
  struct Backend;

 private:

  bool CreateDirect2DTarget();
  bool InitializeGdiPlus();
  bool RenderDirect2D(const RenderScene& scene);
  bool RenderGdiPlus(const RenderScene& scene);
  bool Present();
  void ReleaseSurface();

  HWND hwnd_ = nullptr;
  RendererKind kind_ = RendererKind::kDirect2D;
  std::wstring fallback_reason_;

  HDC memory_dc_ = nullptr;
  HBITMAP dib_ = nullptr;
  HGDIOBJ previous_bitmap_ = nullptr;
  void* bits_ = nullptr;
  int surface_width_ = 0;
  int surface_height_ = 0;
  int surface_stride_ = 0;

  bool gdiplus_started_ = false;
  unsigned long long gdiplus_token_ = 0;

  std::unique_ptr<Backend> backend_;
};

}  // namespace lyrics

#endif  // RUNNER_LYRICS_LYRICS_RENDERER_H_
