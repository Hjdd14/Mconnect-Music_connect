#ifndef RUNNER_DESKTOP_SMTC_SESSION_H_
#define RUNNER_DESKTOP_SMTC_SESSION_H_

#include <windows.h>

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

namespace mconnect {
namespace desktop {

// One request the user made through the Windows media flyout, a keyboard media
// key, or a hardware transport control.
struct SmtcRequest {
  enum class Action {
    kPlay,
    kPause,
    kStop,
    kNext,
    kPrevious,
    kSeek,
  };

  Action action = Action::kPlay;
  int64_t position_ms = 0;  // kSeek only
};

// Thin wrapper around the System Media Transport Controls session that Windows
// shows in its media flyout, on the lock screen and on media keys.
//
// Everything here is best-effort by design: the session is obtained through
// ISystemMediaTransportControlsInterop::GetForWindow, which needs the C++/WinRT
// projection headers (shipped inside the Windows SDK) and a desktop session
// that allows it. When any of that is missing, available() stays false, the
// runner reports `smtcUnavailable`, and playback keeps working — the tray icon
// and the in-app controls are unaffected.
class SmtcSession {
 public:
  using RequestHandler = std::function<void(const SmtcRequest&)>;

  SmtcSession();
  ~SmtcSession();

  SmtcSession(const SmtcSession&) = delete;
  SmtcSession& operator=(const SmtcSession&) = delete;

  // Called on the thread that owns the window (the platform thread). Post the
  // request to a window message instead of calling back into SMTC from here:
  // the projection marshals its events onto the apartment thread and touching
  // the controls from inside a handler is documented to deadlock.
  void SetRequestHandler(RequestHandler handler);

  bool Initialize(HWND window);
  void Teardown();
  bool available() const;

  void SetMetadata(const std::wstring& title,
                   const std::wstring& artist,
                   const std::wstring& album,
                   int64_t duration_ms);
  // 0 playing, 1 paused, 2 stopped (the wire words of the Dart protocol).
  void SetPlaybackStatus(int status);
  void SetTimeline(int64_t position_ms, int64_t duration_ms);
  void SetButtons(bool has_song, bool playing);

 private:
  class Impl;

  void Deliver(const SmtcRequest& request);

  std::unique_ptr<Impl> impl_;
};

}  // namespace desktop
}  // namespace mconnect

#endif  // RUNNER_DESKTOP_SMTC_SESSION_H_
