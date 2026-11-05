#include "taskbar_geometry.h"

#include <shellapi.h>
#include <shellscalingapi.h>

#include <algorithm>
#include <cmath>

namespace lyrics {
namespace {

constexpr int kMinUsableWidthLogical = 80;
constexpr int kMinUsableHeightLogical = 14;
// A band narrower than this is reported to Dart even after the whole-bar
// fallback, because the strip is then drawn over the task buttons.
constexpr int kMinReportBandPx = 40;

UINT QueryMonitorDpi(HMONITOR monitor) {
  if (monitor == nullptr) {
    return 96;
  }
  UINT dpi_x = 96;
  UINT dpi_y = 96;
  if (SUCCEEDED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y)) &&
      dpi_x > 0) {
    return dpi_x;
  }
  return 96;
}

BOOL CALLBACK CollectMonitorCallback(HMONITOR monitor,
                                     HDC monitor_dc,
                                     LPRECT monitor_rect,
                                     LPARAM data) {
  (void)monitor_dc;
  (void)monitor_rect;
  reinterpret_cast<std::vector<HMONITOR>*>(data)->push_back(monitor);
  return TRUE;
}

// Which monitor edge the bar is docked to.
//
// The old version tested "touches the monitor's left edge" *before* "touches
// the bottom edge", so every full-width bottom bar (the Windows default) was
// classified as a LEFT bar: its rect starts at x=0. Every downstream branch
// then took the vertical path -- the strip width was pinned to the bar's
// full width, the anchor moved nothing horizontally, and dragging did not
// follow the pointer. Decide by the bar's *span*, not by which edge check
// happens to run first.
TaskbarEdge EdgeFromRect(const RECT& monitor, const RECT& taskbar) {
  const int monitor_width = monitor.right - monitor.left;
  const int monitor_height = monitor.bottom - monitor.top;
  if (monitor_width <= 0 || monitor_height <= 0) {
    return TaskbarEdge::kBottom;
  }
  const RECT bar = RECT{
      std::max(monitor.left, std::min(taskbar.left, monitor.right)),
      std::max(monitor.top, std::min(taskbar.top, monitor.bottom)),
      std::max(monitor.left, std::min(taskbar.right, monitor.right)),
      std::max(monitor.top, std::min(taskbar.bottom, monitor.bottom))};
  const int bar_width = bar.right - bar.left;
  const int bar_height = bar.bottom - bar.top;
  if (bar_width <= 0 || bar_height <= 0) {
    return TaskbarEdge::kBottom;
  }

  // A horizontal bar spans (most of) the monitor width and is only a thin
  // band tall -- that is the shape of every bottom/top dock, whether or not
  // it also touches the left edge.
  const bool horizontal_span = bar_width * 10 >= monitor_width * 9 &&
                               bar_height * 10 <= monitor_height * 5;
  if (horizontal_span) {
    const int top_gap = bar.top - monitor.top;
    const int bottom_gap = monitor.bottom - bar.bottom;
    return top_gap <= bottom_gap ? TaskbarEdge::kTop : TaskbarEdge::kBottom;
  }

  // A vertical bar spans (most of) the monitor height and is thin.
  const bool vertical_span = bar_height * 10 >= monitor_height * 9 &&
                             bar_width * 10 <= monitor_width * 5;
  if (vertical_span) {
    const int left_gap = bar.left - monitor.left;
    const int right_gap = monitor.right - bar.right;
    return left_gap <= right_gap ? TaskbarEdge::kLeft : TaskbarEdge::kRight;
  }

  // Neither shape: a floating or auto-hide bar. Pick the edge it hugs most
  // tightly, which is the only answer that still places the strip sensibly.
  const int top_gap = bar.top - monitor.top;
  const int bottom_gap = monitor.bottom - bar.bottom;
  const int left_gap = bar.left - monitor.left;
  const int right_gap = monitor.right - bar.right;
  const int best = std::min(std::min(top_gap, bottom_gap),
                            std::min(left_gap, right_gap));
  if (best == top_gap) return TaskbarEdge::kTop;
  if (best == bottom_gap) return TaskbarEdge::kBottom;
  if (best == left_gap) return TaskbarEdge::kLeft;
  return TaskbarEdge::kRight;
}

int ClampValue(int value, int low, int high) {
  if (high < low) {
    return low;
  }
  return std::max(low, std::min(value, high));
}

}  // namespace

const char* TaskbarEdgeName(TaskbarEdge edge) {
  switch (edge) {
    case TaskbarEdge::kBottom:
      return "bottom";
    case TaskbarEdge::kTop:
      return "top";
    case TaskbarEdge::kLeft:
      return "left";
    case TaskbarEdge::kRight:
      return "right";
  }
  return "bottom";
}

TaskbarGeometry ComputeTaskbarGeometry(const TaskbarGeometryInput& input) {
  TaskbarGeometry geometry;
  geometry.monitor = input.monitor;
  geometry.dpi = input.dpi;
  geometry.auto_hide = input.auto_hide;
  const int monitor_width = input.monitor.right - input.monitor.left;
  const int monitor_height = input.monitor.bottom - input.monitor.top;
  if (monitor_width <= 0 || monitor_height <= 0) {
    return geometry;
  }
  const int bar_width = input.taskbar.right - input.taskbar.left;
  const int bar_height = input.taskbar.bottom - input.taskbar.top;
  if (bar_width <= 0 || bar_height <= 0) {
    // No taskbar on this monitor: the whole monitor is free, which is what a
    // secondary screen with a single primary bar needs.
    geometry.found = false;
    geometry.free_rect = input.monitor;
    geometry.taskbar_rect = RECT{input.monitor.left, input.monitor.bottom,
                                 input.monitor.right, input.monitor.bottom};
    geometry.thickness = 0;
    return geometry;
  }

  geometry.found = true;
  geometry.taskbar_rect = input.taskbar;
  geometry.edge = EdgeFromRect(input.monitor, input.taskbar);
  switch (geometry.edge) {
    case TaskbarEdge::kTop:
    case TaskbarEdge::kBottom:
      geometry.thickness = bar_height;
      break;
    case TaskbarEdge::kLeft:
    case TaskbarEdge::kRight:
      geometry.thickness = bar_width;
      break;
  }

  RECT free_band = input.taskbar;
  // Trim the notification area so the strip never covers the clock.
  if (input.has_tray_notify) {
    const int tray_width = input.tray_notify.right - input.tray_notify.left;
    const int tray_height = input.tray_notify.bottom - input.tray_notify.top;
    if (tray_width > 0 && tray_height > 0) {
      geometry.tray_rect = input.tray_notify;
      switch (geometry.edge) {
        case TaskbarEdge::kBottom:
        case TaskbarEdge::kTop:
          free_band.right = std::min(free_band.right, input.tray_notify.left);
          break;
        case TaskbarEdge::kLeft:
        case TaskbarEdge::kRight:
          free_band.bottom = std::min(free_band.bottom, input.tray_notify.top);
          break;
      }
    }
  }
  // Trim the task list so the strip never covers an app button either.
  if (input.has_task_list) {
    const int list_width = input.task_list.right - input.task_list.left;
    const int list_height = input.task_list.bottom - input.task_list.top;
    if (list_width > 0 && list_height > 0) {
      geometry.task_list_rect = input.task_list;
      switch (geometry.edge) {
        case TaskbarEdge::kBottom:
        case TaskbarEdge::kTop:
          free_band.left = std::max(free_band.left, input.task_list.right);
          break;
        case TaskbarEdge::kLeft:
        case TaskbarEdge::kRight:
          free_band.top = std::max(free_band.top, input.task_list.bottom);
          break;
      }
    }
  }

  // Keep the band on the monitor even if a child rectangle was stale.
  free_band.left = ClampValue(free_band.left, input.monitor.left, input.monitor.right);
  free_band.top = ClampValue(free_band.top, input.monitor.top, input.monitor.bottom);
  free_band.right = ClampValue(free_band.right, input.monitor.left, input.monitor.right);
  free_band.bottom = ClampValue(free_band.bottom, input.monitor.top, input.monitor.bottom);
  if (free_band.right < free_band.left) {
    free_band.right = free_band.left;
  }
  if (free_band.bottom < free_band.top) {
    free_band.bottom = free_band.top;
  }
  geometry.free_rect = free_band;

  const double scale = static_cast<double>(input.dpi) / 96.0;
  const bool width_ok =
      (free_band.right - free_band.left) >=
      static_cast<int>(std::lround(kMinUsableWidthLogical * scale));
  const bool height_ok =
      (free_band.bottom - free_band.top) >=
      static_cast<int>(std::lround(kMinUsableHeightLogical * scale));
  geometry.space_insufficient = !width_ok || !height_ok;
  if (geometry.space_insufficient) {
    // A Win11 task list usually spans the whole bar, which trims the band down
    // to nothing. The strip still belongs to the taskbar, so the whole bar
    // becomes the band (it may overlap buttons) instead of reporting "no room"
    // and letting the window land somewhere else on the screen.
    geometry.trimmed_insufficient = true;
    geometry.free_rect = input.taskbar;
    geometry.space_insufficient = true;
  }
  return geometry;
}

TaskbarLyricsPlacement PlaceTaskbarLyrics(const TaskbarGeometry& geometry,
                                          const TaskbarLyricsStyle& style,
                                          double dpi_scale,
                                          int height_px) {
  TaskbarLyricsPlacement placement;
  const double scale = dpi_scale > 0.0 ? dpi_scale : 1.0;

  // No bar on this monitor. There is nowhere to draw a taskbar strip, so the
  // placement says "hidden" and carries an empty rectangle: the old code
  // centred a strip on the monitor here, which is the "歌词跑到屏幕正中心" bug.
  const RECT bar = geometry.taskbar_rect;
  const int bar_width = bar.right - bar.left;
  const int bar_height = bar.bottom - bar.top;
  if (!geometry.found || bar_width <= 0 || bar_height <= 0) {
    placement.visible = false;
    placement.rect = RECT{};
    placement.space_insufficient = true;
    return placement;
  }

  const bool vertical = geometry.edge == TaskbarEdge::kLeft ||
                        geometry.edge == TaskbarEdge::kRight;
  const int requested_width =
      static_cast<int>(std::lround(style.width * scale));
  const int edge_padding =
      std::max(0, static_cast<int>(std::lround(style.edge_padding * scale)));
  const int thickness = geometry.thickness > 0
                            ? geometry.thickness
                            : (vertical ? bar_width : bar_height);

  // The room the strip may use: the band between the task list and the
  // notification area when it is usable, otherwise the whole bar. Either way it
  // is clamped into the bar, because a strip outside the taskbar is exactly the
  // bug this replaces.
  RECT band = geometry.free_rect;
  band.left = ClampValue(band.left, bar.left, bar.right);
  band.right = ClampValue(band.right, bar.left, bar.right);
  band.top = ClampValue(band.top, bar.top, bar.bottom);
  band.bottom = ClampValue(band.bottom, bar.top, bar.bottom);
  if (band.right - band.left <= 0 || band.bottom - band.top <= 0) {
    band = bar;
  }
  const int band_width = band.right - band.left;
  const int band_height = band.bottom - band.top;

  placement.visible = true;
  // Reporting only: a crowded bar is worth telling Dart about, but it never
  // moves the strip out of the taskbar.
  placement.space_insufficient =
      geometry.space_insufficient || band_width < kMinReportBandPx;

  if (!vertical) {
    // Top/bottom bar: the strip runs along the bar and is centred across its
    // thickness, so it can never look like a stray floating window.
    int height = height_px > 0 ? height_px : thickness - edge_padding * 2;
    height = std::max(8, height);
    height = std::min(height, std::max(8, bar_height));
    const int y = ClampValue(bar.top + (bar_height - height) / 2, bar.top,
                             bar.bottom - height);
    int width = requested_width > 0 ? requested_width : band_width;
    width = ClampValue(width, 1, band_width);
    int x = band.left;
    if (!style.anchor_auto) {
      switch (style.anchor) {
        case HorizontalAlign::kLeft:
          x = band.left;
          break;
        case HorizontalAlign::kRight:
          x = band.right - width;
          break;
        case HorizontalAlign::kCenter:
          x = band.left + (band_width - width) / 2;
          break;
      }
    } else {
      x = band.left + (band_width - width) / 2;
    }
    x += static_cast<int>(std::lround(style.offset_x * scale));
    x = ClampValue(x, band.left, band.right - width);
    placement.rect = RECT{x, y, x + width, y + height};
    return placement;
  }

  // Left/right bar: the strip is as wide as the bar is thick and the anchor
  // plus offset slide it along the bar instead.
  int width = thickness - edge_padding * 2;
  width = std::max(8, width);
  width = std::min(width, std::max(8, bar_width));
  const int x = ClampValue(bar.left + (bar_width - width) / 2, bar.left,
                           bar.right - width);
  int height = height_px > 0 ? height_px : band_height;
  height = std::max(8, std::min(height, band_height));
  int y = band.top;
  if (!style.anchor_auto) {
    switch (style.anchor) {
      case HorizontalAlign::kLeft:
        y = band.top;
        break;
      case HorizontalAlign::kRight:
        y = band.bottom - height;
        break;
      case HorizontalAlign::kCenter:
        y = band.top + (band_height - height) / 2;
        break;
    }
  } else {
    y = band.top + (band_height - height) / 2;
  }
  y += static_cast<int>(std::lround(style.offset_x * scale));
  y = ClampValue(y, band.top, band.bottom - height);
  placement.rect = RECT{x, y, x + width, y + height};
  return placement;
}

bool ProbeTaskbar(HMONITOR monitor, TaskbarGeometry* geometry) {
  if (geometry == nullptr) {
    return false;
  }
  MONITORINFOEXW monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFOEXW);
  if (monitor == nullptr || GetMonitorInfoW(monitor, &monitor_info) == FALSE) {
    return false;
  }

  // The primary bar is Shell_TrayWnd; every secondary screen gets its own
  // Shell_SecondaryTrayWnd, and Windows also uses one for some multi-monitor
  // configurations of the primary bar.
  HWND taskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
  HWND candidate = nullptr;
  while ((candidate = FindWindowExW(nullptr, candidate,
                                    L"Shell_SecondaryTrayWnd", nullptr)) !=
         nullptr) {
    if (MonitorFromWindow(candidate, MONITOR_DEFAULTTONEAREST) == monitor) {
      taskbar = candidate;
      break;
    }
  }
  if (taskbar != nullptr &&
      MonitorFromWindow(taskbar, MONITOR_DEFAULTTONEAREST) != monitor) {
    // The primary bar lives on another monitor; a secondary one, if any, was
    // already selected above. Otherwise this monitor simply has no bar.
    HWND secondary = nullptr;
    HWND found = nullptr;
    while ((secondary = FindWindowExW(nullptr, secondary,
                                      L"Shell_SecondaryTrayWnd", nullptr)) !=
           nullptr) {
      if (MonitorFromWindow(secondary, MONITOR_DEFAULTTONEAREST) == monitor) {
        found = secondary;
        break;
      }
    }
    if (found == nullptr) {
      taskbar = nullptr;
    }
  }

  RECT taskbar_rect = {};
  if (taskbar != nullptr) {
    if (GetWindowRect(taskbar, &taskbar_rect) == FALSE) {
      taskbar = nullptr;
    }
  }

  TaskbarGeometryInput input;
  input.monitor = monitor_info.rcMonitor;
  input.dpi = QueryMonitorDpi(monitor);
  if (taskbar != nullptr) {
    input.taskbar = taskbar_rect;
    HWND tray_notify = FindWindowExW(taskbar, nullptr, L"TrayNotifyWnd", nullptr);
    if (tray_notify != nullptr &&
        GetWindowRect(tray_notify, &input.tray_notify) != FALSE) {
      input.has_tray_notify = (input.tray_notify.right > input.tray_notify.left);
    }
    HWND rebar = FindWindowExW(taskbar, nullptr, L"ReBarWindow32", nullptr);
    HWND task_list = nullptr;
    if (rebar != nullptr) {
      task_list = FindWindowExW(rebar, nullptr, L"MSTaskListWClass", nullptr);
    }
    if (task_list == nullptr) {
      task_list = FindWindowExW(taskbar, nullptr, L"MSTaskListWClass", nullptr);
    }
    if (task_list != nullptr &&
        GetWindowRect(task_list, &input.task_list) != FALSE) {
      input.has_task_list = (input.task_list.right > input.task_list.left);
    }
    APPBARDATA appbar = {};
    appbar.cbSize = sizeof(APPBARDATA);
    const UINT_PTR state = SHAppBarMessage(ABM_GETSTATE, &appbar);
    input.auto_hide = (state & ABS_AUTOHIDE) != 0;
  }

  TaskbarGeometry computed = ComputeTaskbarGeometry(input);
  computed.monitor_name = monitor_info.szDevice;
  computed.dpi = input.dpi;
  *geometry = computed;
  return computed.found;
}

std::vector<TaskbarGeometry> ProbeAllTaskbars() {
  std::vector<HMONITOR> handles;
  EnumDisplayMonitors(nullptr, nullptr, CollectMonitorCallback,
                      reinterpret_cast<LPARAM>(&handles));
  std::vector<TaskbarGeometry> result;
  result.reserve(handles.size());
  for (HMONITOR handle : handles) {
    TaskbarGeometry geometry;
    ProbeTaskbar(handle, &geometry);
    result.push_back(geometry);
  }
  return result;
}

bool RunTaskbarGeometrySelfTest(std::wstring* failure) {
  const auto expect = [failure](bool condition, const wchar_t* message) {
    if (!condition) {
      if (failure != nullptr) {
        *failure = message;
      }
      return false;
    }
    return true;
  };

  // Bottom bar, task list left of the notification area.
  TaskbarGeometryInput bottom;
  bottom.monitor = RECT{0, 0, 1920, 1080};
  bottom.taskbar = RECT{0, 1040, 1920, 1080};
  bottom.task_list = RECT{0, 1040, 1200, 1080};
  bottom.tray_notify = RECT{1700, 1040, 1920, 1080};
  bottom.has_task_list = true;
  bottom.has_tray_notify = true;
  bottom.dpi = 96;
  const TaskbarGeometry bottom_geometry = ComputeTaskbarGeometry(bottom);
  if (!expect(bottom_geometry.found, L"bottom bar not detected")) {
    return false;
  }
  if (!expect(bottom_geometry.edge == TaskbarEdge::kBottom,
              L"bottom bar edge")) {
    return false;
  }
  if (!expect(bottom_geometry.thickness == 40, L"bottom bar thickness")) {
    return false;
  }
  if (!expect(bottom_geometry.free_rect.left == 1200,
              L"free rect must start after the task list")) {
    return false;
  }
  if (!expect(bottom_geometry.free_rect.right == 1700,
              L"free rect must end before the notification area")) {
    return false;
  }
  if (!expect(!bottom_geometry.space_insufficient, L"500px band is enough")) {
    return false;
  }

  const auto inside = [](const RECT& inner, const RECT& outer) {
    return inner.left >= outer.left && inner.top >= outer.top &&
           inner.right <= outer.right && inner.bottom <= outer.bottom;
  };

  // A narrow band is not enough room and must be reported - but the band itself
  // must not collapse to nothing, because the strip still lives in the bar.
  TaskbarGeometryInput tight = bottom;
  tight.task_list = RECT{0, 1040, 1600, 1080};
  tight.tray_notify = RECT{1610, 1040, 1920, 1080};
  const TaskbarGeometry tight_geometry = ComputeTaskbarGeometry(tight);
  if (!expect(tight_geometry.space_insufficient, L"tight band must report space_insufficient")) {
    return false;
  }
  if (!expect(tight_geometry.trimmed_insufficient,
              L"tight band must report the trimmed fallback")) {
    return false;
  }
  if (!expect(tight_geometry.free_rect.right > tight_geometry.free_rect.left,
              L"a crowded bar must still provide a band")) {
    return false;
  }

  // A vertical bar on the left, as some users still run.
  TaskbarGeometryInput left;
  left.monitor = RECT{0, 0, 2560, 1440};
  left.taskbar = RECT{0, 0, 64, 1440};
  const TaskbarGeometry left_geometry = ComputeTaskbarGeometry(left);
  if (!expect(left_geometry.edge == TaskbarEdge::kLeft, L"left bar edge")) {
    return false;
  }
  if (!expect(left_geometry.thickness == 64, L"left bar thickness")) {
    return false;
  }

  TaskbarLyricsStyle style;
  style.width = 400;
  style.edge_padding = 0;

  // Centred placement inside the free band of a bottom bar.
  const TaskbarLyricsPlacement placement =
      PlaceTaskbarLyrics(bottom_geometry, style, 1.0, 32);
  if (!expect(placement.visible, L"a found taskbar must provide a placement")) {
    return false;
  }
  if (!expect(inside(placement.rect, bottom_geometry.taskbar_rect),
              L"centred placement must stay inside the taskbar")) {
    return false;
  }
  if (!expect(placement.rect.left >= bottom_geometry.free_rect.left &&
                  placement.rect.right <= bottom_geometry.free_rect.right,
              L"centred placement must stay inside the free band")) {
    return false;
  }

  // A vertical taskbar places the strip across its thickness.
  const TaskbarLyricsPlacement left_placement =
      PlaceTaskbarLyrics(left_geometry, style, 1.0, 0);
  if (!expect(left_placement.visible, L"vertical bar must provide a placement")) {
    return false;
  }
  if (!expect(inside(left_placement.rect, left_geometry.taskbar_rect),
              L"vertical placement must stay inside the bar")) {
    return false;
  }
  if (!expect(left_placement.rect.right - left_placement.rect.left <=
                  left_geometry.thickness,
              L"vertical strip must fit the bar thickness")) {
    return false;
  }

  // A monitor without a taskbar gets no placement at all: the window stays
  // hidden instead of drawing a strip in the middle of the screen.
  TaskbarGeometryInput none;
  none.monitor = RECT{1920, 0, 3840, 1080};
  none.dpi = 96;
  const TaskbarGeometry none_geometry = ComputeTaskbarGeometry(none);
  if (!expect(!none_geometry.found, L"a monitor without a bar must not be found")) {
    return false;
  }
  const TaskbarLyricsPlacement none_placement =
      PlaceTaskbarLyrics(none_geometry, style, 1.0, 32);
  if (!expect(!none_placement.visible,
              L"a monitor without a bar must not be visible")) {
    return false;
  }
  if (!expect(none_placement.rect.left == 0 && none_placement.rect.top == 0 &&
                  none_placement.rect.right == 0 &&
                  none_placement.rect.bottom == 0,
              L"a monitor without a bar must answer an empty rect")) {
    return false;
  }

  // A task list spanning the whole bar (the usual Win11 layout) used to trim
  // the band to zero and push the strip onto the screen centre.
  TaskbarGeometryInput crowded = bottom;
  crowded.task_list = RECT{0, 1040, 1920, 1080};
  const TaskbarGeometry crowded_geometry = ComputeTaskbarGeometry(crowded);
  const TaskbarLyricsPlacement crowded_placement =
      PlaceTaskbarLyrics(crowded_geometry, style, 1.0, 32);
  if (!expect(crowded_placement.visible,
              L"a full-width task list must still place the strip")) {
    return false;
  }
  if (!expect(inside(crowded_placement.rect, crowded_geometry.taskbar_rect),
              L"a full-width task list must keep the strip in the bar")) {
    return false;
  }
  // Windows' own layout: a full-width bottom bar that starts at x = 0. The old
  // edge test said "touches the left edge" before it ever considered the
  // bottom, so this exact rectangle was classified as a LEFT bar -- which is
  // why the strip ignored the width slider and the anchor.
  TaskbarGeometryInput default_bottom;
  default_bottom.monitor = RECT{0, 0, 3840, 2160};
  default_bottom.taskbar = RECT{0, 2076, 3840, 2160};
  default_bottom.dpi = 144;
  const TaskbarGeometry default_bottom_geometry =
      ComputeTaskbarGeometry(default_bottom);
  if (!expect(default_bottom_geometry.edge == TaskbarEdge::kBottom,
              L"a full-width bar at the bottom is a bottom bar")) {
    return false;
  }

  TaskbarGeometryInput top_bar = default_bottom;
  top_bar.taskbar = RECT{0, 0, 3840, 84};
  if (!expect(ComputeTaskbarGeometry(top_bar).edge == TaskbarEdge::kTop,
              L"a full-width bar at the top is a top bar")) {
    return false;
  }

  TaskbarGeometryInput right_bar;
  right_bar.monitor = RECT{0, 0, 2560, 1440};
  right_bar.taskbar = RECT{2496, 0, 2560, 1440};
  right_bar.dpi = 96;
  if (!expect(ComputeTaskbarGeometry(right_bar).edge == TaskbarEdge::kRight,
              L"a full-height bar on the right is a right bar")) {
    return false;
  }

  // A bottom bar inset from the left (a custom shell, a secondary monitor's
  // bar) must still read as the bottom.
  TaskbarGeometryInput inset_bottom = default_bottom;
  inset_bottom.taskbar = RECT{64, 2076, 3840, 2160};
  if (!expect(ComputeTaskbarGeometry(inset_bottom).edge == TaskbarEdge::kBottom,
              L"an inset bottom bar must still be a bottom bar")) {
    return false;
  }
  return true;
}

}  // namespace lyrics
