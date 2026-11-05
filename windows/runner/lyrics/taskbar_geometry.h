#ifndef RUNNER_LYRICS_TASKBAR_GEOMETRY_H_
#define RUNNER_LYRICS_TASKBAR_GEOMETRY_H_

#include <windows.h>

#include <string>
#include <vector>

#include "lyrics_types.h"

namespace lyrics {

enum class TaskbarEdge { kBottom, kTop, kLeft, kRight };

const char* TaskbarEdgeName(TaskbarEdge edge);

// Raw rectangles probed from the shell, in physical pixels.
struct TaskbarGeometryInput {
  RECT monitor = {};
  RECT taskbar = {};
  RECT tray_notify = {};
  RECT task_list = {};
  bool has_tray_notify = false;
  bool has_task_list = false;
  bool auto_hide = false;
  UINT dpi = 96;
};

struct TaskbarGeometry {
  bool found = false;
  TaskbarEdge edge = TaskbarEdge::kBottom;
  int thickness = 0;
  RECT monitor = {};
  RECT taskbar_rect = {};
  // The band between the task list and the notification area: the room the
  // lyrics strip actually has. Never a rectangle that covers a button.
  RECT free_rect = {};
  RECT tray_rect = {};
  RECT task_list_rect = {};
  bool auto_hide = false;
  bool space_insufficient = false;
  // Diagnostic: the trimmed band (task list + notification area removed) was
  // too small, so free_rect fell back to the whole taskbar. The strip stays in
  // the bar either way; this only says the bar is crowded.
  bool trimmed_insufficient = false;
  UINT dpi = 96;
  std::wstring monitor_name;
};

// Pure: derives the edge, thickness and free band from the raw rectangles.
// Separated from the shell probes so it can be exercised with fixed input
// (see RunTaskbarGeometrySelfTest).
TaskbarGeometry ComputeTaskbarGeometry(const TaskbarGeometryInput& input);

struct TaskbarLyricsPlacement {
  // False when there is no taskbar to sit in: the window must stay hidden
  // instead of falling back to a screen-centred strip. rect is zero then.
  bool visible = false;
  RECT rect = {};
  // Reported only: the band is below the usable width or the minimum the strip
  // needs. It never moves the strip out of the taskbar.
  bool space_insufficient = false;
};

// Places the strip inside the taskbar band. anchor auto/left/center/right plus
// offset_x, width and height come from the protocol style. The result is always
// inside geometry.taskbar_rect (a crowded bar is squeezed, never abandoned),
// except when there is no bar at all, which answers visible = false.
TaskbarLyricsPlacement PlaceTaskbarLyrics(const TaskbarGeometry& geometry,
                                          const TaskbarLyricsStyle& style,
                                          double dpi_scale,
                                          int height_px);

// Live shell probes.
bool ProbeTaskbar(HMONITOR monitor, TaskbarGeometry* geometry);
std::vector<TaskbarGeometry> ProbeAllTaskbars();

// Startup self-check of the pure geometry; returns true when every case holds.
bool RunTaskbarGeometrySelfTest(std::wstring* failure);

}  // namespace lyrics

#endif  // RUNNER_LYRICS_TASKBAR_GEOMETRY_H_
