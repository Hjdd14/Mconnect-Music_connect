#include "smtc_session.h"

#if defined(MCONNECT_HAS_CPPWINRT)
#include <systemmediatransportcontrolsinterop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#endif

namespace mconnect {
namespace desktop {

#if defined(MCONNECT_HAS_CPPWINRT)
namespace {

using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::PlaybackPositionChangeRequestedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;

winrt::Windows::Foundation::TimeSpan ToTimeSpan(int64_t milliseconds) {
  if (milliseconds < 0) {
    milliseconds = 0;
  }
  // TimeSpan is a 100 ns tick count.
  return winrt::Windows::Foundation::TimeSpan{milliseconds * 10000};
}

int64_t ToMilliseconds(winrt::Windows::Foundation::TimeSpan span) {
  return span.count() / 10000;
}

}  // namespace
#endif

class SmtcSession::Impl {
 public:
  HWND window = nullptr;
  bool available = false;
  // Last duration the protocol sent, so a timeline push without one (or a
  // metadata refresh before the first tick) still shows a full-length bar.
  int64_t duration_ms = 0;
  // Set from the moment Teardown starts: an event that is already queued on the
  // apartment thread must not reach a half-torn-down session.
  bool revoked = false;
  SmtcSession::RequestHandler handler;

#if defined(MCONNECT_HAS_CPPWINRT)
  SystemMediaTransportControls controls{nullptr};
  winrt::event_token button_token{};
  bool has_button_token = false;
  winrt::event_token position_token{};
  bool has_position_token = false;
#endif
};

SmtcSession::SmtcSession() : impl_(std::make_unique<Impl>()) {}

SmtcSession::~SmtcSession() {
  Teardown();
}

void SmtcSession::SetRequestHandler(RequestHandler handler) {
  if (impl_ == nullptr) {
    return;
  }
  impl_->handler = std::move(handler);
}

bool SmtcSession::available() const {
  return impl_ != nullptr && impl_->available;
}

void SmtcSession::Deliver(const SmtcRequest& request) {
  if (impl_ == nullptr || impl_->revoked || !impl_->handler) {
    return;
  }
  impl_->handler(request);
}

bool SmtcSession::Initialize(HWND window) {
  if (impl_ == nullptr) {
    return false;
  }
  impl_->window = window;
  if (impl_->available) {
    return true;
  }
#if defined(MCONNECT_HAS_CPPWINRT)
  if (window == nullptr) {
    return false;
  }
  try {
    // GetForWindow is the only supported way for a Win32 app to own an SMTC
    // session; the class itself is not activatable.
    auto interop = winrt::get_activation_factory<
        SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    if (!interop) {
      return false;
    }
    SystemMediaTransportControls controls{nullptr};
    winrt::check_hresult(interop->GetForWindow(
        window,
        winrt::guid_of<winrt::Windows::Media::ISystemMediaTransportControls>(),
        winrt::put_abi(controls)));
    if (!controls) {
      return false;
    }

    impl_->controls = controls;
    impl_->revoked = false;
    controls.IsEnabled(true);

    impl_->button_token = controls.ButtonPressed(
        [this](SystemMediaTransportControls const&,
               SystemMediaTransportControlsButtonPressedEventArgs const& args) {
          SmtcRequest request;
          switch (args.Button()) {
            case SystemMediaTransportControlsButton::Play:
              request.action = SmtcRequest::Action::kPlay;
              break;
            case SystemMediaTransportControlsButton::Pause:
              request.action = SmtcRequest::Action::kPause;
              break;
            case SystemMediaTransportControlsButton::Stop:
              request.action = SmtcRequest::Action::kStop;
              break;
            case SystemMediaTransportControlsButton::Next:
              request.action = SmtcRequest::Action::kNext;
              break;
            case SystemMediaTransportControlsButton::Previous:
              request.action = SmtcRequest::Action::kPrevious;
              break;
            default:
              // Record / fast forward / rewind / channel keys are not part of
              // the app's vocabulary; ignore them rather than guessing.
              return;
          }
          Deliver(request);
        });
    impl_->has_button_token = true;

    impl_->position_token = controls.PlaybackPositionChangeRequested(
        [this](SystemMediaTransportControls const&,
               PlaybackPositionChangeRequestedEventArgs const& args) {
          SmtcRequest request;
          request.action = SmtcRequest::Action::kSeek;
          request.position_ms =
              ToMilliseconds(args.RequestedPlaybackPosition());
          Deliver(request);
        });
    impl_->has_position_token = true;

    impl_->available = true;
    return true;
  } catch (...) {
    impl_->available = false;
    impl_->controls = nullptr;
    impl_->has_button_token = false;
    impl_->has_position_token = false;
    return false;
  }
#else
  return false;
#endif
}

void SmtcSession::Teardown() {
  if (impl_ == nullptr) {
    return;
  }
  impl_->handler = nullptr;
  impl_->revoked = true;
#if defined(MCONNECT_HAS_CPPWINRT)
  try {
    if (impl_->controls) {
      if (impl_->has_button_token) {
        impl_->controls.ButtonPressed(impl_->button_token);
        impl_->has_button_token = false;
      }
      if (impl_->has_position_token) {
        impl_->controls.PlaybackPositionChangeRequested(impl_->position_token);
        impl_->has_position_token = false;
      }
      // Clears the flyout entry instead of leaving a dead session behind.
      impl_->controls.IsEnabled(false);
    }
  } catch (...) {
    // Releasing the session is best-effort; the process is going away anyway.
  }
  impl_->controls = nullptr;
#endif
  impl_->available = false;
}

void SmtcSession::SetMetadata(const std::wstring& title,
                              const std::wstring& artist,
                              const std::wstring& album,
                              int64_t duration_ms) {
  if (impl_ == nullptr || !impl_->available) {
    return;
  }
  // The cover art is deliberately not pushed yet (see the protocol note): a
  // thumbnail needs the image downloaded and decoded, which is a follow-up.
  if (duration_ms > 0) {
    impl_->duration_ms = duration_ms;
  }
#if defined(MCONNECT_HAS_CPPWINRT)
  try {
    auto updater = impl_->controls.DisplayUpdater();
    updater.Type(MediaPlaybackType::Music);
    auto music = updater.MusicProperties();
    music.Title(winrt::hstring(title));
    music.Artist(winrt::hstring(artist));
    music.AlbumTitle(winrt::hstring(album));
    updater.Update();
  } catch (...) {
    // A metadata push that fails must never take playback down: the flyout
    // simply keeps showing the previous item.
  }
#else
  (void)title;
  (void)artist;
  (void)album;
#endif
}

void SmtcSession::SetPlaybackStatus(int status) {
  if (impl_ == nullptr || !impl_->available) {
    return;
  }
#if defined(MCONNECT_HAS_CPPWINRT)
  try {
    MediaPlaybackStatus playback_status = MediaPlaybackStatus::Stopped;
    if (status == 0) {
      playback_status = MediaPlaybackStatus::Playing;
    } else if (status == 1) {
      playback_status = MediaPlaybackStatus::Paused;
    }
    impl_->controls.PlaybackStatus(playback_status);
  } catch (...) {
  }
#else
  (void)status;
#endif
}

void SmtcSession::SetTimeline(int64_t position_ms, int64_t duration_ms) {
  if (impl_ == nullptr || !impl_->available) {
    return;
  }
#if defined(MCONNECT_HAS_CPPWINRT)
  try {
    const int64_t total = duration_ms > 0 ? duration_ms : impl_->duration_ms;
    if (duration_ms > 0) {
      impl_->duration_ms = duration_ms;
    }
    SystemMediaTransportControlsTimelineProperties timeline;
    timeline.StartTime(ToTimeSpan(0));
    timeline.MinSeekTime(ToTimeSpan(0));
    timeline.MaxSeekTime(ToTimeSpan(total));
    timeline.EndTime(ToTimeSpan(total));
    // A position past the end (a stale tick racing a track change) would be
    // rejected by the shell and freeze the flyout's progress bar.
    const int64_t clamped =
        total > 0 && position_ms > total ? total : position_ms;
    timeline.Position(ToTimeSpan(clamped));
    impl_->controls.UpdateTimelineProperties(timeline);
  } catch (...) {
  }
#else
  (void)position_ms;
  (void)duration_ms;
#endif
}

void SmtcSession::SetButtons(bool has_song, bool playing) {
  if (impl_ == nullptr || !impl_->available) {
    return;
  }
#if defined(MCONNECT_HAS_CPPWINRT)
  try {
    impl_->controls.IsPlayEnabled(has_song && !playing);
    impl_->controls.IsPauseEnabled(has_song && playing);
    impl_->controls.IsStopEnabled(has_song);
    impl_->controls.IsNextEnabled(has_song);
    impl_->controls.IsPreviousEnabled(has_song);
  } catch (...) {
  }
#else
  (void)has_song;
  (void)playing;
#endif
}

}  // namespace desktop
}  // namespace mconnect
