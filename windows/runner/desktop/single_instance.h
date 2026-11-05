#ifndef RUNNER_DESKTOP_SINGLE_INSTANCE_H_
#define RUNNER_DESKTOP_SINGLE_INSTANCE_H_

#include <windows.h>

#include <string>

namespace mconnect {
namespace desktop {

// dwData marker for the WM_COPYDATA hand-off. A message carrying any other
// value is not ours and is ignored by the window procedure.
constexpr ULONG_PTR kSingleInstanceCopyDataId = 0x4D433031;  // "MC01"

// Creates the named single-instance mutex and keeps it for the process
// lifetime. False when another instance already owns it, i.e. this process must
// hand its command line over and exit instead of opening a second window over
// the same database files.
//
// The name is session local (`Local\`): two different logged-in users may run
// Mconnect at the same time, which is what the Android/iOS "one library per
// user" model expects.
bool AcquireSingleInstanceMutex();

// The first command line argument that looks like a URI ("scheme://..." or
// "mconnect:..."), or an empty string. Used both at startup (to answer
// `takeInitialUri`) and by the second instance (to forward it).
std::wstring InitialUriFromProcessCommandLine();

// Best-effort hand-off to the instance that is already running: activates its
// main window and delivers |payload| (a URI, possibly empty) over WM_COPYDATA.
// Retries for a couple of seconds because the first instance may still be
// building its window. False when no instance answered within that budget.
bool ForwardToRunningInstance(const std::wstring& payload);

}  // namespace desktop
}  // namespace mconnect

#endif  // RUNNER_DESKTOP_SINGLE_INSTANCE_H_
