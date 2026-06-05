/// Minimal cookie jar. Stores per-host cookies and serializes them into a
/// `Cookie:` header string. Mirrors how webstreamr uses `tough-cookie` —
/// only host + path level matching, no SameSite logic on send.
library;

class _Cookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;

  _Cookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expires,
    this.secure = false,
    this.httpOnly = false,
  });

  bool get isExpired =>
      expires != null && expires!.isBefore(DateTime.now());

  bool matches(Uri url) {
    if (isExpired) return false;
    if (secure && url.scheme != 'https') return false;
    final host = url.host.toLowerCase();
    final domainNorm = domain.startsWith('.') ? domain.substring(1) : domain;
    if (host != domainNorm && !host.endsWith('.$domainNorm')) return false;
    final urlPath = url.path.isEmpty ? '/' : url.path;
    if (!urlPath.startsWith(path)) return false;
    return true;
  }
}

class CookieJar {
  final _cookies = <_Cookie>[];

  /// Parses a single Set-Cookie header value and stores it for [url].
  void setFromSetCookieHeader(Uri url, String header) {
    final parts = header.split(';');
    if (parts.isEmpty) return;
    final nv = parts[0].split('=');
    if (nv.length < 2) return;
    final name = nv[0].trim();
    final value = nv.sublist(1).join('=').trim();
    String domain = url.host;
    String path = '/';
    DateTime? expires;
    bool secure = false;
    bool httpOnly = false;
    for (var i = 1; i < parts.length; i++) {
      final attr = parts[i].trim();
      final eq = attr.indexOf('=');
      final key = (eq < 0 ? attr : attr.substring(0, eq)).toLowerCase();
      final val = eq < 0 ? '' : attr.substring(eq + 1).trim();
      switch (key) {
        case 'domain':
          domain = val.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
          break;
        case 'path':
          path = val.isEmpty ? '/' : val;
          break;
        case 'expires':
          try {
            expires = DateTime.parse(val);
          } catch (_) {
            try {
              expires = HttpDateParser.parse(val);
            } catch (_) {}
          }
          break;
        case 'max-age':
          final secs = int.tryParse(val);
          if (secs != null) expires = DateTime.now().add(Duration(seconds: secs));
          break;
        case 'secure':
          secure = true;
          break;
        case 'httponly':
          httpOnly = true;
          break;
      }
    }
    // Replace any existing cookie with the same (domain, path, name).
    _cookies.removeWhere((c) =>
        c.name == name && c.domain == domain && c.path == path);
    _cookies.add(_Cookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expires: expires,
      secure: secure,
      httpOnly: httpOnly,
    ));
  }

  /// Convenience for storing many `Set-Cookie` headers (some HTTP clients
  /// fold them with newlines).
  void setFromHeaders(Uri url, Iterable<String> headers) {
    for (final h in headers) {
      // A single header may contain multiple cookies separated by `, ` only
      // when they don't carry an `Expires=` attribute (rare for our hosts).
      // We treat each header as one cookie to stay safe with date commas.
      setFromSetCookieHeader(url, h);
    }
  }

  /// Adds a cookie directly (used by the FlareSolverr path).
  void setCookie({
    required Uri url,
    required String name,
    required String value,
    required String domain,
    String path = '/',
    DateTime? expires,
    bool secure = false,
    bool httpOnly = false,
  }) {
    _cookies.removeWhere((c) =>
        c.name == name && c.domain == domain && c.path == path);
    _cookies.add(_Cookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expires: expires,
      secure: secure,
      httpOnly: httpOnly,
    ));
  }

  String? getCookieString(Uri url) {
    final parts = _cookies
        .where((c) => c.matches(url))
        .map((c) => '${c.name}=${c.value}')
        .toList();
    return parts.isEmpty ? null : parts.join('; ');
  }

  void clear() => _cookies.clear();
}

/// Minimal RFC 1123 / 850 date parser fallback.
class HttpDateParser {
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime parse(String s) {
    // Examples: "Wed, 21 Oct 2026 07:28:00 GMT"
    final m = RegExp(r'(\d{1,2})[- ]([A-Za-z]{3})[- ](\d{2,4}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(s);
    if (m == null) throw FormatException('bad http-date: $s');
    final day = int.parse(m.group(1)!);
    final mon = _months[m.group(2)!.toLowerCase()] ?? 1;
    var year = int.parse(m.group(3)!);
    if (year < 100) year += year < 70 ? 2000 : 1900;
    return DateTime.utc(year, mon, day,
        int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!));
  }
}
