/// Redaction for anything that leaves the device in a diagnostics export.
///
/// A support bundle is only safe to hand to a developer if it cannot carry the
/// user's credentials with it. The risk is not theoretical: the network layer
/// logs request URLs, and a signed platform request is *nothing but* a query
/// string — `?token=…&mobile=…&sign=…`. NetEase/QQ/酷狗 sessions also travel as
/// cookies (`MUSIC_U`, `qqmusic_key`, `__csrf`), and `DiagnosticsService.record`
/// takes an arbitrary `data` map, so any caller can accidentally log a secret.
///
/// What is redacted:
/// * `Cookie:` / `Set-Cookie:` / `Authorization:` header values;
/// * `Bearer <token>`;
/// * `key=value` / `"key": "value"` / `"key": <unquoted scalar>` pairs whose key
///   looks credential-like — the two key lists are [sensitiveKeys] (matched as a
///   suffix) and [exactSensitiveKeys] (matched whole);
/// * the **entire query string** of any URL (the scheme + host + path stay, so
///   the line is still useful for debugging).
///
/// The redactor is deliberately conservative about *what it keeps*: a query
/// string is replaced wholesale rather than key by key, because a missed
/// parameter is a leaked credential while a lost parameter is just a less
/// convenient log line.
class DiagnosticsRedactor {
  static const placeholder = '<redacted>';

  /// Key names (case-insensitive) whose value must never survive.
  static const Set<String> sensitiveKeys = {
    'token',
    'access_token',
    'accesstoken',
    'refresh_token',
    'refreshtoken',
    'id_token',
    'cookie',
    'set-cookie',
    'authorization',
    'auth',
    'password',
    'passwd',
    'pwd',
    'secret',
    'client_secret',
    'sign',
    'signature',
    'sig',
    'key',
    'apikey',
    'api_key',
    'appkey',
    'accesskey',
    'session',
    'sessionid',
    'session_id',
    'sso',
    'ticket',
    'csrf',
    'csrf_token',
    '__csrf',
    'nonce',
    'music_u',
    'qqmusic_key',
    'qm_keyst',
    'p_skey',
    'skey',
    'mobile',
    'phone',
    'phone_number',
  };

  /// Key names that must match the **whole** key, never as a suffix.
  ///
  /// [sensitiveKeys] is matched after an optional `[A-Za-z0-9_.\-]*?` prefix, so
  /// a short name there redacts every key that merely *ends* with it:
  ///
  /// * `sk` (Last.fm/Libre.fm's session key) would also hit `task`, `disk`,
  ///   `mask` and `flask`, because the non-greedy prefix happily eats `ta` and
  ///   lets `sk` match. Those are ordinary fields, and masking their values
  ///   would cost exactly the debuggability the log exists for.
  /// * `g_tk` (QQ's `bkn` token, derived from `p_skey` in `qq_api.dart`) is
  ///   short enough to treat the same way rather than reason about which longer
  ///   names it might clip.
  ///
  /// Precise keys lose no recall: every real spelling is matched exactly, and
  /// longer names that merely contain one (`p_skey`, `qm_keyst`) are separate
  /// entries in [sensitiveKeys].
  static const Set<String> exactSensitiveKeys = {'sk', 'g_tk'};

  /// The key alternation shared by rules 3, 4 and 4b.
  ///
  /// Built once from the two sets above. Order matters only for readability:
  /// the suffix branch is tried first, then the precise one, so a key that is on
  /// both lists keeps the (more forgiving) suffix behaviour.
  static final String _keyAlternation =
      '(?:[A-Za-z0-9_.\\-]*?(?:'
      '${sensitiveKeys.map(RegExp.escape).join('|')}'
      ')|(?:${exactSensitiveKeys.map(RegExp.escape).join('|')}))';

  /// Rule names reported back to the exporter header, so a user can see that
  /// redaction actually ran (and a test can assert on it).
  static const ruleCookieHeader = 'cookie-header';
  static const ruleBearer = 'bearer-token';
  static const ruleSensitiveKey = 'sensitive-key';
  static const ruleUrlQuery = 'url-query';

  /// Redacts [input] and reports which rules fired.
  static RedactionResult redact(String input) {
    if (input.isEmpty) return const RedactionResult(text: '', rules: {});

    final rules = <String>{};
    var text = input;

    // NOTE: Dart's `RegExp` follows ECMAScript, where inline flags (`(?i)`)
    // are a syntax error — "Invalid group". Case insensitivity therefore has to
    // come from the constructor, which is also why every pattern below is a
    // plain, statically checkable literal.

    // 1. Header-style values: `Cookie: a=b; c=d` up to the end of the line.
    text = _apply(
      text,
      RegExp(
        r'\b(cookie|set-cookie|authorization|proxy-authorization)\s*:\s*[^\r\n]*',
        caseSensitive: false,
        multiLine: true,
      ),
      (match) {
        rules.add(ruleCookieHeader);
        return '${match.group(1)}: $placeholder';
      },
    );

    // 2. `Bearer eyJhbGciOi...`
    text = _apply(
      text,
      RegExp(
        r'\b(bearer)\s+[A-Za-z0-9\-._~+/=]{8,}',
        caseSensitive: false,
      ),
      (match) {
        rules.add(ruleBearer);
        return '${match.group(1)} $placeholder';
      },
    );

    // 3. `key=value` pairs (query strings, form bodies, `;`-joined cookies).
    //
    // The leading delimiter is not strictly required any more: a recorded
    // message can perfectly well *begin* with the credential
    // (`record('qq', 'g_tk=…&src=1')`), so the start of a line counts as one
    // too. Widening the positions can only redact more of a key that is already
    // on the list — it can never pull in a new key.
    text = _apply(
      text,
      RegExp(
        '((?:[?&;,\\s])|^)($_keyAlternation)\\s*=\\s*([^&\\s;,)"\'`]+)',
        caseSensitive: false,
        multiLine: true,
      ),
      (match) {
        // `<redacted>` contains no delimiter, so the separators around it are
        // preserved verbatim; a start-of-line match captures an empty group.
        rules.add(ruleSensitiveKey);
        return '${match.group(1)}${match.group(2)}=$placeholder';
      },
    );

    // 4. JSON-style `"key": "value"`.
    text = _apply(
      text,
      RegExp(
        '("$_keyAlternation"\\s*:\\s*")[^"]*(")',
        caseSensitive: false,
      ),
      (match) {
        rules.add(ruleSensitiveKey);
        return '${match.group(1)}$placeholder${match.group(2)}';
      },
    );

    // 4b. JSON-style `"key": <unquoted scalar>`.
    //
    // Rule 4 only matches a *quoted* value, so a key that is rendered as a
    // number sails straight past it: `g_tk` is an `int` in every place this app
    // produces it (`qq_api.dart` hashes `p_skey` into it and puts it in request
    // maps as `'g_tk': 5381`), and `jsonEncode` writes `{"g_tk":5381}`. Adding
    // the key to the list without this rule would leave that path leaking.
    //
    // The replacement is a **quoted** placeholder so a JSON-shaped log line
    // stays valid JSON. A value that starts with a quote was already handled by
    // rule 4, and `[`/`{`/`,`/`}` are left alone: those are structures, not
    // credentials.
    text = _apply(
      text,
      RegExp(
        '("$_keyAlternation"\\s*:\\s*)([^",}\\s\\[\\{][^,}\\s]*)',
        caseSensitive: false,
      ),
      (match) {
        rules.add(ruleSensitiveKey);
        return '${match.group(1)}"$placeholder"';
      },
    );

    // 5. Whatever is left of a URL query string.
    text = _apply(
      text,
      RegExp(r'''((?:https?)://[^\s?"')\]]+)\?[^\s"')\]]*'''),
      (match) {
        rules.add(ruleUrlQuery);
        return '${match.group(1)}?$placeholder';
      },
    );

    return RedactionResult(text: text, rules: rules);
  }

  /// Convenience wrapper when only the text is needed.
  static String redactText(String input) => redact(input).text;

  static String _apply(
    String input,
    RegExp pattern,
    String Function(Match match) replace,
  ) {
    if (!pattern.hasMatch(input)) return input;
    return input.replaceAllMapped(pattern, replace);
  }
}

/// The redacted text plus the set of rules that fired.
class RedactionResult {
  final String text;
  final Set<String> rules;

  const RedactionResult({required this.text, required this.rules});

  bool get changed => rules.isNotEmpty;

  /// True when [needle] would have leaked had the input not been redacted.
  bool leaks(String needle) => needle.isNotEmpty && text.contains(needle);
}
