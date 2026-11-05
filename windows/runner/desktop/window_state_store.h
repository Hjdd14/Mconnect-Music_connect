#ifndef RUNNER_DESKTOP_WINDOW_STATE_STORE_H_
#define RUNNER_DESKTOP_WINDOW_STATE_STORE_H_

#include <windows.h>

#include <string>

namespace mconnect {
namespace desktop {

// The main window's geometry, as persisted between runs.
struct WindowState {
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
  bool maximized = false;
  bool valid = false;
};

// `%MCONNECT_DATA_DIR%` when the environment sets it, otherwise
// `%LOCALAPPDATA%\com.mconnect\mconnect`. No trailing separator.
//
// MCONNECT_DATA_DIR is the same override the Dart side uses for a portable
// install, so the geometry file travels with the rest of the data instead of
// ending up in the roaming profile of whoever ran the exe.
std::wstring DataDirectory();

// `<DataDirectory()>\window_state.json`.
std::wstring WindowStatePath();

// Reads the persisted state. False when the file is missing, unreadable, or
// does not carry a usable size.
bool LoadWindowState(WindowState* state);

// Writes |state| through a temporary file, so a crash mid-write cannot leave a
// truncated JSON behind. Creates the data directory when it is missing.
bool SaveWindowState(const WindowState& state);

// Deletes the persisted state (and a leftover temporary file). True when
// nothing is left on disk afterwards, including "it was never there".
bool DeleteWindowState();

// Clamps |state| into the work area of the nearest monitor: the size never
// exceeds the work area and enough of the frame stays on screen for the title
// bar to remain grabbable. This is what makes a state saved on a monitor that
// has since been unplugged — or at a much larger resolution — usable again.
bool ClampWindowStateToWorkArea(WindowState* state);

// Loads and clamps the state in one step, for Win32Window::Create: the rect is
// in physical pixels and is applied before the Flutter view exists, so the
// engine surface is correct from its very first frame.
bool LoadWindowRectForCreate(RECT* rect, bool* maximized);

}  // namespace desktop
}  // namespace mconnect

#endif  // RUNNER_DESKTOP_WINDOW_STATE_STORE_H_
