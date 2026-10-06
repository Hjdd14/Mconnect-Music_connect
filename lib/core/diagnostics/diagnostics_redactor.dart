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
/// * `key=value` / `"key": "value"` pairs whose key looks credential-like;
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
    text = _apply(
      text,
      RegExp(
        '([?&;,\\s])([A-Za-z0-9_.\\-]*?(?:'
        '${sensitiveKeys.map(RegExp.escape).join('|')}'
        '))\\s*=\\s*([^&\\s;,)"\'`]+)',
        caseSensitive: false,
      ),
      (match) {
        // `<redacted>` contains no delimiter, so the separators around it are
        // preserved verbatim.
        rules.add(ruleSensitiveKey);
        return '${match.group(1)}${match.group(2)}=$placeholder';
      },
    );

    // 4. JSON-style `"key": "value"`.
    text = _apply(
      text,
      RegExp(
        '("(?:[A-Za-z0-9_.\\-]*?(?:'
        '${sensitiveKeys.map(RegExp.escape).join('|')}'
        '))"\\s*:\\s*")[^"]*(")',
        caseSensitive: false,
      ),
      (match) {
        rules.add(ruleSensitiveKey);
        return '${match.group(1)}$placeholder${match.group(2)}';
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
