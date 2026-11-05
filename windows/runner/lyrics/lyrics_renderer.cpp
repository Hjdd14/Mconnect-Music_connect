#include "lyrics_renderer.h"

#include <algorithm>
#include <cmath>
#include <string>
#include <utility>
#include <vector>

// The GDI+ headers still spell min/max unqualified in a few inline helpers, and
// the runner is built with NOMINMAX. Pulling the standard algorithms into the
// global namespace before those headers is the documented workaround and keeps
// this translation unit self-contained.
using std::max;
using std::min;

#include <d2d1.h>
#include <d2d1helper.h>
#include <dwrite.h>
#include <dwrite_1.h>
#include <objidl.h>

#include <gdiplus.h>

namespace lyrics {
namespace {

// Minimal COM pointer. The runner builds with _HAS_EXCEPTIONS=0 and does not
// otherwise depend on WRL/ATL, so a 30 line holder is safer than a new include.
template <typename T>
class ComPtr {
 public:
  ComPtr() = default;
  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;
  ComPtr(ComPtr&& other) noexcept : ptr_(other.ptr_) { other.ptr_ = nullptr; }
  ComPtr& operator=(ComPtr&& other) noexcept {
    if (this != &other) {
      Reset();
      ptr_ = other.ptr_;
      other.ptr_ = nullptr;
    }
    return *this;
  }
  ~ComPtr() { Reset(); }

  T** Put() {
    Reset();
    return &ptr_;
  }
  T* Get() const { return ptr_; }
  T* operator->() const { return ptr_; }
  explicit operator bool() const { return ptr_ != nullptr; }
  void Reset() {
    if (ptr_ != nullptr) {
      ptr_->Release();
      ptr_ = nullptr;
    }
  }

 private:
  T* ptr_ = nullptr;
};

D2D1_COLOR_F ToColorF(const ArgbColor& color, double alpha) {
  const float a =
      static_cast<float>(Clamp01(alpha) * (static_cast<double>(color.a) / 255.0));
  return D2D1::ColorF(static_cast<float>(color.r) / 255.0f,
                      static_cast<float>(color.g) / 255.0f,
                      static_cast<float>(color.b) / 255.0f, a);
}

D2D1_RECT_F ToRectF(const RECT& rect) {
  return D2D1::RectF(static_cast<float>(rect.left),
                     static_cast<float>(rect.top),
                     static_cast<float>(rect.right),
                     static_cast<float>(rect.bottom));
}

DWRITE_TEXT_ALIGNMENT ToDWriteAlignment(HorizontalAlign align) {
  switch (align) {
    case HorizontalAlign::kLeft:
      return DWRITE_TEXT_ALIGNMENT_LEADING;
    case HorizontalAlign::kRight:
      return DWRITE_TEXT_ALIGNMENT_TRAILING;
    case HorizontalAlign::kCenter:
      return DWRITE_TEXT_ALIGNMENT_CENTER;
  }
  return DWRITE_TEXT_ALIGNMENT_CENTER;
}

Gdiplus::StringAlignment ToGdiAlignment(HorizontalAlign align) {
  switch (align) {
    case HorizontalAlign::kLeft:
      return Gdiplus::StringAlignmentNear;
    case HorizontalAlign::kRight:
      return Gdiplus::StringAlignmentFar;
    case HorizontalAlign::kCenter:
      return Gdiplus::StringAlignmentCenter;
  }
  return Gdiplus::StringAlignmentCenter;
}

Gdiplus::Color ToGdiColor(const ArgbColor& color, double alpha) {
  const BYTE a = static_cast<BYTE>(
      Clamp01(alpha) * static_cast<double>(color.a));
  return Gdiplus::Color(a, color.r, color.g, color.b);
}

constexpr double kMinLineHeight = 1.0;

// One laid-out lyric line, shared by both renderers.
struct TextLine {
  std::wstring text;
  RECT rect = {};
  double font_size = 20.0;
  int weight = 600;
  double letter_spacing = 0.0;
  double line_height = 1.2;
  HorizontalAlign align = HorizontalAlign::kCenter;
  ArgbColor color = {255, 255, 255, 255};
  ArgbColor stroke = {255, 0, 0, 0};
  double stroke_width = 0.0;
  double alpha = 1.0;
  double shadow_opacity = 0.0;
  double shadow_offset = 0.0;
  double marquee_offset = 0.0;
  bool scroll = false;
  bool sweep = false;
  bool glow = false;
  ArgbColor highlight = {255, 255, 212, 74};
  double highlight_progress = 0.0;
  const std::vector<double>* segments = nullptr;
  std::wstring family;
};

struct LineBoxes {
  RECT main = {};
  RECT translation = {};
  RECT next = {};
  double main_size = 20.0;
  double translation_size = 14.0;
  double next_size = 12.0;
};

}  // namespace

struct LyricsRenderer::Backend {
  struct FormatEntry {
    std::wstring key;
    ComPtr<IDWriteTextFormat> format;
  };

  ComPtr<ID2D1Factory> factory;
  ComPtr<ID2D1DCRenderTarget> target;
  ComPtr<IDWriteFactory> write_factory;
  std::vector<FormatEntry> formats;
};

namespace {

IDWriteTextFormat* GetTextFormat(LyricsRenderer::Backend* backend,
                                 const TextLine& line) {
  if (backend == nullptr || !backend->write_factory) {
    return nullptr;
  }
  const wchar_t* family =
      line.family.empty() ? L"Microsoft YaHei UI" : line.family.c_str();
  wchar_t key[320] = {};
  swprintf_s(key, L"%s|%.1f|%d|%d|%.3f|%.3f|%d", family, line.font_size,
             line.weight, static_cast<int>(line.align), line.letter_spacing,
             line.line_height, line.scroll ? 1 : 0);
  for (const auto& entry : backend->formats) {
    if (entry.key == key) {
      return entry.format.Get();
    }
  }

  ComPtr<IDWriteTextFormat> format;
  const auto weight =
      static_cast<DWRITE_FONT_WEIGHT>(ClampInt(line.weight, 100, 900));
  HRESULT hr = backend->write_factory->CreateTextFormat(
      family, nullptr, weight, DWRITE_FONT_STYLE_NORMAL,
      DWRITE_FONT_STRETCH_NORMAL, static_cast<FLOAT>(line.font_size), L"zh-CN",
      format.Put());
  if (FAILED(hr)) {
    // The requested family may not exist (a user supplied name, or an older
    // Windows without the icon font). Segoe UI always does.
    hr = backend->write_factory->CreateTextFormat(
        L"Segoe UI", nullptr, weight, DWRITE_FONT_STYLE_NORMAL,
        DWRITE_FONT_STRETCH_NORMAL, static_cast<FLOAT>(line.font_size),
        L"zh-CN", format.Put());
    if (FAILED(hr)) {
      return nullptr;
    }
  }
  format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
  format->SetTextAlignment(line.scroll ? DWRITE_TEXT_ALIGNMENT_LEADING
                                       : ToDWriteAlignment(line.align));
  format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
  const FLOAT line_height = static_cast<FLOAT>(
      max(kMinLineHeight, line.line_height) * line.font_size);
  format->SetLineSpacing(DWRITE_LINE_SPACING_METHOD_UNIFORM, line_height,
                         line_height * 0.8f);

  LyricsRenderer::Backend::FormatEntry entry;
  entry.key = key;
  entry.format = std::move(format);
  backend->formats.push_back(std::move(entry));
  return backend->formats.back().format.Get();
}

// Horizontal offset of the already-sung prefix inside one layout. Character
// based boundaries come from word-by-word lyrics (QRC/KRC/YRC); everything else
// interpolates uniformly across the line.
double HighlightOffsetX(IDWriteTextLayout* layout,
                        const std::wstring& text,
                        double progress,
                        const std::vector<double>* segments) {
  if (layout == nullptr || text.empty()) {
    return 0.0;
  }
  const UINT32 length = static_cast<UINT32>(text.size());
  const auto hit = [layout](UINT32 index, FLOAT* leading, FLOAT* width) {
    FLOAT x = 0.0f;
    FLOAT y = 0.0f;
    DWRITE_HIT_TEST_METRICS metrics = {};
    if (FAILED(layout->HitTestTextPosition(index, FALSE, &x, &y, &metrics))) {
      *leading = 0.0f;
      *width = 0.0f;
      return;
    }
    *leading = x;
    *width = metrics.width;
  };

  UINT32 char_index = 0;
  double fraction = 0.0;
  const double clamped = Clamp01(progress);
  if (segments != nullptr && segments->size() >= 2) {
    std::size_t index = 0;
    while (index + 2 < segments->size() && clamped >= (*segments)[index + 1]) {
      ++index;
    }
    const double start = (*segments)[index];
    const double end = (*segments)[index + 1];
    fraction = end > start ? Clamp01((clamped - start) / (end - start)) : 1.0;
    char_index = static_cast<UINT32>(min<std::size_t>(index, length - 1));
  } else {
    const double scaled = clamped * static_cast<double>(length);
    const double floored = std::floor(scaled);
    char_index = static_cast<UINT32>(min<double>(
        floored, static_cast<double>(length) - 1.0));
    fraction = Clamp01(scaled - static_cast<double>(char_index));
  }

  FLOAT leading = 0.0f;
  FLOAT width = 0.0f;
  hit(char_index, &leading, &width);
  return static_cast<double>(leading) +
         static_cast<double>(width) * fraction;
}

void DrawLayoutWithColor(ID2D1DCRenderTarget* target,
                         IDWriteTextLayout* layout,
                         double x,
                         double y,
                         const ArgbColor& color,
                         double alpha) {
  if (target == nullptr || layout == nullptr || color.a == 0) {
    return;
  }
  ComPtr<ID2D1SolidColorBrush> brush;
  if (FAILED(target->CreateSolidColorBrush(ToColorF(color, alpha), brush.Put()))) {
    return;
  }
  target->DrawTextLayout(
      D2D1::Point2F(static_cast<FLOAT>(x), static_cast<FLOAT>(y)), layout,
      brush.Get(), D2D1_DRAW_TEXT_OPTIONS_NONE);
}

void DrawTextLineD2D(LyricsRenderer::Backend* backend,
                     ID2D1DCRenderTarget* target,
                     const TextLine& line) {
  if (backend == nullptr || target == nullptr || line.text.empty() ||
      line.alpha <= 0.001) {
    return;
  }
  const double rect_width =
      static_cast<double>(line.rect.right - line.rect.left);
  const double rect_height =
      static_cast<double>(line.rect.bottom - line.rect.top);
  if (rect_width < 1.0 || rect_height < 1.0) {
    return;
  }

  IDWriteTextFormat* format = GetTextFormat(backend, line);
  if (format == nullptr) {
    return;
  }
  // A scrolling line is laid out against a box far wider than the window so
  // DirectWrite never ellipsizes it; the axis aligned clip below keeps it
  // inside the window.
  const double box_width = line.scroll ? 120000.0 : rect_width;
  ComPtr<IDWriteTextLayout> layout;
  if (FAILED(backend->write_factory->CreateTextLayout(
          line.text.c_str(), static_cast<UINT32>(line.text.size()), format,
          static_cast<FLOAT>(box_width), static_cast<FLOAT>(rect_height),
          layout.Put()))) {
    return;
  }
  if (line.letter_spacing != 0.0) {
    IDWriteTextLayout1* layout1 = nullptr;
    if (SUCCEEDED(layout->QueryInterface(__uuidof(IDWriteTextLayout1),
                                         reinterpret_cast<void**>(&layout1))) &&
        layout1 != nullptr) {
      const DWRITE_TEXT_RANGE range = {0,
                                       static_cast<UINT32>(line.text.size())};
      layout1->SetCharacterSpacing(static_cast<FLOAT>(line.letter_spacing),
                                   static_cast<FLOAT>(line.letter_spacing),
                                   0.0f, range);
      layout1->Release();
    }
  }

  DWRITE_TEXT_METRICS metrics = {};
  if (FAILED(layout->GetMetrics(&metrics))) {
    return;
  }
  const double origin_x =
      static_cast<double>(line.rect.left) - (line.scroll ? line.marquee_offset : 0.0);
  const double origin_y =
      static_cast<double>(line.rect.top) +
      (rect_height - static_cast<double>(metrics.height)) * 0.5;

  if (line.scroll) {
    target->PushAxisAlignedClip(ToRectF(line.rect),
                                D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  }

  if (line.shadow_opacity > 0.0 && line.shadow_offset > 0.0) {
    ArgbColor shadow = {static_cast<unsigned char>(
                            Clamp01(line.shadow_opacity) * 255.0),
                        0, 0, 0};
    DrawLayoutWithColor(target, layout.Get(), origin_x,
                        origin_y + line.shadow_offset, shadow, line.alpha);
  }

  if (line.stroke_width >= 0.5) {
    const double step = max(1.0, line.stroke_width);
    for (int dx = -1; dx <= 1; ++dx) {
      for (int dy = -1; dy <= 1; ++dy) {
        if (dx == 0 && dy == 0) {
          continue;
        }
        DrawLayoutWithColor(target, layout.Get(),
                            origin_x + static_cast<double>(dx) * step,
                            origin_y + static_cast<double>(dy) * step,
                            line.stroke, line.alpha);
      }
    }
  }

  if (line.glow) {
    ArgbColor glow = line.highlight;
    for (int offset = -3; offset <= 3; offset += 6) {
      DrawLayoutWithColor(target, layout.Get(), origin_x,
                          origin_y + static_cast<double>(offset), glow,
                          line.alpha * 0.25);
    }
  }

  DrawLayoutWithColor(target, layout.Get(), origin_x, origin_y, line.color,
                      line.alpha);

  if (line.sweep && line.highlight_progress > 0.0) {
    const double offset = HighlightOffsetX(
        layout.Get(), line.text, line.highlight_progress, line.segments);
    if (offset > 0.5) {
      RECT clip = line.rect;
      clip.right = clip.left + static_cast<LONG>(offset);
      if (clip.right > clip.left) {
        target->PushAxisAlignedClip(ToRectF(clip),
                                    D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        DrawLayoutWithColor(target, layout.Get(), origin_x, origin_y,
                            line.highlight, line.alpha);
        target->PopAxisAlignedClip();
      }
    }
  }

  if (line.scroll) {
    target->PopAxisAlignedClip();
  }
}

bool WantsTranslation(const FloatingLyricsStyle& style,
                      const std::wstring& translation,
                      bool compact) {
  if (compact && style.translation_layout == TranslationLayout::kHidden) {
    return false;
  }
  if (style.show_translation == TranslationRule::kNever) {
    return false;
  }
  if (style.show_translation == TranslationRule::kAlways) {
    return !translation.empty();
  }
  return !translation.empty();
}

bool WantsNext(const FloatingLyricsStyle& style, const std::wstring& next) {
  if (next.empty()) {
    return false;
  }
  return style.line_mode == LineMode::kCurrentAndNext ||
         style.line_mode == LineMode::kThreeLines;
}

LineBoxes ComputeLineBoxes(const RenderScene& scene,
                           const std::wstring& translation,
                           const std::wstring& next_text) {
  LineBoxes boxes;
  const auto& style = scene.style;
  const double scale = scene.dpi_scale > 0.0 ? scene.dpi_scale : 1.0;
  const ControlLayout controls = ComputeControlLayout(
      style, scene.width, scene.height, scale, scene.frame.has_song);
  RECT area = controls.lyric_area;
  if (area.right <= area.left || area.bottom <= area.top) {
    area = RECT{0, 0, scene.width, scene.height};
  }

  boxes.main_size = max(11.0, style.font_size * scale);
  boxes.translation_size = max(10.0, boxes.main_size * 0.72);
  boxes.next_size = max(9.0, boxes.main_size * 0.62);

  const bool has_translation =
      WantsTranslation(style, translation, scene.compact);
  const bool has_next = WantsNext(style, next_text);
  const double line_height = max(kMinLineHeight, style.line_height);

  double main_height = boxes.main_size * line_height;
  double translation_height = has_translation ? boxes.translation_size * 1.25 : 0.0;
  double next_height = has_next ? boxes.next_size * 1.2 : 0.0;

  const double available = static_cast<double>(area.bottom - area.top);

  // One-line taskbar strip: keep the main lyric and its translation on the
  // same baseline instead of reserving two rows. Width follows the relative
  // text lengths so a long English translation is not clipped while the short
  // Chinese line keeps half the strip.
  if (scene.compact && style.translation_layout == TranslationLayout::kInline &&
      has_translation) {
    const double gap = 8.0 * scale;
    const double width = static_cast<double>(area.right - area.left);
    const double main_weight = max(1.0, static_cast<double>(scene.frame.text.size())) *
                               boxes.main_size;
    const double translation_weight =
        max(1.0, static_cast<double>(translation.size())) *
        boxes.translation_size;
    double main_width = width * main_weight / (main_weight + translation_weight);
    main_width = min(max(main_width, width * 0.28), width * 0.72);
    const double inline_height =
        min(available, boxes.main_size * line_height * 1.15);
    const int top =
        area.top + static_cast<int>(max(0.0, (available - inline_height) * 0.5));
    boxes.main = RECT{area.left, top,
                      area.left + static_cast<int>(main_width),
                      top + static_cast<int>(inline_height)};
    boxes.translation = RECT{
        area.left + static_cast<int>(main_width + gap), top, area.right,
        top + static_cast<int>(inline_height)};
    boxes.next = RECT{};
    return boxes;
  }

  const double total = main_height + translation_height + next_height;
  if (total > available && total > 0.0) {
    const double factor = available / total;
    main_height *= factor;
    translation_height *= factor;
    next_height *= factor;
  }

  int cursor = area.top +
               static_cast<int>(max(0.0, (available - (main_height + translation_height + next_height)) * 0.5));

  boxes.main.left = area.left;
  boxes.main.right = area.right;
  boxes.main.top = cursor;
  boxes.main.bottom = cursor + static_cast<int>(main_height);
  cursor = boxes.main.bottom;

  boxes.translation.left = area.left;
  boxes.translation.right = area.right;
  boxes.translation.top = cursor;
  boxes.translation.bottom = cursor + static_cast<int>(translation_height);
  cursor = boxes.translation.bottom;

  boxes.next.left = area.left;
  boxes.next.right = area.right;
  boxes.next.top = cursor;
  boxes.next.bottom = cursor + static_cast<int>(next_height);
  return boxes;
}

TextLine MakeLine(const RenderScene& scene,
                  const std::wstring& text,
                  const RECT& rect,
                  double font_size,
                  ArgbColor color,
                  double alpha) {
  const auto& style = scene.style;
  const double scale = scene.dpi_scale > 0.0 ? scene.dpi_scale : 1.0;
  TextLine line;
  line.text = text;
  line.rect = rect;
  line.font_size = font_size;
  line.weight = style.font_weight;
  line.letter_spacing = style.letter_spacing * scale;
  line.line_height = max(kMinLineHeight, style.line_height);
  line.align = style.text_align;
  line.color = color;
  line.stroke = style.stroke_color;
  line.stroke_width = style.stroke_width * scale;
  line.alpha = alpha;
  line.shadow_opacity = style.shadow_opacity;
  line.shadow_offset = max(1.0, style.shadow_blur * scale * 0.25);
  line.family = style.font_family;
  line.highlight = style.highlight_color;
  line.segments = &scene.word_segments;
  line.highlight_progress = scene.highlight_progress;
  return line;
}

void DrawContentBlockD2D(LyricsRenderer::Backend* backend,
                         ID2D1DCRenderTarget* target,
                         const RenderScene& scene,
                         const std::wstring& text,
                         const std::wstring& translation,
                         const std::wstring& next_text,
                         double alpha,
                         double dx,
                         double dy,
                         double scale_x,
                         double scale_y,
                         double clip_fraction,
                         bool clip_from_left,
                         bool sweep,
                         bool glow) {
  if (target == nullptr || text.empty() && translation.empty()) {
    return;
  }
  const LineBoxes boxes = ComputeLineBoxes(scene, translation, next_text);
  if (boxes.main.right <= boxes.main.left || boxes.main.bottom <= boxes.main.top) {
    return;
  }

  RECT clip = boxes.main;
  const bool wipe = clip_fraction < 0.999;
  if (wipe) {
    const LONG width = clip.right - clip.left;
    const LONG revealed =
        static_cast<LONG>(static_cast<double>(width) * Clamp01(clip_fraction));
    if (revealed <= 0) {
      return;
    }
    if (clip_from_left) {
      clip.right = clip.left + revealed;
    } else {
      clip.left = clip.right - revealed;
    }
  }

  const double w = static_cast<double>(scene.width);
  const double h = static_cast<double>(scene.height);
  const D2D1_POINT_2F centre =
      D2D1::Point2F(static_cast<FLOAT>(w * 0.5), static_cast<FLOAT>(h * 0.5));
  const D2D1::Matrix3x2F window =
      D2D1::Matrix3x2F::Scale(static_cast<FLOAT>(max(0.05, scene.window.scale)),
                              static_cast<FLOAT>(max(0.05, scene.window.scale)),
                              centre) *
      D2D1::Matrix3x2F::Translation(static_cast<FLOAT>(scene.window.dx * w),
                                    static_cast<FLOAT>(scene.window.dy * h));
  const D2D1::Matrix3x2F block =
      D2D1::Matrix3x2F::Scale(static_cast<FLOAT>(max(0.02, scale_x)),
                              static_cast<FLOAT>(max(0.02, scale_y)), centre) *
      D2D1::Matrix3x2F::Translation(static_cast<FLOAT>(dx * w),
                                    static_cast<FLOAT>(dy * h));

  target->SetTransform(block * window);
  if (wipe) {
    target->PushAxisAlignedClip(ToRectF(clip),
                                D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  }

  const ArgbColor dim = scene.style.text_color;
  TextLine main_line = MakeLine(scene, text, boxes.main, boxes.main_size, dim,
                                alpha);
  main_line.scroll = scene.marquee_offset > 0.0;
  main_line.marquee_offset = scene.marquee_offset;
  main_line.sweep = sweep && scene.style.word_highlight;
  main_line.glow = glow;
  DrawTextLineD2D(backend, target, main_line);

  const bool has_translation =
      WantsTranslation(scene.style, translation, scene.compact);
  if (has_translation) {
    ArgbColor color = scene.style.text_color;
    color.a = static_cast<unsigned char>(color.a * 0.86);
    TextLine line = MakeLine(scene, translation, boxes.translation,
                             boxes.translation_size, color, alpha);
    line.stroke_width = 0.0;
    line.shadow_opacity = 0.0;
    DrawTextLineD2D(backend, target, line);
  }

  const bool has_next = WantsNext(scene.style, next_text);
  if (has_next) {
    ArgbColor color = scene.style.text_color;
    color.a = static_cast<unsigned char>(color.a * 0.60);
    TextLine line =
        MakeLine(scene, next_text, boxes.next, boxes.next_size, color, alpha);
    line.stroke_width = 0.0;
    line.shadow_opacity = 0.0;
    DrawTextLineD2D(backend, target, line);
  }

  if (wipe) {
    target->PopAxisAlignedClip();
  }
  target->SetTransform(window);
}

void DrawButtonD2D(LyricsRenderer::Backend* backend,
                   ID2D1DCRenderTarget* target,
                   const RECT& rect,
                   const wchar_t* glyph,
                   bool hovered,
                   double alpha,
                   double scale) {
  const double radius = 6.0 * scale;
  ArgbColor background = hovered ? ArgbColor{150, 255, 255, 255}
                                 : ArgbColor{64, 20, 20, 20};
  ComPtr<ID2D1SolidColorBrush> brush;
  if (SUCCEEDED(
          target->CreateSolidColorBrush(ToColorF(background, alpha), brush.Put()))) {
    target->FillRoundedRectangle(
        D2D1::RoundedRect(ToRectF(rect), static_cast<FLOAT>(radius),
                          static_cast<FLOAT>(radius)),
        brush.Get());
  }
  TextLine line;
  line.text = glyph;
  line.rect = rect;
  line.font_size = max(9.0, static_cast<double>(rect.bottom - rect.top) * 0.60);
  line.family = L"Segoe MDL2 Assets";
  line.weight = 400;
  line.align = HorizontalAlign::kCenter;
  line.color = ArgbColor{255, 236, 236, 236};
  line.alpha = alpha;
  DrawTextLineD2D(backend, target, line);
}

void DrawControlsD2D(LyricsRenderer::Backend* backend,
                     ID2D1DCRenderTarget* target,
                     const RenderScene& scene,
                     double alpha) {
  const auto& style = scene.style;
  if (!style.show_controls || scene.compact) {
    return;
  }
  const double scale = scene.dpi_scale > 0.0 ? scene.dpi_scale : 1.0;
  const ControlLayout layout = ComputeControlLayout(
      style, scene.width, scene.height, scale, scene.frame.has_song);

  DrawButtonD2D(backend, target, layout.lock_rect,
                style.is_locked ? L"\uE72E" : L"\uE785",
                scene.hovered_action == "lock", alpha, scale);
  DrawButtonD2D(backend, target, layout.close_rect, L"\uE8BB",
                scene.hovered_action == "close", alpha, scale);
  for (const auto& control : layout.transport) {
    const wchar_t* glyph = L"\uE768";
    if (control.action == "previous") {
      glyph = L"\uE892";
    } else if (control.action == "next") {
      glyph = L"\uE893";
    } else if (control.action == "playPause") {
      glyph = scene.frame.is_playing ? L"\uE769" : L"\uE768";
    }
    DrawButtonD2D(backend, target, control.rect, glyph,
                  scene.hovered_action == control.action, alpha, scale);
  }

  if (!style.is_locked) {
    ComPtr<ID2D1SolidColorBrush> brush;
    ArgbColor grip = {200, 235, 235, 235};
    if (SUCCEEDED(
            target->CreateSolidColorBrush(ToColorF(grip, alpha), brush.Put()))) {
      const RECT rect = layout.resize_rect;
      for (int index = 0; index < 3; ++index) {
        const FLOAT offset = static_cast<FLOAT>((4.0 + index * 4.0) * scale);
        target->DrawLine(
            D2D1::Point2F(static_cast<FLOAT>(rect.right) - offset,
                          static_cast<FLOAT>(rect.bottom) - 2.0f),
            D2D1::Point2F(static_cast<FLOAT>(rect.right) - 2.0f,
                          static_cast<FLOAT>(rect.bottom) - offset),
            brush.Get(), static_cast<FLOAT>(max(1.0, scale)));
      }
    }
  }
}

void DrawBackgroundD2D(ID2D1DCRenderTarget* target,
                       const RenderScene& scene,
                       double alpha) {
  const auto& style = scene.style;
  if (style.background_mode == BackgroundMode::kNone) {
    return;
  }
  const bool solid_visible = IsVisible(style.background_color);
  const bool second_visible = IsVisible(style.background_color2);
  if (!solid_visible && !second_visible) {
    return;
  }
  const double w = static_cast<double>(scene.width);
  const double h = static_cast<double>(scene.height);
  const double scale = scene.dpi_scale > 0.0 ? scene.dpi_scale : 1.0;
  const double radius =
      min(style.corner_radius * scale, min(w, h) * 0.5);
  const D2D1_ROUNDED_RECT rounded = D2D1::RoundedRect(
      D2D1::RectF(0.0f, 0.0f, static_cast<FLOAT>(w), static_cast<FLOAT>(h)),
      static_cast<FLOAT>(radius), static_cast<FLOAT>(radius));
  const double opacity = alpha * Clamp01(style.background_opacity);

  if (style.background_mode == BackgroundMode::kGradient ||
      style.background_mode == BackgroundMode::kCover) {
    // backgroundMode cover needs a decoded, blurred cover bitmap; until that
    // lands the configured pair of colours is the documented degradation.
    ArgbColor first = style.background_color;
    ArgbColor second = second_visible ? style.background_color2 : first;
    D2D1_GRADIENT_STOP stops[2] = {};
    stops[0].position = 0.0f;
    stops[0].color = ToColorF(first, opacity);
    stops[1].position = 1.0f;
    stops[1].color = ToColorF(second, opacity);
    ComPtr<ID2D1GradientStopCollection> collection;
    if (FAILED(target->CreateGradientStopCollection(stops, 2, collection.Put()))) {
      return;
    }
    const D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES properties =
        D2D1::LinearGradientBrushProperties(
            D2D1::Point2F(0.0f, 0.0f),
            D2D1::Point2F(0.0f, static_cast<FLOAT>(h)));
    ComPtr<ID2D1LinearGradientBrush> brush;
    if (SUCCEEDED(target->CreateLinearGradientBrush(properties, collection.Get(),
                                                    brush.Put()))) {
      target->FillRoundedRectangle(rounded, brush.Get());
    }
    return;
  }

  ComPtr<ID2D1SolidColorBrush> brush;
  if (SUCCEEDED(target->CreateSolidColorBrush(
          ToColorF(style.background_color, opacity), brush.Put()))) {
    target->FillRoundedRectangle(rounded, brush.Get());
  }
}

// --- GDI+ fallback -------------------------------------------------------

void AddRoundedRect(Gdiplus::GraphicsPath* path,
                    const Gdiplus::RectF& rect,
                    Gdiplus::REAL radius) {
  const Gdiplus::REAL diameter = radius * 2.0f;
  path->AddArc(rect.X, rect.Y, diameter, diameter, 180.0f, 90.0f);
  path->AddArc(rect.GetRight() - diameter, rect.Y, diameter, diameter, 270.0f,
               90.0f);
  path->AddArc(rect.GetRight() - diameter, rect.GetBottom() - diameter,
               diameter, diameter, 0.0f, 90.0f);
  path->AddArc(rect.X, rect.GetBottom() - diameter, diameter, diameter, 90.0f,
               90.0f);
  path->CloseFigure();
}

void DrawBackgroundGdiPlus(Gdiplus::Graphics& graphics,
                           const RenderScene& scene,
                           double alpha) {
  const auto& style = scene.style;
  if (style.background_mode == BackgroundMode::kNone) {
    return;
  }
  if (!IsVisible(style.background_color) && !IsVisible(style.background_color2)) {
    return;
  }
  const Gdiplus::REAL w = static_cast<Gdiplus::REAL>(scene.width);
  const Gdiplus::REAL h = static_cast<Gdiplus::REAL>(scene.height);
  const double scale = scene.dpi_scale > 0.0 ? scene.dpi_scale : 1.0;
  const Gdiplus::REAL radius = static_cast<Gdiplus::REAL>(
      min(style.corner_radius * scale, min<double>(scene.width, scene.height) * 0.5));
  const Gdiplus::RectF rect(0.0f, 0.0f, w, h);
  Gdiplus::GraphicsPath path;
  AddRoundedRect(&path, rect, radius);
  const double opacity = alpha * Clamp01(style.background_opacity);
  if (style.background_mode == BackgroundMode::kGradient ||
      style.background_mode == BackgroundMode::kCover) {
    const ArgbColor second = IsVisible(style.background_color2)
                                 ? style.background_color2
                                 : style.background_color;
    Gdiplus::LinearGradientBrush brush(rect, ToGdiColor(style.background_color, opacity),
                                       ToGdiColor(second, opacity),
                                       Gdiplus::LinearGradientModeVertical);
    graphics.FillPath(&brush, &path);
  } else {
    Gdiplus::SolidBrush brush(ToGdiColor(style.background_color, opacity));
    graphics.FillPath(&brush, &path);
  }
}

void DrawTextLineGdiPlus(Gdiplus::Graphics& graphics, const TextLine& line) {
  
  if (line.text.empty() || line.alpha <= 0.001) {
    return;
  }
  const double width = static_cast<double>(line.rect.right - line.rect.left);
  const double height = static_cast<double>(line.rect.bottom - line.rect.top);
  if (width < 1.0 || height < 1.0) {
    return;
  }
  Gdiplus::FontFamily requested(line.family.empty() ? L"Microsoft YaHei UI"
                                                    : line.family.c_str());
  const Gdiplus::FontFamily* generic =
      Gdiplus::FontFamily::GenericSansSerif();
  const Gdiplus::FontFamily* family =
      requested.IsAvailable() ? &requested : generic;
  const INT style = line.weight >= 600 ? Gdiplus::FontStyleBold
                                       : Gdiplus::FontStyleRegular;
  Gdiplus::Font font(family, static_cast<Gdiplus::REAL>(line.font_size), style,
                     Gdiplus::UnitPixel);
  if (font.GetLastStatus() != Gdiplus::Ok) {
    return;
  }
  Gdiplus::StringFormat format;
  format.SetAlignment(ToGdiAlignment(line.align));
  format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  const Gdiplus::RectF layout(
      static_cast<Gdiplus::REAL>(line.rect.left),
      static_cast<Gdiplus::REAL>(line.rect.top),
      static_cast<Gdiplus::REAL>(width), static_cast<Gdiplus::REAL>(height));

  Gdiplus::GraphicsPath path;
  if (path.AddString(line.text.c_str(), static_cast<INT>(line.text.size()),
                     family, style,
                     static_cast<Gdiplus::REAL>(line.font_size),
                     Gdiplus::PointF(0.0f, 0.0f),
                     &format) != Gdiplus::Ok) {
    return;
  }
  Gdiplus::RectF bounds;
  path.GetBounds(&bounds);
  Gdiplus::Matrix matrix;
  const Gdiplus::REAL offset_x =
      layout.X + (layout.Width - bounds.Width) * 0.5f - bounds.X -
      static_cast<Gdiplus::REAL>(line.scroll ? line.marquee_offset : 0.0);
  const Gdiplus::REAL offset_y =
      layout.Y + (layout.Height - bounds.Height) * 0.5f - bounds.Y;
  matrix.Translate(offset_x, offset_y);
  path.Transform(&matrix);

  graphics.SetClip(layout);
  if (line.stroke_width >= 0.5) {
    Gdiplus::Pen pen(ToGdiColor(line.stroke, line.alpha),
                     static_cast<Gdiplus::REAL>(line.stroke_width) * 2.0f);
    pen.SetLineJoin(Gdiplus::LineJoinRound);
    graphics.DrawPath(&pen, &path);
  }
  Gdiplus::SolidBrush brush(ToGdiColor(line.color, line.alpha));
  graphics.FillPath(&brush, &path);
  if (line.sweep && line.highlight_progress > 0.0) {
    const Gdiplus::REAL prefix = static_cast<Gdiplus::REAL>(
        bounds.Width * Clamp01(line.highlight_progress));
    graphics.SetClip(Gdiplus::RectF(layout.X, layout.Y, prefix, layout.Height));
    Gdiplus::SolidBrush highlight(ToGdiColor(line.highlight, line.alpha));
    graphics.FillPath(&highlight, &path);
  }
  graphics.ResetClip();
}

void DrawContentBlockGdiPlus(Gdiplus::Graphics& graphics,
                             const RenderScene& scene,
                             const std::wstring& text,
                             const std::wstring& translation,
                             const std::wstring& next_text,
                             double alpha,
                             double dy) {
  
  const LineBoxes boxes = ComputeLineBoxes(scene, translation, next_text);
  const auto shift = [dy](const RECT& rect) {
    RECT moved = rect;
    moved.top += static_cast<LONG>(dy);
    moved.bottom += static_cast<LONG>(dy);
    return moved;
  };
  TextLine line = MakeLine(scene, text, shift(boxes.main), boxes.main_size,
                           scene.style.text_color, alpha);
  line.scroll = scene.marquee_offset > 0.0;
  line.marquee_offset = scene.marquee_offset;
  line.sweep = scene.style.word_highlight;
  DrawTextLineGdiPlus(graphics, line);

  if (WantsTranslation(scene.style, translation, scene.compact)) {
    ArgbColor color = scene.style.text_color;
    color.a = static_cast<unsigned char>(color.a * 0.86);
    TextLine translated =
        MakeLine(scene, translation, shift(boxes.translation),
                 boxes.translation_size, color, alpha);
    translated.stroke_width = 0.0;
    translated.shadow_opacity = 0.0;
    DrawTextLineGdiPlus(graphics, translated);
  }
  if (WantsNext(scene.style, next_text)) {
    ArgbColor color = scene.style.text_color;
    color.a = static_cast<unsigned char>(color.a * 0.60);
    TextLine upcoming = MakeLine(scene, next_text, shift(boxes.next),
                                 boxes.next_size, color, alpha);
    upcoming.stroke_width = 0.0;
    upcoming.shadow_opacity = 0.0;
    DrawTextLineGdiPlus(graphics, upcoming);
  }
}

void DrawControlsGdiPlus(Gdiplus::Graphics& graphics,
                         const RenderScene& scene,
                         double alpha) {
  const auto& style = scene.style;
  if (!style.show_controls || scene.compact) {
    return;
  }
  const double scale = scene.dpi_scale > 0.0 ? scene.dpi_scale : 1.0;
  const ControlLayout layout = ComputeControlLayout(
      style, scene.width, scene.height, scale, scene.frame.has_song);
  const auto draw_button = [&graphics, alpha, scale](const RECT& rect,
                                                     const wchar_t* glyph,
                                                     bool hovered) {
    const Gdiplus::REAL radius = static_cast<Gdiplus::REAL>(6.0 * scale);
    const Gdiplus::RectF box(static_cast<Gdiplus::REAL>(rect.left),
                             static_cast<Gdiplus::REAL>(rect.top),
                             static_cast<Gdiplus::REAL>(rect.right - rect.left),
                             static_cast<Gdiplus::REAL>(rect.bottom - rect.top));
    Gdiplus::GraphicsPath path;
    AddRoundedRect(&path, box, radius);
    const ArgbColor background = hovered ? ArgbColor{150, 255, 255, 255}
                                         : ArgbColor{64, 20, 20, 20};
    Gdiplus::SolidBrush brush(ToGdiColor(background, alpha));
    graphics.FillPath(&brush, &path);
    Gdiplus::FontFamily icons(L"Segoe MDL2 Assets");
    if (!icons.IsAvailable()) {
      return;
    }
    Gdiplus::Font font(&icons, static_cast<Gdiplus::REAL>(box.Height * 0.60),
                       Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    Gdiplus::SolidBrush glyph_brush(ToGdiColor(ArgbColor{255, 236, 236, 236}, alpha));
    graphics.DrawString(glyph, -1, &font, box, &format, &glyph_brush);
  };

  draw_button(layout.lock_rect,
              style.is_locked ? L"\uE72E" : L"\uE785",
              scene.hovered_action == "lock");
  draw_button(layout.close_rect, L"\uE8BB", scene.hovered_action == "close");
  for (const auto& control : layout.transport) {
    const wchar_t* glyph = L"\uE768";
    if (control.action == "previous") {
      glyph = L"\uE892";
    } else if (control.action == "next") {
      glyph = L"\uE893";
    } else if (control.action == "playPause") {
      glyph = scene.frame.is_playing ? L"\uE769" : L"\uE768";
    }
    draw_button(control.rect, glyph, scene.hovered_action == control.action);
  }
}

}  // namespace

ControlLayout ComputeControlLayout(const FloatingLyricsStyle& style,
                                   int width,
                                   int height,
                                   double dpi_scale,
                                   bool has_song) {
  ControlLayout layout;
  const double scale = dpi_scale > 0.0 ? dpi_scale : 1.0;
  const int margin = static_cast<int>(std::lround(6.0 * scale));
  const int control = static_cast<int>(std::lround(22.0 * scale));
  const int gap = static_cast<int>(std::lround(4.0 * scale));
  const double padding = max(2.0, style.padding * scale);
  const int left = static_cast<int>(std::lround(padding));
  const int right = width - left;
  int top = static_cast<int>(std::lround(padding));
  int bottom = height - static_cast<int>(std::lround(padding));

  layout.lock_rect = RECT{margin, margin, margin + control, margin + control};
  layout.close_rect = RECT{width - margin - control, margin, width - margin,
                           margin + control};
  layout.resize_rect = RECT{width - margin - control, height - margin - control,
                            width - margin, height - margin};

  if (style.show_controls) {
    top = margin + control + static_cast<int>(std::lround(2.0 * scale));
  }
  if (style.show_controls && has_song) {
    const int total = control * 3 + gap * 2;
    int x = (width - total) / 2;
    const int y = height - margin - control;
    for (const char* action : {"previous", "playPause", "next"}) {
      layout.transport.push_back(
          ControlRect{RECT{x, y, x + control, y + control}, action});
      x += control + gap;
    }
    bottom = min(bottom, y - static_cast<int>(std::lround(2.0 * scale)));
  }

  if (right <= left || bottom <= top) {
    layout.lyric_area = RECT{0, 0, width, height};
  } else {
    layout.lyric_area = RECT{left, top, right, bottom};
  }
  return layout;
}

LyricsRenderer::LyricsRenderer() = default;

LyricsRenderer::~LyricsRenderer() { Shutdown(); }

bool LyricsRenderer::Initialize(HWND hwnd) {
  hwnd_ = hwnd;
  backend_ = std::make_unique<Backend>();
  // GDI+ is the stable renderer for the layered overlay on this Windows /
  // Flutter combination. The Direct2D backend remains in this file for a future
  // fix, but preview and playback both use the GDI+ path today.
  kind_ = RendererKind::kGdiPlus;
  InitializeGdiPlus();
  return true;
}

bool LyricsRenderer::InitializeGdiPlus() {
  if (gdiplus_started_) {
    return true;
  }
  Gdiplus::GdiplusStartupInput input;
  ULONG_PTR token = 0;
  if (Gdiplus::GdiplusStartup(&token, &input, nullptr) != Gdiplus::Ok) {
    fallback_reason_ = L"GdiplusStartup failed";
    return false;
  }
  gdiplus_token_ = static_cast<unsigned long long>(token);
  gdiplus_started_ = true;
  return true;
}

void LyricsRenderer::ReleaseSurface() {
  if (memory_dc_ != nullptr && previous_bitmap_ != nullptr) {
    SelectObject(memory_dc_, previous_bitmap_);
    previous_bitmap_ = nullptr;
  }
  if (dib_ != nullptr) {
    DeleteObject(dib_);
    dib_ = nullptr;
  }
  if (memory_dc_ != nullptr) {
    DeleteDC(memory_dc_);
    memory_dc_ = nullptr;
  }
  bits_ = nullptr;
  surface_width_ = 0;
  surface_height_ = 0;
  surface_stride_ = 0;
}

bool LyricsRenderer::EnsureSurface(int width, int height) {
  if (width <= 0 || height <= 0) {
    return false;
  }
  if (memory_dc_ != nullptr && width == surface_width_ &&
      height == surface_height_) {
    return true;
  }
  ReleaseSurface();
  HDC screen = GetDC(nullptr);
  if (screen == nullptr) {
    return false;
  }
  memory_dc_ = CreateCompatibleDC(screen);
  ReleaseDC(nullptr, screen);
  if (memory_dc_ == nullptr) {
    return false;
  }

  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  // Top-down rows: Direct2D and GDI+ both expect the first scanline at the top.
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  dib_ = CreateDIBSection(memory_dc_, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (dib_ == nullptr || bits == nullptr) {
    ReleaseSurface();
    return false;
  }
  previous_bitmap_ = SelectObject(memory_dc_, dib_);
  bits_ = bits;
  surface_width_ = width;
  surface_height_ = height;
  surface_stride_ = width * 4;
  if (kind_ == RendererKind::kDirect2D) {
    if (!backend_->target && !CreateDirect2DTarget()) {
      kind_ = RendererKind::kGdiPlus;
      InitializeGdiPlus();
    } else {
      RECT bind_rect = {0, 0, width, height};
      if (FAILED(backend_->target->BindDC(memory_dc_, &bind_rect))) {
        backend_->target.Reset();
        kind_ = RendererKind::kGdiPlus;
        InitializeGdiPlus();
      }
    }
  }
  return true;
}

bool LyricsRenderer::CreateDirect2DTarget() {
  if (!backend_ || !backend_->factory || memory_dc_ == nullptr) {
    return false;
  }
  D2D1_RENDER_TARGET_PROPERTIES properties = D2D1::RenderTargetProperties(
      D2D1_RENDER_TARGET_TYPE_DEFAULT,
      D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                        D2D1_ALPHA_MODE_PREMULTIPLIED));
  // One DIP per pixel: all sizing decisions are made in physical pixels here so
  // the DIB, the Direct2D coordinates and the GDI+ fallback agree exactly.
  properties.dpiX = 96.0f;
  properties.dpiY = 96.0f;
  if (FAILED(backend_->factory->CreateDCRenderTarget(&properties,
                                                     backend_->target.Put()))) {
    fallback_reason_ = L"CreateDCRenderTarget failed";
    return false;
  }
  return true;
}

bool LyricsRenderer::Render(const RenderScene& scene) {
  const bool surface_ok = EnsureSurface(scene.width, scene.height);
  if (!surface_ok) {
    return false;
  }
  if (bits_ == nullptr) {
    return false;
  }
  const size_t bytes = static_cast<size_t>(surface_stride_) *
                       static_cast<size_t>(surface_height_);
  ZeroMemory(bits_, bytes);

  bool drawn = false;
  if (kind_ == RendererKind::kDirect2D) {
    drawn = RenderDirect2D(scene);
    if (!drawn) {
      // Permanent demotion: a render target that cannot draw into this surface
      // will not recover, and a blank overlay is the one outcome that looks
      // like the app is broken.
      fallback_reason_ = L"Direct2D draw failed";
      kind_ = RendererKind::kGdiPlus;
      if (backend_) {
        backend_->target.Reset();
      }
      InitializeGdiPlus();
      ZeroMemory(bits_, bytes);
    }
  }
  if (!drawn) {
    drawn = RenderGdiPlus(scene);
  }
  if (!drawn) {
    return false;
  }
  const bool presented = Present();
  return presented;
}

bool LyricsRenderer::RenderDirect2D(const RenderScene& scene) {
  if (!backend_ || !backend_->target || memory_dc_ == nullptr) {
    return false;
  }
  ID2D1DCRenderTarget* target = backend_->target.Get();
  RECT bind_rect = {0, 0, surface_width_, surface_height_};
  if (FAILED(target->BindDC(memory_dc_, &bind_rect))) {
    return false;
  }
  target->BeginDraw();
  target->SetTransform(D2D1::Matrix3x2F::Identity());
  target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
  target->SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  target->Clear(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.0f));

  const double alpha = Clamp01(scene.window.alpha);
  const double w = static_cast<double>(scene.width);
  const double h = static_cast<double>(scene.height);
  const D2D1_POINT_2F centre =
      D2D1::Point2F(static_cast<FLOAT>(w * 0.5), static_cast<FLOAT>(h * 0.5));
  const double window_scale = max(0.05, scene.window.scale);
  const D2D1_MATRIX_3X2_F window_transform =
      D2D1::Matrix3x2F::Scale(static_cast<FLOAT>(window_scale),
                              static_cast<FLOAT>(window_scale), centre) *
      D2D1::Matrix3x2F::Translation(static_cast<FLOAT>(scene.window.dx * w),
                                    static_cast<FLOAT>(scene.window.dy * h));

  target->SetTransform(window_transform);
  DrawBackgroundD2D(target, scene, alpha);

  const bool animating = scene.transition_active;
  if (animating && scene.transition.has_old && !scene.previous_text.empty()) {
    DrawContentBlockD2D(backend_.get(), target, scene, scene.previous_text,
                        scene.previous_translation, std::wstring(),
                        scene.transition.old_alpha, scene.transition.old_dx,
                        scene.transition.old_dy, scene.transition.old_scale_x,
                        scene.transition.old_scale_y, 1.0, true, false, false);
  }
  DrawContentBlockD2D(
      backend_.get(), target, scene, scene.frame.text, scene.frame.translation,
      scene.frame.next_text, animating ? scene.transition.new_alpha : 1.0,
      animating ? scene.transition.new_dx : 0.0,
      animating ? scene.transition.new_dy : 0.0,
      animating ? scene.transition.new_scale_x : 1.0,
      animating ? scene.transition.new_scale_y : 1.0,
      animating ? scene.transition.new_clip : 1.0,
      scene.transition.clip_from_left, true,
      animating && scene.transition.new_glow);

  target->SetTransform(window_transform);
  DrawControlsD2D(backend_.get(), target, scene, alpha);
  target->SetTransform(D2D1::Matrix3x2F::Identity());

  const HRESULT result = target->EndDraw();
  if (result == D2DERR_RECREATE_TARGET) {
    backend_->target.Reset();
    return false;
  }
  return SUCCEEDED(result);
}

bool LyricsRenderer::RenderGdiPlus(const RenderScene& scene) {
  if (!InitializeGdiPlus() || bits_ == nullptr) {
    return false;
  }
  Gdiplus::Bitmap bitmap(surface_width_, surface_height_, surface_stride_,
                         PixelFormat32bppPARGB,
                         static_cast<BYTE*>(bits_));
  if (bitmap.GetLastStatus() != Gdiplus::Ok) {
    return false;
  }
  Gdiplus::Graphics graphics(&bitmap);
  if (graphics.GetLastStatus() != Gdiplus::Ok) {
    return false;
  }
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
  graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
  graphics.SetCompositingQuality(Gdiplus::CompositingQualityHighQuality);
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));

  const double alpha = Clamp01(scene.window.alpha);
  // The window transition used to translate the text content by the full
  // window width/height. If the transition timer stalls, dx/dy stay at 1 and
  // every glyph is clipped outside the layered surface, leaving only the
  // unshifted lock/close controls visible. Keep the text anchored; the window
  // animation still runs through alpha/scale.
  const double vertical_shift = 0.0;
  const double horizontal_shift = 0.0;
  if (horizontal_shift != 0.0) {
    Gdiplus::Matrix shift;
    shift.Translate(static_cast<Gdiplus::REAL>(horizontal_shift), 0.0f);
    graphics.SetTransform(&shift);
  }
  DrawBackgroundGdiPlus(graphics, scene, alpha);
  if (scene.transition_active && scene.transition.has_old &&
      !scene.previous_text.empty()) {
    DrawContentBlockGdiPlus(graphics, scene, scene.previous_text,
                            scene.previous_translation, std::wstring(),
                            scene.transition.old_alpha, vertical_shift);
  }
  
  DrawContentBlockGdiPlus(graphics, scene, scene.frame.text,
                          scene.frame.translation, scene.frame.next_text,
                          scene.transition_active ? scene.transition.new_alpha
                                                  : 1.0,
                          vertical_shift);
  if (horizontal_shift != 0.0) {
    graphics.ResetTransform();
  }
  DrawControlsGdiPlus(graphics, scene, alpha);
  return graphics.GetLastStatus() == Gdiplus::Ok;
}

bool LyricsRenderer::Present() {
  if (hwnd_ == nullptr || memory_dc_ == nullptr) {
    return false;
  }
  RECT window_rect = {};
  if (!GetWindowRect(hwnd_, &window_rect)) {
    return false;
  }
  POINT destination = {window_rect.left, window_rect.top};
  SIZE size = {surface_width_, surface_height_};
  POINT source = {0, 0};
  BLENDFUNCTION blend = {};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;
  HDC screen = GetDC(nullptr);
  if (screen == nullptr) {
    return false;
  }
  const BOOL updated =
      UpdateLayeredWindow(hwnd_, screen, &destination, &size, memory_dc_,
                          &source, 0, &blend, ULW_ALPHA);
  
  ReleaseDC(nullptr, screen);
  return updated != FALSE;
}

double LyricsRenderer::MeasureLineWidth(const FloatingLyricsStyle& style,
                                        const std::wstring& text,
                                        double font_size,
                                        double letter_spacing) {
  if (text.empty()) {
    return 0.0;
  }
  if (backend_ && backend_->write_factory) {
    TextLine line;
    line.text = text;
    line.font_size = font_size;
    line.letter_spacing = letter_spacing;
    line.family = style.font_family;
    line.weight = style.font_weight;
    IDWriteTextFormat* format = GetTextFormat(backend_.get(), line);
    if (format != nullptr) {
      ComPtr<IDWriteTextLayout> layout;
      if (SUCCEEDED(backend_->write_factory->CreateTextLayout(
              text.c_str(), static_cast<UINT32>(text.size()), format, 200000.0f,
              static_cast<FLOAT>(max(8.0, font_size * 4.0)), layout.Put()))) {
        DWRITE_TEXT_METRICS metrics = {};
        if (SUCCEEDED(layout->GetMetrics(&metrics))) {
          return static_cast<double>(metrics.widthIncludingTrailingWhitespace);
        }
      }
    }
  }
  HDC screen = GetDC(nullptr);
  if (screen == nullptr) {
    return 0.0;
  }
  HFONT font = CreateFontW(
      -static_cast<int>(std::lround(font_size)), 0, 0, 0, FW_SEMIBOLD, FALSE,
      FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Microsoft YaHei UI");
  HGDIOBJ previous = SelectObject(screen, font);
  SIZE extent = {};
  const BOOL measured =
      GetTextExtentPoint32W(screen, text.c_str(), static_cast<int>(text.size()),
                            &extent);
  SelectObject(screen, previous);
  DeleteObject(font);
  ReleaseDC(nullptr, screen);
  return measured != FALSE ? static_cast<double>(extent.cx) : 0.0;
}

void LyricsRenderer::Shutdown() {
  ReleaseSurface();
  if (backend_) {
    backend_->formats.clear();
    backend_->target.Reset();
    backend_->write_factory.Reset();
    backend_->factory.Reset();
    backend_.reset();
  }
  if (gdiplus_started_) {
    Gdiplus::GdiplusShutdown(static_cast<ULONG_PTR>(gdiplus_token_));
    gdiplus_started_ = false;
    gdiplus_token_ = 0;
  }
  hwnd_ = nullptr;
}

}  // namespace lyrics
