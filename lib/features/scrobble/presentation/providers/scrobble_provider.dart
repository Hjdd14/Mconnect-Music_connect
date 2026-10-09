import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/scrobble_config.dart';
import '../../data/scrobble_coordinator.dart';

/// The wiring layer for scrobbling: preferences, secrets, the coordinator, and a
/// single read-only snapshot for the settings UI.
///
/// Three deliberate choices worth knowing before editing:
///
/// * **The secret setters live on [scrobbleSecretsProvider], not on the
///   preferences notifier.** The two halves are loaded from different places (Hive
///   vs the platform keystore) and the credential input fields must rebuild when
///   the *secrets* arrive — keeping them in one notifier would have made one of
///   the two halves a second source of truth.
/// * **Scrobbling is off by default and a disabled preference builds no backend
///   at all.** Sending listening history to a third party is the user's decision,
///   and "off" must mean no object exists that could send anything.
/// * **`pendingCount` is cached, not async.** A `Provider` cannot await, so the
///   count lives in [ScrobbleStatusNotifier] and is refreshed explicitly (after a
///   drain, after enqueueing, when the settings page mounts).

/// Where the non-secret half is persisted. Overridden in tests.
final scrobblePreferenceStoreProvider = Provider<ScrobblePreferenceStore>(
  (ref) => const HiveScrobblePreferenceStore(),
);

/// Where the secret half is persisted. Overridden in tests so no test touches the
/// platform keystore (it throws on a device whose keystore was invalidated, which
/// would make tests flaky for reasons unrelated to scrobbling).
final scrobbleSecretStoreProvider = Provider<ScrobbleSecretStore>(
  (ref) => const SecureScrobbleSecretStore(),
);

final scrobbleCredentialsProvider = Provider<ScrobbleCredentials>(
  (ref) => ScrobbleCredentials(ref.watch(scrobbleSecretStoreProvider)),
);

/// A read-only snapshot for the settings page.
class ScrobbleStatus {
  const ScrobbleStatus({
    required this.preferences,
    required this.hasCredentials,
    required this.needsReauth,
    required this.pendingCount,
    this.lastError,
  });

  final ScrobblePreferences preferences;

  /// Whether the *current* service has a complete credential set. False is a
  /// normal state ("未配置"), not an error.
  final bool hasCredentials;

  final bool needsReauth;
  final int pendingCount;
  final String? lastError;

  bool get enabled => preferences.enabled;
  ScrobbleService get service => preferences.service;

  ScrobbleStatus copyWith({
    ScrobblePreferences? preferences,
    bool? hasCredentials,
    bool? needsReauth,
    int? pendingCount,
    String? Function()? lastError,
  }) {
    return ScrobbleStatus(
      preferences: preferences ?? this.preferences,
      hasCredentials: hasCredentials ?? this.hasCredentials,
      needsReauth: needsReauth ?? this.needsReauth,
      pendingCount: pendingCount ?? this.pendingCount,
      lastError: lastError != null ? lastError() : this.lastError,
    );
  }
}

/// The non-secret half: enabled / which service / custom base URL.
///
/// The initial state is the documented default (disabled) so the first frame is
/// already correct; the stored value replaces it asynchronously.
class ScrobblePreferencesNotifier extends StateNotifier<ScrobblePreferences> {
  ScrobblePreferencesNotifier(this._ref, {ScrobblePreferences? initial})
      : super(initial ?? const ScrobblePreferences()) {
    if (initial == null) unawaited(_load());
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final stored = await _ref.read(scrobblePreferenceStoreProvider).load();
      if (!mounted) return;
      state = stored;
    } catch (_) {
      // A preferences read failure keeps the documented default (off) rather than
      // silently enabling something the user may not have chosen.
    }
  }

  Future<void> _save(ScrobblePreferences next) async {
    state = next;
    try {
      await _ref.read(scrobblePreferenceStoreProvider).save(next);
    } catch (_) {
      // In-memory state already reflects the user's action; a failed persist must
      // not throw at the UI. The value will be re-read (and possibly lost) on the
      // next launch, which is the honest outcome.
    }
  }

  Future<void> setEnabled(bool enabled) =>
      _save(state.copyWith(enabled: enabled));

  Future<void> setService(ScrobbleService service) => _save(
    state.copyWith(
      service: service,
      // The custom base URL belongs to the service it was typed for. Keeping it
      // across a service switch would send, say, Last.fm requests to a Maloja
      // instance — the field is only ever shown for a self-hosted instance, but
      // the model must not be able to leak it.
      customBaseUrl: () => null,
    ),
  );

  /// Sets (or clears, with null/empty) the custom base URL.
  ///
  /// Returns false and keeps the previous value when the URL is not a usable
  /// http(s) endpoint, so the page can show the error next to the field instead
  /// of persisting something that would make every request fail.
  Future<bool> setCustomBaseUrl(String? url) async {
    final trimmed = url?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      if (!isValidScrobbleBaseUrl(trimmed)) return false;
    }
    await _save(
      state.copyWith(
        customBaseUrl: () =>
            (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      ),
    );
    return true;
  }

  /// ⚠️ `backendLastError` and `testConnection()` used to live here and did
  /// `_ref.read(scrobbleBackendProvider)`. That is a **cycle**: this notifier IS
  /// `scrobblePreferencesProvider`, while `scrobbleBackendProvider` does
  /// `ref.watch(scrobblePreferencesProvider)`. Reading the backend from here means
  /// "the provider I am building watches me back", and Riverpod throws
  /// `CircularDependencyError`.
  ///
  /// Device log, 2026-10-09 (settings page red screen):
  /// ```
  /// #3 ScrobblePreferencesNotifier.backendLastError  (scrobble_provider.dart:165)
  /// #4 RiverpodScrobbleSettingsController._backendLastError
  /// #5 RiverpodScrobbleSettingsController.view
  /// #6 _ScrobbleSettingsSectionState.build
  /// ```
  /// Both operations now hang off the transport layer instead — see
  /// [ScrobbleStatusNotifier.backendLastError] / `.testConnection()`, which read
  /// the coordinator. Do not move them back: an earlier attempt only deferred the
  /// *call* into a closure, which does not remove the edge.
}

final scrobblePreferencesProvider =
    StateNotifierProvider<ScrobblePreferencesNotifier, ScrobblePreferences>((
      ref,
    ) {
      return ScrobblePreferencesNotifier(ref);
    });

/// The secret half: api key / secret / session key / token for the current
/// service, loaded from the platform keystore and written back on change.
class ScrobbleSecretsNotifier extends StateNotifier<ScrobbleSecrets> {
  ScrobbleSecretsNotifier(this._ref, {ScrobbleSecrets? initial})
      : super(initial ?? const ScrobbleSecrets()) {
    if (initial == null) unawaited(_load());
  }

  final Ref _ref;

  ScrobbleService get _service => _ref.read(scrobblePreferencesProvider).service;

  Future<void> _load() async {
    try {
      final credentials = _ref.read(scrobbleCredentialsProvider);
      final loaded = await credentials.load(_service);
      if (!mounted) return;
      state = loaded;
    } catch (_) {
      // Unreadable keystore ⇒ treat as "not configured" rather than crashing the
      // settings page; the user re-enters the credential.
    }
  }

  /// Reloads for [service] (used when the user switches service: the fields must
  /// show that service's stored credential, and switching must NOT clear the
  /// other service's).
  Future<void> loadFor(ScrobbleService service) async {
    final credentials = _ref.read(scrobbleCredentialsProvider);
    final loaded = await credentials.load(service);
    if (!mounted) return;
    state = loaded;
  }

  Future<void> _save(ScrobbleSecrets next) async {
    state = next;
    try {
      await _ref
          .read(scrobbleCredentialsProvider)
          .save(_service, next);
    } catch (_) {
      // Same reasoning as the preferences half: the field already shows what the
      // user typed; a keystore failure must not throw at the UI.
    }
  }

  Future<void> setApiKey(String value) =>
      _save(state.copyWith(apiKey: value));
  Future<void> setApiSecret(String value) =>
      _save(state.copyWith(apiSecret: value));
  Future<void> setSessionKey(String value) =>
      _save(state.copyWith(sessionKey: value));
  Future<void> setToken(String value) => _save(state.copyWith(token: value));

  /// Used when a service rejects the credentials: forgets them so the app stops
  /// retrying a dead token.
  Future<void> clear() async {
    try {
      await _ref.read(scrobbleCredentialsProvider).clear(_service);
    } catch (_) {}
    if (!mounted) return;
    state = const ScrobbleSecrets();
  }
}

final scrobbleSecretsProvider =
    StateNotifierProvider<ScrobbleSecretsNotifier, ScrobbleSecrets>((ref) {
      return ScrobbleSecretsNotifier(ref);
    });

/// Builds the transport for the current configuration, or null when it cannot
/// run (disabled, incomplete credentials, unusable base URL).
///
/// Rebuilt whenever the preferences or the secrets change, which is what makes
/// "switch service" and "paste a token" take effect without a restart.
final scrobbleBackendProvider = Provider((ref) {
  final preferences = ref.watch(scrobblePreferencesProvider);
  final secrets = ref.watch(scrobbleSecretsProvider);
  if (!preferences.enabled) return null;
  return buildScrobbleBackend(
    service: preferences.service,
    secrets: secrets,
    preferences: preferences,
  );
});

/// The serial pump. Recreated when the configuration changes; the previous
/// instance is stopped on dispose so two pumps can never run at once.
final scrobbleCoordinatorProvider = Provider<ScrobbleCoordinator>((ref) {
  final preferences = ref.watch(scrobblePreferencesProvider);
  final backend = ref.watch(scrobbleBackendProvider);
  final coordinator = ScrobbleCoordinator(
    queue: database.scrobbleQueueDao,
    // A closure over the *current* backend: `ref.watch` above rebuilds this
    // provider when the backend changes, and the old instance is disposed.
    backendProvider: () => preferences.enabled ? backend : null,
  );
  ref.onDispose(coordinator.stop);
  if (preferences.enabled && backend != null) {
    // The pump must not block the first frame: it is a background concern.
    unawaited(coordinator.start());
  }
  return coordinator;
});

/// The cached status snapshot the settings page watches.
///
/// **Deliberately has no build-time side effects.** An earlier version called
/// [refresh] from the constructor and `ref.listen`ed to the two halves here; that
/// made building this provider reach the coordinator (→ backend → preferences and
/// secrets) *during a build*, and a widget that watched both this and the
/// settings controller hit `CircularDependencyError`. The refresh is now driven
/// by the page (`initState`) and after each action, which is where it belongs.
class ScrobbleStatusNotifier extends StateNotifier<ScrobbleStatus> {
  ScrobbleStatusNotifier(this._ref)
      : super(
          ScrobbleStatus(
            preferences: const ScrobblePreferences(),
            hasCredentials: false,
            needsReauth: false,
            pendingCount: 0,
          ),
        );

  final Ref _ref;

  /// Re-reads everything that is not already reactive. Cheap enough to call when
  /// the settings page mounts and after a drain.
  ///
  /// The whole body is guarded: this runs from the constructor (so it executes
  /// whenever the settings page is pumped, including in widget tests) and it
  /// touches the database. A widget test has no `path_provider`, so an unguarded
  /// read here would turn "SettingsPage renders" into a setup failure. Falling
  /// back to a zero count is the honest outcome — the count is decoration, the
  /// credentials are not.
  Future<void> refresh() async {
    try {
      final preferences = _ref.read(scrobblePreferencesProvider);
      final secrets = _ref.read(scrobbleSecretsProvider);
      final coordinator = _ref.read(scrobbleCoordinatorProvider);
      int pending = 0;
      try {
        pending = await coordinator.pendingCount();
      } catch (_) {
        // A database hiccup must not blank the settings page.
      }
      if (!mounted) return;
      state = ScrobbleStatus(
        preferences: preferences,
        hasCredentials: secrets.isCompleteFor(preferences.service),
        needsReauth: coordinator.needsReauth,
        pendingCount: pending,
        lastError: coordinator.lastError,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(pendingCount: 0, needsReauth: false);
    }
  }

  /// The transport's own last message, for the settings page to display.
  ///
  /// Lives on the STATUS notifier, not on the preferences one: reading
  /// `scrobbleBackendProvider` from `ScrobblePreferencesNotifier` created a
  /// `CircularDependencyError` (see the note on that class). The coordinator
  /// already owns this value, and reading the coordinator is a one-way edge.
  String? get backendLastError {
    try {
      return _ref.read(scrobbleCoordinatorProvider).lastError;
    } catch (_) {
      return state.lastError;
    }
  }

  /// A zero-side-effect probe: `user.getInfo` without a `user` parameter returns
  /// the account the session belongs to, and creates nothing.
  ///
  /// 【需联网验证】the exact endpoint for an already-authorised session is not
  /// documented — the spec's fallback is `user.getRecentTracks&limit=1`.
  Future<bool> testConnection() async {
    final backend = _ref.read(scrobbleBackendProvider);
    if (backend == null) return false;
    return backend.validate();
  }

  /// "立即补交": drains once and refreshes the count.
  Future<ScrobbleDrainOutcome?> drainNow() async {
    final coordinator = _ref.read(scrobbleCoordinatorProvider);
    ScrobbleDrainOutcome? outcome;    try {
      outcome = await coordinator.drainOnce();
    } catch (_) {
      outcome = null;
    }
    await refresh();
    return outcome;
  }
}

final scrobbleStatusProvider =
    StateNotifierProvider<ScrobbleStatusNotifier, ScrobbleStatus>((ref) {
      // No `ref.listen` here on purpose — see the class doc: a subscription
      // created inside this build put the status provider in a cycle with the
      // settings controller. The status embeds the preferences, so whoever
      // changes a preference refreshes the status explicitly.
      return ScrobbleStatusNotifier(ref);
    });

/// Where the user goes to authorise this client.
///
/// Last.fm and Libre.fm have a dedicated page that takes the api key;
/// ListenBrainz's token lives on the user's profile page; a self-hosted Maloja has
/// no standard page, so its instance root is the best available target.
///
/// 【需联网验证】only the Last.fm shape is documented; the other three are the
/// best-known targets and are listed in the specs doc's unverified section.
Uri? scrobbleAuthorizeUrl({
  required ScrobbleService service,
  required String apiKey,
  required ScrobblePreferences preferences,
}) {
  switch (service) {
    case ScrobbleService.lastfm:
      return Uri.parse(
        'https://www.last.fm/api/auth/?api_key=${Uri.encodeQueryComponent(apiKey)}',
      );
    case ScrobbleService.librefm:
      return Uri.parse(
        'https://libre.fm/api/auth/?api_key=${Uri.encodeQueryComponent(apiKey)}',
      );
    case ScrobbleService.listenbrainz:
      return Uri.parse('https://listenbrainz.org/profile/');
    case ScrobbleService.maloja:
      final base = preferences.baseUrl;
      return base.isEmpty ? null : Uri.tryParse(base);
  }
}
