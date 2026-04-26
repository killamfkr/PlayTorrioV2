/// Port of webstreamr/src/utils/Fetcher.ts
///
/// Built on `package:http`. Provides:
///   * per-host queue (Semaphore) with timeout
///   * per-host UA cache (used after FlareSolverr)
///   * cookie jar
///   * retry-after handling (429)
///   * timeout-count circuit breaker per host
///   * FlareSolverr challenge solving (POST /v1)
///   * MediaFlow-Proxy passthrough hosts
///   * `noProxyHeaders` option to skip X-Forwarded-* injection
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpHeaders;
import 'package:http/http.dart' as http;

import '../errors.dart';
import '../types.dart';
import 'cache.dart';
import 'cookie_jar.dart';
import 'env.dart';
import 'semaphore.dart';

class FetcherRequestConfig {
  String method;
  Map<String, String>? headers;
  String? body;
  Duration? timeout;
  int? minCacheTtlMs;
  bool noProxyHeaders;
  int? queueLimit;
  Duration? queueTimeout;
  int? timeoutsCountThrow;
  bool followRedirects;
  int maxRedirects;

  FetcherRequestConfig({
    this.method = 'GET',
    this.headers,
    this.body,
    this.timeout,
    this.minCacheTtlMs,
    this.noProxyHeaders = false,
    this.queueLimit,
    this.queueTimeout,
    this.timeoutsCountThrow,
    this.followRedirects = true,
    this.maxRedirects = 5,
  });

  FetcherRequestConfig copyWith({
    String? method,
    Map<String, String>? headers,
    String? body,
    Duration? timeout,
    int? queueLimit,
    Duration? queueTimeout,
    bool? followRedirects,
  }) {
    return FetcherRequestConfig(
      method: method ?? this.method,
      headers: headers ?? this.headers,
      body: body ?? this.body,
      timeout: timeout ?? this.timeout,
      minCacheTtlMs: minCacheTtlMs,
      noProxyHeaders: noProxyHeaders,
      queueLimit: queueLimit ?? this.queueLimit,
      queueTimeout: queueTimeout ?? this.queueTimeout,
      timeoutsCountThrow: timeoutsCountThrow,
      followRedirects: followRedirects ?? this.followRedirects,
      maxRedirects: maxRedirects,
    );
  }
}

class FetcherResponse {
  final int status;
  final String statusText;
  final Map<String, String> headers;
  final String body;
  final Uri finalUrl;
  FetcherResponse({
    required this.status,
    required this.statusText,
    required this.headers,
    required this.body,
    required this.finalUrl,
  });
}

class _FlareSolverrSolution {
  final int status;
  final String response;
  final String userAgent;
  final List<Map<String, dynamic>> cookies;
  _FlareSolverrSolution(this.status, this.response, this.userAgent, this.cookies);
}

class Fetcher {
  static const _defaultTimeout = Duration(seconds: 10);
  static const _defaultQueueLimit = 50;
  static const _defaultQueueTimeout = Duration(seconds: 10);
  static const _defaultTimeoutsCountThrow = 30;
  static const _timeoutCacheTtl = Duration(hours: 1);
  static const _flareSolverrCacheTtl = Duration(minutes: 15);
  static const _maxWaitRetryAfter = Duration(seconds: 10);

  final http.Client _client;

  final Map<String, Semaphore> _semaphores = {};
  final Map<String, String> _hostUserAgentMap = {};
  final CookieJar _cookieJar = CookieJar();
  final Cacheable<bool> _rateLimitedCache = Cacheable<bool>();
  final Cacheable<int> _timeoutsCountCache = Cacheable<int>();
  final Mutex _timeoutsMutex = Mutex();
  final Cacheable<_FlareSolverrSolution> _flareSolverrCache =
      Cacheable<_FlareSolverrSolution>();
  final Map<String, Mutex> _flareSolverrMutexes = {};
  final void Function(String) _log;

  Fetcher({http.Client? client, void Function(String msg)? logger})
      : _client = client ?? http.Client(),
        _log = logger ?? ((_) {});

  // ── public surface ────────────────────────────────────────────────────────

  Future<FetcherResponse> fetch(Context ctx, Uri url,
          [FetcherRequestConfig? cfg]) =>
      _queuedFetch(ctx, url, cfg ?? FetcherRequestConfig());

  Future<String> text(Context ctx, Uri url, [FetcherRequestConfig? cfg]) async =>
      (await _queuedFetch(ctx, url, cfg ?? FetcherRequestConfig())).body;

  Future<String> textPost(Context ctx, Uri url, String data,
      [FetcherRequestConfig? cfg]) async {
    final c = cfg ?? FetcherRequestConfig();
    c.method = 'POST';
    c.body = data;
    return (await _queuedFetch(ctx, url, c)).body;
  }

  Future<Map<String, String>> head(Context ctx, Uri url,
      [FetcherRequestConfig? cfg]) async {
    final c = cfg ?? FetcherRequestConfig();
    c.method = 'HEAD';
    return (await _queuedFetch(ctx, url, c)).headers;
  }

  Future<Uri> getFinalRedirectUrl(
    Context ctx,
    Uri url, [
    FetcherRequestConfig? cfg,
    int? maxCount,
    int count = 0,
  ]) async {
    final c = (cfg ?? FetcherRequestConfig()).copyWith(
      method: 'HEAD',
      followRedirects: false,
    );
    if (maxCount != null && count >= maxCount) return url;
    final response = await _queuedFetch(ctx, url, c);
    if (response.status >= 300 && response.status < 400) {
      final loc = response.headers['location'];
      if (loc == null) return url;
      return getFinalRedirectUrl(
          ctx, Uri.parse(loc), c, maxCount, count + 1);
    }
    return url;
  }

  Future<dynamic> json(Context ctx, Uri url,
      [FetcherRequestConfig? cfg]) async {
    final c = cfg ?? FetcherRequestConfig();
    c.headers = {
      'Accept': 'application/json,text/plain,*/*',
      ...?c.headers,
    };
    return jsonDecode(await text(ctx, url, c));
  }

  // ── queue + timeout wrapper ──────────────────────────────────────────────

  Semaphore _semFor(Uri url, int limit) {
    return _semaphores.putIfAbsent(url.host, () => Semaphore(limit));
  }

  Future<FetcherResponse> _queuedFetch(
      Context ctx, Uri url, FetcherRequestConfig cfg) async {
    final limit = cfg.queueLimit ?? _defaultQueueLimit;
    final qto = cfg.queueTimeout ?? _defaultQueueTimeout;
    final sem = _semFor(url, limit);
    await sem.acquire(timeout: qto, url: url);
    try {
      return await _fetchWithTimeout(ctx, url, cfg);
    } finally {
      sem.release();
    }
  }

  Future<FetcherResponse> _fetchWithTimeout(
      Context ctx, Uri url, FetcherRequestConfig cfg,
      [int tryCount = 0]) async {
    var msg = 'Fetch ${cfg.method} $url';
    if (cfg.headers?[HttpHeaders.refererHeader] != null) {
      msg += ' with referer ${cfg.headers![HttpHeaders.refererHeader]}';
    } else if (cfg.headers?['Referer'] != null) {
      msg += ' with referer ${cfg.headers!['Referer']}';
    }
    _log(msg);

    final rateRaw = _rateLimitedCache.getRaw(url.host);
    if (rateRaw != null && rateRaw.value) {
      final ttl = rateRaw.expiresAtMs - DateTime.now().millisecondsSinceEpoch;
      if (ttl <= _maxWaitRetryAfter.inMilliseconds && tryCount < 1) {
        _log('Wait out rate limit for $url');
        await Future.delayed(Duration(milliseconds: ttl));
        return _fetchWithTimeout(
            ctx, url, cfg.copyWith(queueLimit: 1), tryCount + 1);
      }
      throw TooManyRequestsError(url, ttl / 1000);
    }

    final timeouts = _timeoutsCountCache.get(url.host) ?? 0;
    if (!_isFlareSolverrUrl(url) &&
        timeouts >= (cfg.timeoutsCountThrow ?? _defaultTimeoutsCountThrow)) {
      throw TooManyTimeoutsError(url);
    }

    final reqHeaders = <String, String>{
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en',
      'Priority': 'u=0',
      'User-Agent': _hostUserAgentMap[url.host] ??
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      if (url.userInfo.isNotEmpty)
        'Authorization':
            'Basic ${base64.encode(utf8.encode(url.userInfo))}',
      if (ctx.ip != null && !cfg.noProxyHeaders) ...{
        'Forwarded':
            'by=unknown;for=${ctx.ip};host=${url.host};proto=${url.scheme}',
        'X-Forwarded-For': ctx.ip!,
        'X-Forwarded-Host': url.host,
        'X-Forwarded-Proto': url.scheme,
        'X-Real-IP': ctx.ip!,
      },
      ...?cfg.headers,
    };

    final cookieString = _cookieJar.getCookieString(url);
    if (cookieString != null && cookieString.isNotEmpty) {
      reqHeaders['Cookie'] = cookieString;
    }

    // Strip user info from URL before sending.
    final cleanUrl = url.replace(userInfo: '');

    http.Response response;
    try {
      final req = http.Request(cfg.method, cleanUrl);
      req.headers.addAll(reqHeaders);
      req.followRedirects = cfg.followRedirects;
      req.maxRedirects = cfg.maxRedirects;
      if (cfg.body != null) req.body = cfg.body!;
      final streamed = await _client
          .send(req)
          .timeout(cfg.timeout ?? _defaultTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      _log('Got timeout for $url');
      await _increaseTimeouts(url);
      throw TimeoutError(url);
    } catch (e) {
      _log('Got error $e for $url');
      rethrow;
    }

    _log('Got ${response.statusCode} (${response.reasonPhrase}) for $url');
    await _decreaseTimeouts(url);

    // Persist Set-Cookie (from any redirect chain we get back)
    final setCookies = _extractSetCookies(response.headers);
    if (setCookies.isNotEmpty) _cookieJar.setFromHeaders(url, setCookies);

    // 429 Retry-After short-wait
    if (response.statusCode == 429) {
      final ra =
          int.tryParse('${response.headers['retry-after']}') ?? 0;
      if (ra * 1000 <= _maxWaitRetryAfter.inMilliseconds && tryCount < 1) {
        _log('Wait out rate limit for ${url.host}');
        await Future.delayed(Duration(seconds: ra));
        return _fetchWithTimeout(
            ctx, url, cfg.copyWith(queueLimit: 1), tryCount + 1);
      }
    }

    final triggeredCloudflareTurnstile =
        response.headers.containsKey('cf-turnstile');

    if (response.statusCode >= 200 &&
        response.statusCode <= 399 &&
        !triggeredCloudflareTurnstile) {
      return FetcherResponse(
        status: response.statusCode,
        statusText: response.reasonPhrase ?? '',
        headers: Map.of(response.headers),
        body: response.body,
        finalUrl: response.request?.url ?? cleanUrl,
      );
    }

    if (response.statusCode == 404) throw NotFoundError();

    if (response.headers['cf-mitigated'] == 'challenge' ||
        triggeredCloudflareTurnstile) {
      final endpoint = WsEnv.get('FLARESOLVERR_ENDPOINT');
      if (endpoint == null) {
        throw BlockedError(url, BlockedReason.cloudflare_challenge,
            Map.of(response.headers));
      }
      return _solveWithFlareSolverr(ctx, url, endpoint, response);
    }

    if (response.statusCode == 403) {
      final mfp = ctx.config['mediaFlowProxyUrl'];
      if (mfp != null && url.toString().contains(mfp)) {
        throw BlockedError(url, BlockedReason.media_flow_proxy_auth,
            Map.of(response.headers));
      }
      throw BlockedError(url, BlockedReason.unknown,
          Map.of(response.headers));
    }

    if (response.statusCode == 451) {
      throw BlockedError(url, BlockedReason.cloudflare_censor,
          Map.of(response.headers));
    }

    if (response.statusCode == 429) {
      final ra = int.tryParse('${response.headers['retry-after']}') ?? 0;
      if (ra > 0) {
        _rateLimitedCache.set(url.host, true, Duration(seconds: ra));
      }
      throw TooManyRequestsError(url, ra);
    }

    throw HttpError(url, response.statusCode, response.reasonPhrase ?? '',
        Map.of(response.headers));
  }

  // ── FlareSolverr ─────────────────────────────────────────────────────────

  bool _isFlareSolverrUrl(Uri url) {
    final ep = WsEnv.get('FLARESOLVERR_ENDPOINT');
    return ep != null && url.toString().startsWith(ep);
  }

  Future<FetcherResponse> _solveWithFlareSolverr(
      Context ctx, Uri url, String endpoint, http.Response orig) async {
    final cached = _flareSolverrCache.get(url.toString());
    if (cached != null) {
      return FetcherResponse(
        status: cached.status,
        statusText: 'OK',
        headers: Map.of(orig.headers),
        body: cached.response,
        finalUrl: url,
      );
    }
    final session = '${WsEnv.appId()}_${url.host}';
    final mutex = _flareSolverrMutexes.putIfAbsent(session, () => Mutex());
    final solution = await mutex.runExclusive<_FlareSolverrSolution>(() async {
      _log('Query FlareSolverr for $url');
      final body = jsonEncode({
        'cmd': 'request.get',
        'url': url.toString(),
        'session': session,
        'session_ttl_minutes': 60,
        'maxTimeout': 15000,
        'disableMedia': true,
      });
      final cfg = FetcherRequestConfig(
        method: 'POST',
        body: body,
        headers: {'Content-Type': 'application/json'},
        timeout: const Duration(seconds: 15),
        queueTimeout: const Duration(seconds: 60),
      );
      final resp = await _queuedFetch(
          ctx, Uri.parse('$endpoint/v1'), cfg);
      final parsed = jsonDecode(resp.body) as Map<String, dynamic>;
      if (parsed['status'] != 'ok') {
        throw BlockedError(url, BlockedReason.flaresolverr_failed, {});
      }
      final sol = parsed['solution'] as Map<String, dynamic>;
      return _FlareSolverrSolution(
        sol['status'] as int,
        sol['response'] as String,
        sol['userAgent'] as String,
        ((sol['cookies'] as List?) ?? const [])
            .map((c) => (c as Map).cast<String, dynamic>())
            .toList(),
      );
    });

    for (final ck in solution.cookies) {
      final name = ck['name'] as String;
      if (!name.startsWith('cf_') &&
          !name.startsWith('__cf') &&
          !name.startsWith('__ddg')) {
        continue;
      }
      _cookieJar.setCookie(
        url: url,
        name: name,
        value: ck['value'] as String,
        domain: (ck['domain'] as String).replaceFirst(RegExp(r'^\.+'), ''),
        path: (ck['path'] as String?) ?? '/',
        expires: DateTime.fromMillisecondsSinceEpoch(
            ((ck['expiry'] as num?) ?? 0).toInt() * 1000),
        secure: (ck['secure'] as bool?) ?? false,
        httpOnly: (ck['httpOnly'] as bool?) ?? false,
      );
    }
    _hostUserAgentMap[url.host] = solution.userAgent;
    _flareSolverrCache.set(url.toString(), solution, _flareSolverrCacheTtl);

    return FetcherResponse(
      status: solution.status,
      statusText: 'OK',
      headers: Map.of(orig.headers),
      body: solution.response,
      finalUrl: url,
    );
  }

  // ── timeout circuit-breaker ──────────────────────────────────────────────

  Future<void> _increaseTimeouts(Uri url) async {
    await _timeoutsMutex.runExclusive(() async {
      final n = (_timeoutsCountCache.get(url.host) ?? 0) + 1;
      _timeoutsCountCache.set(url.host, n, _timeoutCacheTtl);
    });
  }

  Future<void> _decreaseTimeouts(Uri url) async {
    await _timeoutsMutex.runExclusive(() async {
      final n = ((_timeoutsCountCache.get(url.host) ?? 0) - 1)
          .clamp(0, 1 << 30);
      _timeoutsCountCache.set(url.host, n, _timeoutCacheTtl);
    });
  }

  // `package:http` folds multiple Set-Cookie headers into a single value
  // joined by ", " which conflicts with Expires=… commas. We extract the raw
  // strings as best we can.
  List<String> _extractSetCookies(Map<String, String> headers) {
    final raw = headers['set-cookie'];
    if (raw == null || raw.isEmpty) return const [];
    // Split on comma followed by a token before '=', but preserve dates.
    final out = <String>[];
    var current = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == ',') {
        // Lookahead to next ',' or ';' — if next "key=" appears with no day
        // word in between, treat as a separator.
        final rest = raw.substring(i + 1);
        if (RegExp(r'^\s*[A-Za-z0-9!#\$%&'r"'"r'*+\-.^_`|~]+=').hasMatch(rest)) {
          out.add(current.toString().trim());
          current = StringBuffer();
          continue;
        }
      }
      current.write(ch);
    }
    if (current.isNotEmpty) out.add(current.toString().trim());
    return out.where((s) => s.isNotEmpty).toList();
  }
}
