#ifndef RUNNER_DESKTOP_DESKTOP_INTEGRATION_CHANNEL_H_
#define RUNNER_DESKTOP_DESKTOP_INTEGRATION_CHANNEL_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <vector>

#include "smtc_session.h"
#include "window_state_store.h"

namespace mconnect {
namespace desktop {

// Tray icon callback message (WM_CONTEXTMENU / NIN_SELECT arrive in lParam).
// WM_APP + n keeps it clear of the layered lyrics windows, which own WM_APP + 1
// and up in their own procedures.
constexpr UINT kTrayCallbackMessage = WM_APP + 0x4D;

// Posted by the SMTC event handlers so the session is never touched from inside
// one of its own callbacks: wParam carries a SmtcRequest::Action, lParam the
// seek target in milliseconds.
constexpr UINT kSmtcRequestMessage = WM_APP + 0x4E;

// `com.mconnect.mconnect/desktop_integration` — the Windows half of
// docs/desktop-lyrics-protocol.md section 4.3.
//
// Owns everything the runner has to do besides drawing lyrics: the System Media
// Transport Controls session (media flyout, media keys), the notification-area
// icon and its menu, window geometry persistence, close-to-tray behaviour,
// global hotkeys, single-instance hand-off, prevent-sleep, the Accent colour and
// free disk space.
//
// Every method answers `false` (or null) instead of throwing, and every native
// failure that the user should be able to see is reported as an event
// (`smtcUnavailable`, `trayReady`) rather than as a platform exception, because
// a missing tray icon must not stop the music.
class DesktopIntegrationChannel {
 public:
  DesktopIntegrationChannel(HWND window,
                            flutter::BinaryMessenger* messenger,
                            std::wstring initial_uri);
  ~DesktopIntegrationChannel();

  DesktopIntegrationChannel(const DesktopIntegrationChannel&) = delete;
  DesktopIntegrationChannel& operator=(const DesktopIntegrationChannel&) = delete;

  // Window message hook for the main window. Returns true when |message| was
  // consumed and |result| holds the message result.
  bool HandleWindowMessage(HWND window,
                           UINT message,
                           WPARAM wparam,
                           LPARAM lparam,
                           LRESULT* result);

  // WM_CLOSE. Returns true when the close was handled and the window must not
  // be destroyed: either it went into the tray, or - when close-to-tray is on
  // but no tray icon exists - it was minimized to the taskbar instead.
  // Returns false when the app should exit (close-to-tray off, or an explicit
  // "退出 Mconnect" from the tray menu).
  bool HandleCloseRequest();

  // Brings the main window back from the tray or the taskbar.
  void ShowMainWindow();

  // Another instance forwarded its command line over WM_COPYDATA.
  void HandleForwardedPayload(const std::wstring& payload);

 private:
  enum MenuCommand : UINT {
    kMenuShow = 0x4D01,
    kMenuPlayPause = 0x4D02,
    kMenuPrevious = 0x4D03,
    kMenuNext = 0x4D04,
    kMenuFloatingLyrics = 0x4D05,
    kMenuTaskbarLyrics = 0x4D06,
    kMenuExit = 0x4D07,
  };

  struct HotkeyBinding {
    int id = 0;
    UINT modifiers = 0;
    UINT virtual_key = 0;
    std::string action;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool Initialize();
  // A plain hidden top-level window that owns the tray icon.
  //
  // The icon used to be registered against the Flutter window and the shell
  // refused it (three different flag sets all failed while an ordinary window
  // in the same session succeeded). Giving the tray its own window also keeps
  // the icon alive across a Flutter view rebuild.
  bool EnsureTrayHost();
  bool AddTrayIcon();
  void RemoveTrayIcon();
  void UpdateTrayTooltip();
  void ShowTrayMenu(POINT point);
  void ShowTrayBalloon(const std::wstring& title, const std::wstring& text);
  void HandleTrayMessage(WPARAM wparam, LPARAM lparam);
  void HandleMenuCommand(UINT command);
  void RequestQuit();

  bool ApplyHotkeys(bool enabled,
                    const std::string& lyrics_toggle,
                    const std::string& play_pause);
  void UnregisterHotkeys();
  bool HandleHotkey(int id);

  void ApplyExecutionState();

  void EmitEvent(const std::string& name, flutter::EncodableMap arguments);
  void EmitTrayCommand(const std::string& action);
  void DeliverSmtcRequest(int action, int64_t position_ms);

  WindowState CurrentWindowState() const;
  bool SaveWindowStateNow(bool emit_event);

  HWND window_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  SmtcSession smtc_;

  // Startup URI until Dart takes it, and the last URI forwarded by a second
  // instance. Single slot on purpose: a deep link that arrives before Dart asks
  // is more useful than a queue of stale ones.
  std::wstring pending_uri_;

  bool initialized_ = false;
  bool tray_icon_added_ = false;
  // GetLastError() from the last NIM_ADD that failed, 0 when there is none.
  // Reported through getRuntimeStatus and minimizedInsteadOfTray so a tray the
  // shell never accepted is something the user can read instead of guess at.
  int tray_error_ = 0;
  // Per-process icon id. A fixed id collides with the shell's leftover entry
  // when an earlier run was killed instead of shutting down (the shell keeps
  // answering ERROR_ALREADY_EXISTS for that window+id), so every run owns its
  // own slot and deletes it before adding.
  UINT tray_icon_id_ = 0;
  // True when the icon was accepted through the GUID path, which changes how
  // every later NIM_MODIFY / NIM_DELETE has to address it.
  bool tray_guid_mode_ = false;
  UINT taskbar_created_message_ = 0;
  int tray_retry_attempts_ = 0;
  // Backs off from 1s to 30s instead of giving up after ten tries: the shell
  // can be busy for a while at logon, and a late icon is far better than none.
  UINT tray_retry_delay_ms_ = 1000;
  HWND tray_host_ = nullptr;
  // "Close means hide" is on but there is no icon to hide into. Kept as state so
  // the status card can explain it after the fact.
  bool tray_unavailable_ = false;

  bool playing_ = false;
  bool has_song_ = false;
  bool floating_lyrics_ = false;
  bool taskbar_lyrics_ = false;
  bool liked_ = false;
  std::wstring tray_tooltip_ = L"Mconnect";
  bool minimize_to_tray_ = true;
  bool first_run_hint_ = true;
  bool close_hint_shown_ = false;
  // Armed again every time close-to-tray is turned back on, so the balloon
  // explains the tray icon the first time it matters - not only on first run.
  bool hint_armed_ = true;
  // "记住窗口位置". When off, nothing writes geometry to disk, including the
  // save that would otherwise run while closing.
  bool remember_window_state_ = true;
  bool force_quit_ = false;
  bool prevent_sleep_ = false;

  std::vector<HotkeyBinding> hotkeys_;
};

}  // namespace desktop
}  // namespace mconnect

#endif  // RUNNER_DESKTOP_DESKTOP_INTEGRATION_CHANNEL_H_