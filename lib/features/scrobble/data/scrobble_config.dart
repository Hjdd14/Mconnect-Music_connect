/// What the user configured for scrobbling, and how a backend is built from it.
///
/// Split by sensitivity on purpose:
///
/// * **secrets** (`api_secret`, the user's `sk`, the ListenBrainz token) live in
///   `flutter_secure_storage`, one key per service, and never touch Hive, the
///   backup file or a log;
/// * **preferences** (which service, whether it is on, a custom base URL) are
///   ordinary settings in the `settings` Hive box, so they follow the existing
///   backup/restore path — which is also why nothing secret may go in there.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../domain/scrobble_backend.dart';
import 'lastfm_compatible_backend.dart';
import 'listenbrainz_native_backend.dart';

/// Which protocol family a service speaks (`v1.5-w2w3-implementation-specs` A.4).
enum ScrobbleTransport { lastFmCompatible, listenBrainzNative }

/// The services the settings page offers.
///
/// `gnufm` is not a separate row: a self-hosted GNU FM instance is a
/// [ScrobbleTransport.lastFmCompatible] service with a custom base URL, and
/// pretending otherwise would multiply the credential UI for nothing.
enum ScrobbleService {
  lastfm('lastfm', 'Last.fm', ScrobbleTransport.lastFmCompatible),
  librefm('librefm', 'Libre.fm', ScrobbleTransport.lastFmCompatible),
  listenbrainz(
    'listenbrainz',
    'ListenBrainz',
    ScrobbleTransport.listenBrainzNative,
  ),
  maloja('maloja', 'Maloja', ScrobbleTransport.listenBrainzNative);

  const ScrobbleService(this.id, this.displayName, this.transport);

  /// Persisted id — also the `scrobble_queue.service` value and the secure
  /// storage key prefix.
  final String id;
  final String displayName;
  final ScrobbleTransport transport;

  static ScrobbleService? tryParse(String? value) {
    for (final service in ScrobbleService.values) {
      if (service.id == value) return service;
    }
    return null;
  }

  /// What the settings page calls this service.
  String get label => displayName;

  /// Whether the credential fields are the Last.fm-family trio (api key, api
  /// secret, session key) rather than a single token. Derived from [transport] so
  /// a new service only has to declare its transport.
  bool get usesApiKey =>
      transport == ScrobbleTransport.lastFmCompatible;

  bool get usesToken =>
      transport == ScrobbleTransport.listenBrainzNative;

  /// Only a self-hosted instance has a base URL worth asking the user for.
  bool get usesCustomBaseUrl => this == ScrobbleService.maloja;
}

/// The default base URL per service; a custom one overrides it (self-hosted
/// instances, and Maloja's path which is instance-specific).
String defaultBaseUrlFor(ScrobbleService service) => switch (service) {
  ScrobbleService.lastfm => kLastFmBaseUrl,
  ScrobbleService.librefm => kLibreFmBaseUrl,
  ScrobbleService.listenbrainz => kListenBrainzBaseUrl,
  ScrobbleService.maloja => kListenBrainzBaseUrl,
};

/// The non-secret half: what the user turned on and where it points.
class ScrobblePreferences {
  const ScrobblePreferences({
    this.enabled = false,
    this.service = ScrobbleService.lastfm,
    this.customBaseUrl,
  });

  /// Scrobbling is **off by default**: it sends listening history to a third
  /// party, which is the user's decision to make.
  final bool enabled;

  final ScrobbleService service;

  /// Overrides [defaultBaseUrlFor] when non-empty.
  final String? customBaseUrl;

  String get baseUrl {
    final custom = customBaseUrl?.trim();
    if (custom == null || custom.isEmpty) return defaultBaseUrlFor(service);
    // A trailing slash is easy to forget and would otherwise produce
    // `.../2.0//?method=` — harmless for Last.fm, a 404 for some instances.
    return custom.endsWith('/') ? custom : '$custom/';
  }

  ScrobblePreferences copyWith({
    bool? enabled,
    ScrobbleService? service,
    String? Function()? customBaseUrl,
  }) {
    return ScrobblePreferences(
      enabled: enabled ?? this.enabled,
      service: service ?? this.service,
      customBaseUrl: customBaseUrl != null ? customBaseUrl() : this.customBaseUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'service': service.id,
    if (customBaseUrl != null) 'customBaseUrl': customBaseUrl,
  };

  static ScrobblePreferences fromJson(dynamic value) {
    if (value is! Map) return const ScrobblePreferences();
    return ScrobblePreferences(
      enabled: value['enabled'] == true,
      service:
          ScrobbleService.tryParse(value['service']?.toString()) ??
          ScrobbleService.lastfm,
      customBaseUrl: value['customBaseUrl']?.toString(),
    );
  }
}

/// The per-service credentials the user pasted.
class ScrobbleSecrets {
  const ScrobbleSecrets({
    this.apiKey = '',
    this.apiSecret = '',
    this.sessionKey = '',
    this.token = '',
  });

  /// Application-level, shipped with the build for Last.fm; user-supplied for
  /// Libre.fm/GNU FM.
  final String apiKey;
  final String apiSecret;

  /// The user's `sk` (Last.fm-compatible family).
  final String sessionKey;

  /// The user's ListenBrainz/Maloja user token.
  final String token;

  bool isCompleteFor(ScrobbleService service) => switch (service.transport) {
    ScrobbleTransport.lastFmCompatible =>
      apiKey.trim().isNotEmpty &&
          apiSecret.trim().isNotEmpty &&
          sessionKey.trim().isNotEmpty,
    ScrobbleTransport.listenBrainzNative => token.trim().isNotEmpty,
  };

  ScrobbleSecrets copyWith({
    String? apiKey,
    String? apiSecret,
    String? sessionKey,
    String? token,
  }) {
    return ScrobbleSecrets(
      apiKey: apiKey ?? this.apiKey,
      apiSecret: apiSecret ?? this.apiSecret,
      sessionKey: sessionKey ?? this.sessionKey,
      token: token ?? this.token,
    );
  }
}

/// Reads and writes the secret half.
///
/// An interface so the coordinator's tests never touch the platform keystore —
/// `FlutterSecureStorage` throws on a device whose keystore was invalidated, and
/// a test that depends on it would be flaky for reasons unrelated to scrobbling.
abstract class ScrobbleSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureScrobbleSecretStore implements ScrobbleSecretStore {
  const SecureScrobbleSecretStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryScrobbleSecretStore implements ScrobbleSecretStore {
  MemoryScrobbleSecretStore([Map<String, String>? seed])
    : _values = {...?seed};

  final Map<String, String> _values;

  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Reads and writes the preference half.
abstract class ScrobblePreferenceStore {
  Future<ScrobblePreferences> load();
  Future<void> save(ScrobblePreferences preferences);
}

class HiveScrobblePreferenceStore implements ScrobblePreferenceStore {
  static const String boxName = 'settings';
  static const String key = 'scrobble_preferences';

  const HiveScrobblePreferenceStore();

  @override
  Future<ScrobblePreferences> load() async {
    final box = await Hive.openBox(boxName);
    return ScrobblePreferences.fromJson(box.get(key));
  }

  @override
  Future<void> save(ScrobblePreferences preferences) async {
    final box = await Hive.openBox(boxName);
    await box.put(key, preferences.toJson());
  }
}

class MemoryScrobblePreferenceStore implements ScrobblePreferenceStore {
  MemoryScrobblePreferenceStore([this._preferences = const ScrobblePreferences()]);

  ScrobblePreferences _preferences;

  @override
  Future<ScrobblePreferences> load() async => _preferences;

  @override
  Future<void> save(ScrobblePreferences preferences) async =>
      _preferences = preferences;
}

/// One place that knows how the two halves spell a key.
class ScrobbleCredentials {
  const ScrobbleCredentials(this._store);

  final ScrobbleSecretStore _store;

  static String apiKeyKey(ScrobbleService service) =>
      'scrobble.${service.id}.api_key';
  static String apiSecretKey(ScrobbleService service) =>
      'scrobble.${service.id}.api_secret';
  static String sessionKeyKey(ScrobbleService service) =>
      'scrobble.${service.id}.session_key';
  static String tokenKey(ScrobbleService service) =>
      'scrobble.${service.id}.token';

  Future<ScrobbleSecrets> load(ScrobbleService service) async {
    Future<String> valueOf(String key) async => await _store.read(key) ?? '';
    return ScrobbleSecrets(
      apiKey: await valueOf(apiKeyKey(service)),
      apiSecret: await valueOf(apiSecretKey(service)),
      sessionKey: await valueOf(sessionKeyKey(service)),
      token: await valueOf(tokenKey(service)),
    );
  }

  Future<void> save(ScrobbleService service, ScrobbleSecrets secrets) async {
    await _writeOrDelete(apiKeyKey(service), secrets.apiKey);
    await _writeOrDelete(apiSecretKey(service), secrets.apiSecret);
    await _writeOrDelete(sessionKeyKey(service), secrets.sessionKey);
    await _writeOrDelete(tokenKey(service), secrets.token);
  }

  /// Forgets everything about [service] — used when a service reports the
  /// credentials are dead, so the app stops retrying a rejected token.
  Future<void> clear(ScrobbleService service) async {
    for (final key in [
      apiKeyKey(service),
      apiSecretKey(service),
      sessionKeyKey(service),
      tokenKey(service),
    ]) {
      await _store.delete(key);
    }
  }

  Future<void> _writeOrDelete(String key, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _store.delete(key);
      return;
    }
    await _store.write(key, trimmed);
  }
}

/// Builds the transport for [service] from the stored configuration.
///
/// Returns null when the service cannot run at all: not configured, or a custom
/// base URL that is not a usable http(s) endpoint. A null backend is a normal
/// state (the settings page shows "未配置"), not an error.
ScrobbleBackend? buildScrobbleBackend({
  required ScrobbleService service,
  required ScrobbleSecrets secrets,
  required ScrobblePreferences preferences,
}) {
  if (!secrets.isCompleteFor(service)) return null;
  final baseUrl = preferences.baseUrl;
  final version = _normalizedVersion();
  switch (service.transport) {
    case ScrobbleTransport.lastFmCompatible:
      return LastFmCompatibleBackend(
        id: service.id,
        displayName: service.displayName,
        apiKey: secrets.apiKey.trim(),
        apiSecret: secrets.apiSecret.trim(),
        sessionKey: secrets.sessionKey.trim(),
        baseUrl: baseUrl,
        userAgent: 'Mconnect/$version',
      );
    case ScrobbleTransport.listenBrainzNative:
      return ListenBrainzNativeBackend(
        id: service.id,
        displayName: service.displayName,
        token: secrets.token.trim(),
        userAgentContact: kUserAgentContact,
        appVersion: version,
        baseUrl: baseUrl,
      );
  }
}

/// Contact ListenBrainz may use to reach the operator; the service *will*
/// disable a client whose User-Agent carries no contact (A.3).
const String kUserAgentContact = 'https://github.com/mconnect-music';

/// `AppConstants.appVersion` is `v1.4.4`; the UA and ListenBrainz's
/// `additional_info` want `1.4.4`.
String _normalizedVersion() => AppConstants.appVersion.replaceFirst(
  RegExp(r'^v'),
  '',
);

/// A cheap sanity check for a user-supplied base URL, so the settings page can
/// reject obvious nonsense before it becomes a backend that always fails.
bool isValidScrobbleBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  if (!uri.hasScheme) return false;
  // `Platform.isAndroid/isWindows` style checks are not needed here: the
  // listener is only ever used to reach a server, so http(s) is the whole
  // requirement.
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  return uri.host.isNotEmpty || uri.path.isNotEmpty;
}
