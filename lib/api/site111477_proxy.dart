// Local seekable streaming proxy for MPV — single-connection edition.
//
// 1:1 Dart port of server.js, copied verbatim from 111477service.dart.
// Pure dart:io, no external dependencies.
//
// This CDN rate-limits by REQUEST COUNT (every range request is a strike,
// 429 with multi-minute Retry-After). So we do the opposite of chunking:
//   * Open ONE long-lived upstream GET starting at byte 0 (or wherever
//     MPV first seeks to), writing into a sparse local file.
//   * Serve MPV's Range requests from the local file as data arrives.
//   * On seek beyond what we've buffered, abort the upstream connection
//     and reopen it from the new offset (one new request — not 800).
//   * Cache file is reused across runs (resume).
//
// MOBILE ADAPTATIONS (only — algorithm untouched):
//   * `cacheDir` is set at start-time from path_provider's temp directory
//     instead of `Directory.current`.
//   * `ProcessSignal.sigint` is not registered on Android/iOS (where it
//     does not exist). The proxy is stopped explicitly via `stop111477Proxy`.
//   * `main()` is replaced with `start111477Proxy(url, headers)` /
//     `stop111477Proxy()` so the same code can run inside a Flutter app.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

// ---------- config ----------
// Port 0 = let the OS pick any free port (avoids conflicts with other
// app proxies and works inside Android's restricted port range).
const int port             = 0;
int _boundPort             = 0;
const int seekTolerance    = 4 * 1024 * 1024;
const int waitPollMs       = 100;
const int waitTimeoutMs    = 60000;
const int reconnectDelay   = 1500;
const int maxReconnects    = 20;
const int maxRedirects     = 8;
const int cf1015WaitMs     = 12000; // 10s CF rule + 2s safety margin

// ---- sliding-window chunked cache ----
// Cache the file as many small chunk files instead of one giant sparse
// file. The janitor keeps only chunks within [readPos - back, readPos +
// forward] on disk — like a torrent streamer's piece cache. Total disk
// footprint stays roughly (back + forward) regardless of file size, so a
// 15 GiB stream uses ~290 MiB instead of 15 GiB.
const int chunkSize          = 4 * 1024 * 1024;       // 4 MiB per chunk
const int forwardBufferBytes = 256 * 1024 * 1024;     // ~ 1-2 min runway
const int backBufferBytes    = 32 * 1024 * 1024;      // ~ 30s lookback
// MKV stores its SeekHead / cues at the file tail, MP4 may store moov at
// the start or the end. MPV reads them once on open and again on every
// seek. Pin a few chunks at each end so the janitor can't evict them —
// otherwise every seek triggers a fresh captcha + CF1015 wait to refetch.
const int anchorChunksHead   = 2;                     // first 8 MiB
const int anchorChunksTail   = 2;                     // last  8 MiB
const int maxOpenWriteRafs   = 8;                     // LRU cap on writer RAFs
const Duration janitorPeriod = Duration(seconds: 2);

// Initialized to '' so an early _doStop() before start() reaches the cache
// dir setup doesn't trip a LateInitializationError.
String cacheDir = '';

// Global Cloudflare 1015 cooldown gate. Whenever ANY code path sees a 1015,
// it pushes this deadline out, and every outbound request must wait until
// the deadline passes. This guarantees a truly quiet network for the full
// cooldown (CF resets the counter only if there are zero hits in the window).
int _cf1015UntilMs = 0;
bool _stopping = false;

void _markCf1015() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final until = now + cf1015WaitMs;
  if (until > _cf1015UntilMs) _cf1015UntilMs = until;
}

Future<void> _awaitCf1015Cooldown() async {
  // Poll in 200 ms slices so a stop() can break us out immediately instead
  // of stalling teardown for up to 12 s.
  while (!_stopping) {
    final remaining =
        _cf1015UntilMs - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return;
    await Future.delayed(Duration(milliseconds: remaining < 200 ? remaining : 200));
  }
}

final Map<String, String> extraHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
};

// ---------- argv / globals ----------
late String originalUrl;
late String targetUrl;

_Meta? meta;
// Per-key directory: <cacheDir>/<hashKey>/chunk_<NNNNNNN>.bin
// Initialized to '' so an early _doStop() before start() reaches the chunk
// dir setup doesn't trip a LateInitializationError.
String cacheKeyDir = '';

// chunkIdx -> bytes currently written contiguously from chunk start.
// A chunk is "complete" when chunkBytes[idx] >= _chunkExpectedSize(idx).
final Map<int, int> chunkBytes = {};
final Set<int> haveChunks = {};

// Open writer RAFs (FileMode.append). Closed when the chunk completes or
// when the LRU cap is hit. Reader uses fresh per-call FileMode.read RAFs.
final Map<int, RandomAccessFile> _chunkRafs = {};
final List<int> _chunkRafLru = []; // chunk indices, MRU at end

// Latest absolute byte offset the active reader has consumed. The janitor
// uses this to decide which chunks fall outside the keep window.
int _currentReadOffset = 0;

Timer? _janitorTimer;

// One shared HttpClient, follows no redirects (we follow manually).
final HttpClient httpClient = HttpClient()
  ..autoUncompress = false
  ..idleTimeout = const Duration(seconds: 30);

// ---------- low-level HTTP ----------
class _RawResponse {
  final HttpClientResponse res;
  // The subscription is created lazily; abort() cancels it.
  StreamSubscription<List<int>>? _sub;
  bool _aborted = false;
  _RawResponse(this.res);

  void abort() {
    if (_aborted) return;
    _aborted = true;
    // Just cancel the subscription. Calling res.detachSocket() here triggers
    // a null-check crash inside dart:io's _HttpClient._returnConnection when
    // the response was already drained / completed — which then corrupts the
    // shared HttpClient connection pool and breaks every subsequent request.
    // Cancelling the subscription is enough; dart:io will release or recycle
    // the underlying socket on its own.
    try { _sub?.cancel(); } catch (_) {}
  }
}

Future<_RawResponse> rawRequest(
  String urlStr,
  String method,
  Map<String, String> headers, {
  int timeoutMs = 15000,
}) async {
  // Block until any global CF 1015 cooldown has elapsed — otherwise we keep
  // resetting Cloudflare's counter and never escape the rate limit.
  await _awaitCf1015Cooldown();
  final u = Uri.parse(urlStr);
  final req = await httpClient
      .openUrl(method, u)
      .timeout(Duration(milliseconds: timeoutMs));
  req.followRedirects = false;
  // Merge extraHeaders + headers; later wins.
  extraHeaders.forEach((k, v) => req.headers.set(k, v));
  headers.forEach((k, v) => req.headers.set(k, v));
  // Host header is set automatically by dart:io from the URI.
  final res = await req.close().timeout(Duration(milliseconds: timeoutMs));
  return _RawResponse(res);
}

Future<_RawResponse> followRedirects(
  String method,
  Map<String, String> headers,
) async {
  var url = targetUrl;
  var m = method;
  for (var i = 0; i <= maxRedirects; i++) {
    final raw = await rawRequest(url, m, headers);
    final code = raw.res.statusCode;
    if (code >= 300 && code < 400) {
      final loc = raw.res.headers.value(HttpHeaders.locationHeader);
      if (loc != null) {
        await raw.res.drain<void>().catchError((_) {});
        raw.abort();
        url = Uri.parse(url).resolve(loc).toString();
        if (code == 303) m = 'GET';
        continue;
      }
    }
    if (url != targetUrl) {
      stdout.writeln('  resolved → $url');
      targetUrl = url;
    }
    return raw;
  }
  throw Exception('Too many redirects');
}

void reresolve() {
  if (targetUrl != originalUrl) {
    stdout.writeln('  re-resolving signed URL …');
    targetUrl = originalUrl;
  }
}

// ---------- captcha auto-solver ----------

Future<String> readBodyText(_RawResponse raw, {int maxBytes = 65536}) {
  final completer = Completer<String>();
  final chunks = <int>[];
  late StreamSubscription<List<int>> sub;
  void finish([Object? err]) {
    if (completer.isCompleted) return;
    try {
      completer.complete(utf8.decode(chunks, allowMalformed: true));
    } catch (_) {
      completer.complete('');
    }
  }
  sub = raw.res.listen((c) {
    if (chunks.length < maxBytes) {
      final remaining = maxBytes - chunks.length;
      chunks.addAll(c.length <= remaining ? c : c.sublist(0, remaining));
    }
  }, onDone: finish, onError: (_) => finish(), cancelOnError: false);
  raw._sub = sub;
  return completer.future;
}

// Tiny safe arithmetic evaluator — only digits, whitespace, + - * / ( ).
num? evalSimpleMath(String expr) {
  final cleaned = expr.replaceAll(RegExp(r'\s+'), '');
  if (!RegExp(r'^[0-9+\-*/()]+$').hasMatch(cleaned)) return null;
  try {
    final p = _Parser(cleaned);
    final v = p.parseExpr();
    if (!p.atEnd) return null;
    if (v.isNaN || v.isInfinite) return null;
    return v;
  } catch (_) {
    return null;
  }
}

class _Parser {
  final String s;
  int i = 0;
  _Parser(this.s);
  bool get atEnd => i >= s.length;
  String get cur => s[i];
  num parseExpr() {
    var v = parseTerm();
    while (!atEnd && (cur == '+' || cur == '-')) {
      final op = cur;
      i++;
      final r = parseTerm();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }
  num parseTerm() {
    var v = parseFactor();
    while (!atEnd && (cur == '*' || cur == '/')) {
      final op = cur;
      i++;
      final r = parseFactor();
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }
  num parseFactor() {
    if (atEnd) throw const FormatException('eof');
    if (cur == '-') { i++; return -parseFactor(); }
    if (cur == '+') { i++; return parseFactor(); }
    if (cur == '(') {
      i++;
      final v = parseExpr();
      if (atEnd || cur != ')') throw const FormatException('mismatched paren');
      i++;
      return v;
    }
    final start = i;
    while (!atEnd && (cur.codeUnitAt(0) >= 0x30 && cur.codeUnitAt(0) <= 0x39)) {
      i++;
    }
    if (i == start) throw const FormatException('expected number');
    return int.parse(s.substring(start, i));
  }
}

class _Captcha {
  final String question;
  final num answer;
  final String token;
  final String linkId;
  _Captcha(this.question, this.answer, this.token, this.linkId);
}

_Captcha? parseCaptcha(String html) {
  if (html.isEmpty) return null;
  if (!RegExp(r'Download Locked|captchaForm|/unlock/', caseSensitive: false)
      .hasMatch(html)) return null;
  final qMatch = RegExp(
      r'<div class="question"[^>]*>\s*([^<]+?)\s*=\s*\?\s*</div>',
      caseSensitive: false).firstMatch(html);
  final tokMatch =
      RegExp(r'id="token"\s+value="([^"]+)"', caseSensitive: false).firstMatch(html);
  final linkMatch =
      RegExp(r'id="linkId"\s+value="([^"]+)"', caseSensitive: false).firstMatch(html);
  if (qMatch == null || tokMatch == null || linkMatch == null) return null;
  final answer = evalSimpleMath(qMatch.group(1)!);
  if (answer == null) return null;
  return _Captcha(qMatch.group(1)!.trim(), answer, tokMatch.group(1)!, linkMatch.group(1)!);
}

// CF "Error 1015 — You are being rate limited"
bool isCloudflare1015(String text) {
  if (text.isEmpty) return false;
  return RegExp(r'\b(?:error\s*(?:code:?\s*)?1015)\b', caseSensitive: false)
          .hasMatch(text) ||
      RegExp(r'you are being rate limited', caseSensitive: false).hasMatch(text);
}

// Worker-side hint that the signed download URL we're holding is no longer
// valid and we should re-resolve from `originalUrl`. Examples seen in the
// wild: "id busy - generate a new download link if stuck",
// "link expired", "invalid signature".
bool _isSignedUrlExhausted(String text) {
  if (text.isEmpty) return false;
  final t = text.toLowerCase();
  return t.contains('id busy') ||
      t.contains('generate a new download link') ||
      t.contains('link expired') ||
      t.contains('invalid signature') ||
      t.contains('signature expired');
}

class _PostResult {
  final int status;
  final String body;
  _PostResult(this.status, this.body);
}

Future<_PostResult> postJson(String urlStr, Object obj,
    {int timeoutMs = 15000}) async {
  final u = Uri.parse(urlStr);
  final body = utf8.encode(jsonEncode(obj));
  final req = await httpClient
      .openUrl('POST', u)
      .timeout(Duration(milliseconds: timeoutMs));
  req.followRedirects = false;
  extraHeaders.forEach((k, v) => req.headers.set(k, v));
  req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  req.headers.set(HttpHeaders.contentLengthHeader, body.length.toString());
  req.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
  req.add(body);
  final res =
      await req.close().timeout(Duration(milliseconds: timeoutMs));
  final raw = _RawResponse(res);
  final text = await readBodyText(raw);
  return _PostResult(res.statusCode, text);
}

// kind: 'captcha-solved' | 'captcha-failed' | 'cf1015' | 'other'
class _HtmlResult {
  final String kind;
  final int waitMs;
  _HtmlResult(this.kind, [this.waitMs = 0]);
}

Future<_HtmlResult> handleHtmlResponse(
    _RawResponse raw, String pageOrigin, String? retryAfterHeader) async {
  final html = await readBodyText(raw);

  if (isCloudflare1015(html)) {
    _markCf1015();
    return _HtmlResult('cf1015', cf1015WaitMs);
  }

  final c = parseCaptcha(html);
  if (c == null) return _HtmlResult('other');

  stdout.writeln(
      '  ⚡ captcha detected: "${c.question} = ?" → answering ${c.answer}');
  final unlockUrl =
      '$pageOrigin/unlock/${Uri.encodeComponent(c.linkId)}';
  try {
    final r = await postJson(unlockUrl, {'answer': c.answer, 'token': c.token});
    var ok = false;
    try {
      final parsed = jsonDecode(r.body);
      if (parsed is Map && parsed['ok'] == true) ok = true;
    } catch (_) {}
    if (r.status >= 200 && r.status < 300 && ok) {
      stdout.writeln('  ✓ captcha unlocked');
      return _HtmlResult('captcha-solved');
    }
    stdout.writeln(
        '  ✗ unlock failed: HTTP ${r.status} ${_truncate(r.body, 200)}');
  } catch (e) {
    stdout.writeln('  ✗ unlock POST error: $e');
  }
  return _HtmlResult('captcha-failed');
}

String _truncate(String s, int n) => s.length <= n ? s : s.substring(0, n);

String originOf(String urlStr) {
  final u = Uri.parse(urlStr);
  return '${u.scheme}://${u.authority}';
}

bool looksLikeHtml(_RawResponse raw) {
  final ct = (raw.res.headers.value(HttpHeaders.contentTypeHeader) ?? '')
      .toLowerCase();
  return ct.contains('text/html');
}

// Concurrent solve coalescing — a token can only be redeemed once.
Future<_HtmlResult>? _inflightCaptchaSolve;
Future<_HtmlResult> fetchAndSolveCaptchaPage() {
  final existing = _inflightCaptchaSolve;
  if (existing != null) return existing;
  final fut = _fetchAndSolveCaptchaPageImpl();
  _inflightCaptchaSolve = fut;
  fut.whenComplete(() => _inflightCaptchaSolve = null);
  return fut;
}

Future<_HtmlResult> _fetchAndSolveCaptchaPageImpl() async {
  const browserHeaders = {
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };
  var url = targetUrl;
  var lastStatus = 0;
  var lastCt = '';
  try {
    for (var i = 0; i < maxRedirects; i++) {
      final raw = await rawRequest(url, 'GET', browserHeaders);
      lastStatus = raw.res.statusCode;
      lastCt = raw.res.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      if (lastStatus >= 300 && lastStatus < 400) {
        final loc = raw.res.headers.value(HttpHeaders.locationHeader);
        if (loc != null) {
          await raw.res.drain<void>().catchError((_) {});
          raw.abort();
          url = Uri.parse(url).resolve(loc).toString();
          continue;
        }
      }
      if (looksLikeHtml(raw)) {
        stdout.writeln(
            '  · captcha page from ${Uri.parse(url).host} (HTTP $lastStatus)');
        final result = await handleHtmlResponse(raw, originOf(url),
            raw.res.headers.value('retry-after'));
        raw.abort();
        return result;
      }
      final body = await readBodyText(raw, maxBytes: 2048);
      raw.abort();
      stdout.writeln(
          '  · captcha-page fetch: HTTP $lastStatus ct="$lastCt" body="${_truncate(body, 120).trim()}"');
      if (isCloudflare1015(body)) { _markCf1015(); return _HtmlResult('cf1015', cf1015WaitMs); }
      return _HtmlResult('other');
    }
    stdout.writeln('  · captcha-page fetch: too many redirects');
    return _HtmlResult('other');
  } catch (e) {
    stdout.writeln('  ✗ captcha page fetch failed: $e');
    return _HtmlResult('other');
  }
}

// ---------- probe ----------
class _Meta {
  final int length;
  final String type;
  _Meta(this.length, this.type);
}

Future<_Meta> probe() async {
  for (var attempt = 0; attempt < 8; attempt++) {
    stdout.writeln('  sending probe GET bytes=0-0 …');
    final raw = await followRedirects('GET', {'Range': 'bytes=0-0'});
    stdout.writeln('  probe response: HTTP ${raw.res.statusCode}');

    if (looksLikeHtml(raw)) {
      final result = await handleHtmlResponse(
          raw, originOf(targetUrl), raw.res.headers.value('retry-after'));
      raw.abort();
      if (result.kind == 'captcha-solved') { reresolve(); continue; }
      if (result.kind == 'cf1015') {
        final s = (result.waitMs / 1000).round();
        stdout.writeln(
            '  ! Cloudflare 1015 rate limit — waiting ${s}s then retrying');
        await Future.delayed(Duration(milliseconds: result.waitMs));
        continue;
      }
      throw Exception(
          'upstream returned HTML and auto-solve failed (kind=${result.kind})');
    }

    if (raw.res.statusCode == 429) {
      final body = await readBodyText(raw, maxBytes: 512);
      raw.abort();
      stdout.writeln('  ! probe 429: ${body.trim()}');

      if (isCloudflare1015(body)) {
        _markCf1015();
        stdout.writeln(
            '  ! Cloudflare 1015 — waiting ${cf1015WaitMs / 1000}s then retrying');
        await Future.delayed(const Duration(milliseconds: cf1015WaitMs));
        continue;
      }

      // "id busy - generate a new download link if stuck" — the worker is
      // telling us the signed URL is exhausted. Re-resolve from originalUrl
      // instead of trying the captcha solver (which can't help here).
      //
      // EXCEPT for "concurrency limit reached" — that one IS unlockable via
      // the captcha solver on the same shard, so let it fall through below.
      if (_isSignedUrlExhausted(body) &&
          !body.toLowerCase().contains('concurrency limit')) {
        stdout.writeln('  ! signed URL exhausted — re-resolving');
        reresolve();
        await Future.delayed(const Duration(milliseconds: 1000));
        continue;
      }

      stdout.writeln('  ⚡ fetching captcha page to auto-solve …');
      final result = await fetchAndSolveCaptchaPage();
      if (result.kind == 'captcha-solved') { reresolve(); continue; }
      if (result.kind == 'cf1015') {
        stdout.writeln(
            '  ! Cloudflare 1015 — waiting ${result.waitMs / 1000}s then retrying');
        await Future.delayed(Duration(milliseconds: result.waitMs));
        continue;
      }
      final ra = raw.res.headers.value('retry-after') ?? '?';
      throw Exception(
          'upstream 429 (Retry-After=${ra}s) and captcha auto-solve failed: ${body.trim()}');
    }

    final cr = raw.res.headers.value('content-range') ?? '';
    final m = RegExp(r'/(\d+)\s*$').firstMatch(cr);
    final type =
        raw.res.headers.value(HttpHeaders.contentTypeHeader) ?? 'application/octet-stream';
    await raw.res.drain<void>().catchError((_) {});
    raw.abort();
    if (m != null) return _Meta(int.parse(m.group(1)!), type);
    final lenStr = raw.res.headers.value(HttpHeaders.contentLengthHeader) ?? '0';
    final len = int.tryParse(lenStr) ?? 0;
    if (len > 0) return _Meta(len, type);
    throw Exception('Cannot determine Content-Length');
  }
  throw Exception('probe failed after captcha retries');
}

// ---------- bookkeeping (chunked) ----------

// Stable 16-char hex hash of the URL — FNV-1a 64-bit, no external deps.
String hashKey() {
  const int fnvOffset = 0xcbf29ce484222325;
  const int fnvPrime  = 0x100000001b3;
  var h = fnvOffset;
  for (final c in utf8.encode(originalUrl)) {
    h ^= c;
    h = (h * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(16, '0');
}

int _chunkIndex(int absOffset) => absOffset ~/ chunkSize;
int _chunkStart(int chunkIdx) => chunkIdx * chunkSize;
int _chunkExpectedSize(int chunkIdx) {
  final start = _chunkStart(chunkIdx);
  final remaining = meta!.length - start;
  return remaining < chunkSize ? remaining : chunkSize;
}
bool _isChunkComplete(int chunkIdx) =>
    (chunkBytes[chunkIdx] ?? 0) >= _chunkExpectedSize(chunkIdx);

String _chunkPath(int chunkIdx) =>
    '$cacheKeyDir${Platform.pathSeparator}'
    'chunk_${chunkIdx.toString().padLeft(7, '0')}.bin';

// Open (and cache) a writer RAF for the given chunk. Eviction is LRU.
Future<RandomAccessFile> _openChunkForWrite(int chunkIdx) async {
  final cached = _chunkRafs[chunkIdx];
  if (cached != null) {
    _chunkRafLru.remove(chunkIdx);
    _chunkRafLru.add(chunkIdx);
    return cached;
  }
  while (_chunkRafs.length >= maxOpenWriteRafs && _chunkRafLru.isNotEmpty) {
    final oldest = _chunkRafLru.removeAt(0);
    final old = _chunkRafs.remove(oldest);
    if (old != null) {
      try { await old.close(); } catch (_) {}
    }
  }
  final f = File(_chunkPath(chunkIdx));
  if (!f.existsSync()) f.createSync(recursive: true);
  final raf = await f.open(mode: FileMode.append);
  _chunkRafs[chunkIdx] = raf;
  _chunkRafLru.add(chunkIdx);
  return raf;
}

Future<void> _closeChunkRaf(int chunkIdx) async {
  final raf = _chunkRafs.remove(chunkIdx);
  _chunkRafLru.remove(chunkIdx);
  if (raf != null) {
    try { await raf.close(); } catch (_) {}
  }
}

Future<void> _closeAllChunkRafs() async {
  final indices = _chunkRafs.keys.toList();
  for (final idx in indices) {
    await _closeChunkRaf(idx);
  }
  _chunkRafs.clear();
  _chunkRafLru.clear();
}

// Mark a contiguous-from-chunk-start byte range as written. Downloader is
// guaranteed to start at a chunk boundary and write sequentially, so
// per-chunk byte counts always grow monotonically from 0.
void addRange(int start, int end) {
  if (end < start) return;
  var pos = start;
  while (pos <= end) {
    final idx = _chunkIndex(pos);
    final cStart = _chunkStart(idx);
    final cExpected = _chunkExpectedSize(idx);
    final cLastByte = cStart + cExpected - 1;
    final segEnd = end < cLastByte ? end : cLastByte;
    final newBytes = (segEnd - cStart) + 1;
    if (newBytes > (chunkBytes[idx] ?? 0)) {
      chunkBytes[idx] = newBytes;
    }
    if (_isChunkComplete(idx)) {
      haveChunks.add(idx);
      // Writer is sequential — close finished chunk's RAF eagerly so the
      // LRU cap stays focused on actively-growing chunks.
      // ignore: unawaited_futures
      _closeChunkRaf(idx);
    }
    pos = segEnd + 1;
  }
}

bool hasByte(int pos) {
  if (meta == null || pos < 0 || pos >= meta!.length) return false;
  final idx = _chunkIndex(pos);
  final off = pos - _chunkStart(idx);
  return (chunkBytes[idx] ?? 0) > off;
}

// Returns the highest contiguous byte offset reachable from `pos` without
// hitting a missing region. If `pos` itself is missing, returns pos - 1.
int contiguousEndFrom(int pos) {
  if (!hasByte(pos)) return pos - 1;
  var idx = _chunkIndex(pos);
  var avail = _chunkStart(idx) + (chunkBytes[idx] ?? 0) - 1;
  while (_isChunkComplete(idx)) {
    final next = idx + 1;
    if (next * chunkSize >= meta!.length) break;
    final nextBytes = chunkBytes[next] ?? 0;
    if (nextBytes == 0) break;
    avail = _chunkStart(next) + nextBytes - 1;
    if (!_isChunkComplete(next)) break;
    idx = next;
  }
  return avail;
}

// Walk the on-disk cache directory at startup to rebuild chunk bookkeeping.
// Called after `meta` is set so we can decide which chunks are complete.
void _scanChunks() {
  chunkBytes.clear();
  haveChunks.clear();
  final d = Directory(cacheKeyDir);
  if (!d.existsSync()) return;
  for (final entry in d.listSync(followLinks: false)) {
    if (entry is! File) continue;
    final name = entry.uri.pathSegments.isNotEmpty
        ? entry.uri.pathSegments.last
        : entry.path.split(Platform.pathSeparator).last;
    final m = RegExp(r'^chunk_(\d+)\.bin$').firstMatch(name);
    if (m == null) continue;
    final idx = int.parse(m.group(1)!);
    final size = entry.lengthSync();
    chunkBytes[idx] = size;
    if (size >= _chunkExpectedSize(idx)) haveChunks.add(idx);
  }
}

// ---------- janitor: sliding-window eviction ----------
bool _isAnchorChunk(int idx) {
  if (idx < anchorChunksHead) return true;
  final totalChunks = (meta!.length + chunkSize - 1) ~/ chunkSize;
  if (idx >= totalChunks - anchorChunksTail) return true;
  return false;
}

Future<void> _evictOutsideWindow() async {
  if (meta == null) return;
  final readPos = _currentReadOffset;
  final fromByte = readPos - backBufferBytes < 0 ? 0 : readPos - backBufferBytes;
  final toByte = readPos + forwardBufferBytes >= meta!.length
      ? meta!.length - 1
      : readPos + forwardBufferBytes;
  final keepFrom = _chunkIndex(fromByte);
  final keepTo = _chunkIndex(toByte);
  final toEvict = <int>[];
  for (final idx in chunkBytes.keys) {
    if (_isAnchorChunk(idx)) continue; // pinned: MKV cues / MP4 moov
    if (idx < keepFrom || idx > keepTo) toEvict.add(idx);
  }
  if (toEvict.isEmpty) return;
  for (final idx in toEvict) {
    await _closeChunkRaf(idx);
    chunkBytes.remove(idx);
    haveChunks.remove(idx);
    final f = File(_chunkPath(idx));
    try { if (f.existsSync()) f.deleteSync(); } catch (_) {}
  }
}

void _startJanitor() {
  _janitorTimer?.cancel();
  _janitorTimer = Timer.periodic(janitorPeriod, (_) {
    // ignore: unawaited_futures
    _withCache(() => _evictOutsideWindow()).catchError((_) {});
  });
}

void _stopJanitor() {
  _janitorTimer?.cancel();
  _janitorTimer = null;
}

// Trigger a downloader run if the forward window has any missing bytes
// ahead of the current read position. Cheap to call after every reader
// advance — bails immediately if a downloader is already active.
void ensureForwardBuffer() {
  if (downloader != null) return;
  if (meta == null) return;
  final readPos = _currentReadOffset;
  final maxByte = readPos + forwardBufferBytes;
  final endByte = maxByte > meta!.length - 1 ? meta!.length - 1 : maxByte;
  if (endByte < readPos) return;
  final missing = firstMissingByte(readPos, endByte);
  if (missing != null) {
    startDownloader(missing).catchError(
        (e) => stdout.writeln('  ! downloader: $e'));
  }
}

// ---------- single-connection downloader ----------
class _Downloader {
  int writeOffset;
  int requestedFrom;
  _RawResponse? raw;
  bool stopped = false;
  // Pending writes that haven't yet called addRange. Tracked only so that
  // shutdown can wait for flush — not required for correctness of seeking,
  // because requestedFrom + writeOffset already cover the queued range.
  int pendingWrites = 0;
  _Downloader(this.writeOffset) : requestedFrom = writeOffset;
}

_Downloader? downloader;

// Serializes ALL access to `cacheRaf` (writer + every reader). dart:io's
// RandomAccessFile rejects concurrent async ops with "An async operation is
// currently pending", so every setPosition/writeFrom/readInto must chain off
// this future.
Future<void> _writeQueue = Future.value();

Future<T> _withCache<T>(Future<T> Function() op) {
  final completer = Completer<T>();
  _writeQueue = _writeQueue.then((_) async {
    try {
      completer.complete(await op());
    } catch (e, st) {
      completer.completeError(e, st);
    }
  });
  return completer.future;
}

void stopDownloader() {
  final d = downloader;
  if (d == null) return;
  d.stopped = true;
  try { d.raw?.abort(); } catch (_) {}
  downloader = null;
}

Future<void> startDownloader(int fromOffset) async {
  stopDownloader();
  final total = meta!.length;
  if (fromOffset >= total) return;

  // Always start at a chunk boundary so chunk files fill sequentially from
  // byte 0 of the chunk — makes chunkBytes[idx] always equal "contiguous
  // bytes from chunk start". Cost: up to 4 MiB extra bandwidth on a seek.
  final cend = contiguousEndFrom(fromOffset);
  var writeOffset = (cend >= fromOffset) ? cend + 1 : fromOffset;
  final chunkIdx = _chunkIndex(writeOffset);
  final chunkBoundary = _chunkStart(chunkIdx);
  if (writeOffset > chunkBoundary && (chunkBytes[chunkIdx] ?? 0) == 0) {
    // Restart at chunk boundary so the chunk file fills from byte 0.
    writeOffset = chunkBoundary;
  } else if ((chunkBytes[chunkIdx] ?? 0) > 0 &&
             (chunkBytes[chunkIdx] ?? 0) < (writeOffset - chunkBoundary)) {
    // Chunk has partial data but a gap before our position — start at the
    // end of the contiguous prefix.
    writeOffset = chunkBoundary + (chunkBytes[chunkIdx] ?? 0);
  }
  if (writeOffset >= total) return;

  final me = _Downloader(writeOffset);
  downloader = me;

  var attempt = 0;
  while (!me.stopped && attempt <= maxReconnects) {
    _RawResponse raw;
    try {
      stdout.writeln(
          '↓ upstream GET from byte ${me.writeOffset} '
          '(${(me.writeOffset / 1048576).toStringAsFixed(2)} / ${(total / 1048576).toStringAsFixed(2)} MiB)');
      me.requestedFrom = me.writeOffset;
      raw = await followRedirects('GET', {'Range': 'bytes=${me.writeOffset}-'});
      me.raw = raw;
    } catch (e) {
      stdout.writeln('  ! upstream connect failed: $e');
      attempt++;
      final mult = attempt > 3 ? 8 : (1 << attempt);
      await Future.delayed(Duration(milliseconds: reconnectDelay * mult));
      continue;
    }

    final code = raw.res.statusCode;
    if (looksLikeHtml(raw)) {
      final result = await handleHtmlResponse(
          raw, originOf(targetUrl), raw.res.headers.value('retry-after'));
      raw.abort();
      if (result.kind == 'captcha-solved') {
        reresolve();
        await Future.delayed(const Duration(milliseconds: 250));
        continue;
      }
      if (result.kind == 'cf1015') {
        final s = (result.waitMs / 1000).round();
        stdout.writeln(
            '  ! Cloudflare 1015 rate limit — waiting ${s}s then retrying');
        await Future.delayed(Duration(milliseconds: result.waitMs));
        continue;
      }
      stdout.writeln('  ! upstream returned HTML (${result.kind}), backing off');
      reresolve();
      attempt++;
      await Future.delayed(const Duration(milliseconds: reconnectDelay));
      continue;
    }

    if (code == 429) {
      final ra = int.tryParse(raw.res.headers.value('retry-after') ?? '0') ?? 0;
      final body = await readBodyText(raw, maxBytes: 512);
      raw.abort();
      stdout.writeln(
          '  ! 429 from upstream${body.isNotEmpty ? ' — ${body.trim()}' : ''}');

      if (isCloudflare1015(body)) {
        _markCf1015();
        stdout.writeln(
            '  ! Cloudflare 1015 — waiting ${cf1015WaitMs / 1000}s then retrying');
        await Future.delayed(const Duration(milliseconds: cf1015WaitMs));
        continue;
      }

      // "id busy - generate a new download link if stuck" — signed URL is
      // exhausted; re-resolve from originalUrl instead of solving captcha.
      if (_isSignedUrlExhausted(body)) {
        stdout.writeln('  ! signed URL exhausted — re-resolving');
        reresolve();
        await Future.delayed(const Duration(milliseconds: 1000));
        continue;
      }

      stdout.writeln('  ⚡ fetching captcha page to auto-solve …');
      final result = await fetchAndSolveCaptchaPage();
      if (result.kind == 'captcha-solved') {
        reresolve();
        await Future.delayed(const Duration(milliseconds: 250));
        continue;
      }
      if (result.kind == 'cf1015') {
        stdout.writeln(
            '  ! Cloudflare 1015 — waiting ${result.waitMs / 1000}s then retrying');
        await Future.delayed(Duration(milliseconds: result.waitMs));
        continue;
      }
      final wait = ra > 0 ? ra * 1000 : 30000;
      stdout.writeln(
          '  ✗ auto-solve failed — waiting ${(wait / 1000).round()}s before retry');
      attempt++;
      await Future.delayed(Duration(milliseconds: wait));
      continue;
    }

    if (code == 403 || code == 404 || code == 410) {
      stdout.writeln('  ! upstream $code, re-resolving');
      await raw.res.drain<void>().catchError((_) {});
      raw.abort();
      reresolve();
      attempt++;
      await Future.delayed(const Duration(milliseconds: reconnectDelay));
      continue;
    }

    if (code != 200 && code != 206) {
      stdout.writeln('  ! upstream status $code, retrying');
      await raw.res.drain<void>().catchError((_) {});
      raw.abort();
      attempt++;
      await Future.delayed(
          Duration(milliseconds: reconnectDelay * (1 << attempt.clamp(0, 6))));
      continue;
    }

    attempt = 0; // success → reset backoff

    // Stream body, writing as we go.
    final completer = Completer<String>();
    StreamSubscription<List<int>>? sub;
    void resolve(String why) {
      if (!completer.isCompleted) completer.complete(why);
    }
    sub = raw.res.listen((chunk) {
      if (me.stopped) {
        try { sub?.cancel(); raw.abort(); } catch (_) {}
        return;
      }
      // Forward-buffer pause: if we're already (forwardBufferBytes) ahead
      // of where the reader is, stop pulling more from upstream. The
      // reader's ensureForwardBuffer() call will restart us once playback
      // catches up.
      if (me.writeOffset >
          _currentReadOffset + forwardBufferBytes) {
        me.stopped = true;
        try { sub?.cancel(); raw.abort(); } catch (_) {}
        resolve('forward-full');
        return;
      }
      final offset = me.writeOffset;
      final buf = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      me.writeOffset += buf.length;
      // Only mark these bytes as "have" AFTER the write actually completes.
      // Otherwise an MPV read can race the queued write and read zeros from
      // the sparse hole — which shows up as MKV "Cluster found at ..." resync errors.
      // Writes MUST also be serialized — RandomAccessFile rejects concurrent
      // setPosition/writeFrom with "An async operation is currently pending".
      me.pendingWrites++;
      _withCache(() async {
        try {
          // Stream may span multiple chunk boundaries — split & route.
          var p = 0;
          while (p < buf.length) {
            final absPos = offset + p;
            final cIdx = _chunkIndex(absPos);
            final cBoundary = _chunkStart(cIdx);
            final cExpected = _chunkExpectedSize(cIdx);
            final cLastByte = cBoundary + cExpected - 1;
            final maxAbs = cLastByte < (offset + buf.length - 1)
                ? cLastByte
                : (offset + buf.length - 1);
            final segLen = maxAbs - absPos + 1;
            final raf = await _openChunkForWrite(cIdx);
            await raf.writeFrom(buf, p, p + segLen);
            p += segLen;
          }
          addRange(offset, offset + buf.length - 1);
        } catch (e) {
          stdout.writeln('  ! write error: $e');
        } finally {
          me.pendingWrites--;
        }
      });
    },
        onDone: () => resolve('end'),
        onError: (e) {
          stdout.writeln('  ! upstream stream error: $e');
          resolve('error');
        },
        cancelOnError: false);
    raw._sub = sub;

    final why = await completer.future;
    // Drain pending writes so chunkBytes/haveChunks are correct before we
    // decide whether to reconnect / declare done.
    while (me.pendingWrites > 0) {
      await Future.delayed(const Duration(milliseconds: 5));
    }

    if (me.stopped) {
      if (downloader == me) downloader = null;
      return;
    }
    final fullyCached = haveChunks.length ==
            ((total + chunkSize - 1) ~/ chunkSize) &&
        haveChunks.length == chunkBytes.length;
    if (me.writeOffset >= total) {
      if (fullyCached) {
        stdout.writeln(
            '✓ download complete (${(total / 1048576).toStringAsFixed(2)} MiB)');
      } else {
        var got = 0;
        for (final v in chunkBytes.values) got += v;
        stdout.writeln(
            '  upstream reached EOF (${chunkBytes.length} chunk(s) cached, '
            '${(got / 1048576).toStringAsFixed(2)} / ${(total / 1048576).toStringAsFixed(2)} MiB)');
      }
      if (downloader == me) downloader = null;
      return;
    }
    stdout.writeln(
        '  upstream ended ($why) at byte ${me.writeOffset}, reconnecting');
    attempt++;
    await Future.delayed(const Duration(milliseconds: reconnectDelay));
  }

  if (downloader == me) downloader = null;
}

int? firstMissingByte(int start, int end) {
  var pos = start;
  while (pos <= end) {
    if (!hasByte(pos)) return pos;
    pos = contiguousEndFrom(pos) + 1;
  }
  return null;
}

void ensureCovering(int start, int end) {
  final missing = firstMissingByte(start, end);
  if (missing == null) return;

  final dl = downloader;
  if (dl != null) {
    final wo = dl.writeOffset;
    // Bytes between requestedFrom and writeOffset are written-or-queued —
    // don't yank the downloader back over them.
    final queuedCovers = missing >= dl.requestedFrom && missing < wo;
    if (queuedCovers) return;
    final aheadOfMissing = wo > missing;
    final farBehind = wo < missing && (missing - wo) > seekTolerance;
    if (!aheadOfMissing && !farBehind) return;
    stdout.writeln(
        '↪ seek: restart downloader at $missing '
        '(was at $wo, mpv wants $start-$end)');
  }
  startDownloader(missing).catchError(
      (e) => stdout.writeln('  ! downloader: $e'));
}

Future<void> waitForByte(int pos) async {
  final started = DateTime.now().millisecondsSinceEpoch;
  while (true) {
    if (hasByte(pos)) return;
    if (DateTime.now().millisecondsSinceEpoch - started > waitTimeoutMs) {
      throw Exception('timeout waiting for byte $pos');
    }
    await Future.delayed(const Duration(milliseconds: waitPollMs));
  }
}

// ---------- HTTP server ----------
class _Client {
  bool cancelled = false;
  final HttpResponse res;
  _Client(this.res);
}

_Client? activeClient;

class _Range {
  final int start, end;
  _Range(this.start, this.end);
}

_Range? parseRangeHeader(String? header, int total) {
  if (header == null) return null;
  final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
  if (m == null) return null;
  final sStr = m.group(1)!, eStr = m.group(2)!;
  int? start = sStr.isEmpty ? null : int.parse(sStr);
  int? end = eStr.isEmpty ? null : int.parse(eStr);
  if (start == null && end == null) return null;
  if (start == null) {
    start = total - end!;
    end = total - 1;
  }
  if (end == null || end >= total) end = total - 1;
  if (start < 0 || start > end || start >= total) return null;
  return _Range(start, end);
}

Future<void> handle(HttpRequest req) async {
  final res = req.response;
  if (req.method != 'GET' && req.method != 'HEAD') {
    res.statusCode = 405;
    await res.close();
    return;
  }
  final total = meta!.length;
  final range = parseRangeHeader(req.headers.value('range'), total);
  int start, end, status;
  if (range != null) { start = range.start; end = range.end; status = 206; }
  else               { start = 0; end = total - 1; status = 200; }

  final length = end - start + 1;
  res.statusCode = status;
  res.headers.set(HttpHeaders.contentTypeHeader, meta!.type);
  res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  res.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
  res.headers.set(HttpHeaders.contentLengthHeader, length.toString());
  if (status == 206) {
    res.headers.set('Content-Range', 'bytes $start-$end/$total');
  }
  if (req.method == 'HEAD') {
    await res.close();
    return;
  }

  stdout.writeln(
      '\n→ MPV range $start-$end (${(length / 1048576).toStringAsFixed(2)} MiB)');

  // Cancel any previous client — MPV opens a new connection per seek.
  if (activeClient != null) {
    activeClient!.cancelled = true;
    try { await activeClient!.res.close(); } catch (_) {}
  }
  final me = _Client(res);
  activeClient = me;
  // Detect MPV-side disconnect.
  unawaited(res.done.catchError((_) {}).whenComplete(() => me.cancelled = true));

  // Update the janitor's notion of where the player actually is — eviction
  // and downloader pause both pivot on this. Set BEFORE ensureCovering so
  // the downloader's first runway anchors at the new seek position.
  _currentReadOffset = start;
  ensureCovering(start, end);
  ensureForwardBuffer();

  final readBuf = Uint8List(256 * 1024);
  var pos = start;
  try {
    while (pos <= end && !me.cancelled) {
      if (!hasByte(pos)) {
        await waitForByte(pos);
        if (me.cancelled) break;
      }
      final cend = contiguousEndFrom(pos);
      final rangeEnd = cend < end ? cend : end;
      var remaining = rangeEnd - pos + 1;
      while (remaining > 0 && !me.cancelled) {
        final want = remaining < readBuf.length ? remaining : readBuf.length;
        final readPos = pos;
        final bytesRead = await _withCache(() async {
          // Don't cross chunk boundaries in a single read — keeps the
          // chunk-file open simple and matches the writer's split logic.
          final cIdx = _chunkIndex(readPos);
          final cBoundary = _chunkStart(cIdx);
          final cExpected = _chunkExpectedSize(cIdx);
          final cLastByte = cBoundary + cExpected - 1;
          final chunkOff = readPos - cBoundary;
          final chunkAvail = chunkBytes[cIdx] ?? 0;
          if (chunkOff >= chunkAvail) return 0;
          final canFromChunk = chunkAvail - chunkOff;
          final inChunkLimit = cLastByte - readPos + 1;
          var capped = want;
          if (canFromChunk < capped) capped = canFromChunk;
          if (inChunkLimit < capped) capped = inChunkLimit;
          final f = File(_chunkPath(cIdx));
          if (!f.existsSync()) return 0;
          final raf = await f.open(mode: FileMode.read);
          try {
            await raf.setPosition(chunkOff);
            return await raf.readInto(readBuf, 0, capped);
          } finally {
            try { await raf.close(); } catch (_) {}
          }
        });
        if (bytesRead <= 0) break;
        res.add(Uint8List.sublistView(readBuf, 0, bytesRead));
        await res.flush();
        pos += bytesRead;
        remaining -= bytesRead;
        _currentReadOffset = pos;
        if (!me.cancelled && pos <= end) {
          ensureCovering(pos, end);
          ensureForwardBuffer();
        }
      }
    }
    if (!me.cancelled) await res.close();
  } catch (err) {
    stderr.writeln('  ! response error: $err');
    try { await res.close(); } catch (_) {}
  } finally {
    if (activeClient == me) activeClient = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PUBLIC ENTRY POINTS  (mobile-friendly replacement for `main()`)
// ─────────────────────────────────────────────────────────────────────────────
//
// Single-instance proxy. Call [start111477Proxy] with the upstream signed URL
// and any optional headers. It returns a `http://127.0.0.1:8888/` URL that
// MPV (via media_kit) can stream — supporting Range requests and seeking.
// When playback ends, call [stop111477Proxy] to halt the downloader, close
// the local server, and delete the on-disk cache so the device doesn't fill.

HttpServer? _server;
StreamSubscription<HttpRequest>? _serverSub;
bool _running = false;

Future<String> start111477Proxy(
  String upstreamUrl, {
  Map<String, String>? headers,
}) async {
  // Wait for any in-flight stop to finish (file deletion, port release).
  // Hard ceiling so a stuck stop can't block forever.
  if (_stopFuture != null) {
    try {
      await _stopFuture!.timeout(const Duration(seconds: 12));
    } catch (_) {
      stdout.writeln('[111477] previous stop timed out — forcing reset');
      _stopFuture = null;
      _running = false;
    }
  }
  // If a previous session is still alive, tear it down first.
  if (_running) {
    await stop111477Proxy();
  }

  stdout.writeln('[111477] starting proxy …');

  // Reset per-session state.
  _stopping = false;
  _cf1015UntilMs = 0;
  chunkBytes.clear();
  haveChunks.clear();
  await _closeAllChunkRafs();
  meta = null;
  downloader = null;
  activeClient = null;
  _currentReadOffset = 0;
  _stopJanitor();
  _inflightCaptchaSolve = null;
  _writeQueue = Future.value();

  originalUrl = upstreamUrl;
  targetUrl = upstreamUrl;
  if (headers != null) {
    headers.forEach((k, v) => extraHeaders[k] = v);
  }

  // Mobile-safe cache directory — temporary so the OS can reclaim it.
  final tmp = await getTemporaryDirectory();
  cacheDir = '${tmp.path}${Platform.pathSeparator}site111477_cache';
  final root = Directory(cacheDir);
  if (!root.existsSync()) {
    root.createSync(recursive: true);
  } else {
    // Sweep stale per-key directories from previous sessions — sliding
    // window doesn't try to resume across runs (the chunks would mostly
    // have been evicted anyway).
    try {
      for (final entry in root.listSync(followLinks: false)) {
        try {
          if (entry is Directory) {
            entry.deleteSync(recursive: true);
          } else if (entry is File) {
            entry.deleteSync();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  stdout.writeln('Probing upstream: $originalUrl');
  meta = await probe();
  stdout.writeln(
      '  Content-Length: ${meta!.length} (${(meta!.length / 1048576).toStringAsFixed(2)} MiB)');
  stdout.writeln('  Content-Type:   ${meta!.type}');

  // Per-URL chunk directory — lets the janitor wipe everything for the
  // current stream by deleting one folder.
  cacheKeyDir = '$cacheDir${Platform.pathSeparator}${hashKey()}';
  Directory(cacheKeyDir).createSync(recursive: true);
  _scanChunks();
  if (chunkBytes.isNotEmpty) {
    var got = 0;
    for (final v in chunkBytes.values) got += v;
    stdout.writeln(
        '  resumed: ${chunkBytes.length} chunk(s), '
        '${(got / 1048576).toStringAsFixed(2)} MiB on disk');
  }
  stdout.writeln('  cache dir:      $cacheKeyDir');
  stdout.writeln(
      '  sliding window: ${backBufferBytes ~/ (1024 * 1024)} MiB back / '
      '${forwardBufferBytes ~/ (1024 * 1024)} MiB forward');

  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  _boundPort = _server!.port;
  _running = true;
  stdout.writeln('\nProxy ready at http://127.0.0.1:$_boundPort/');

  // Sliding-window janitor — evicts chunks outside the keep window every
  // few seconds so disk usage stays bounded.
  _startJanitor();

  // ignore: unawaited_futures
  startDownloader(0).catchError(
      (e) => stdout.writeln('  ! downloader: $e'));

  // Only register SIGINT on platforms that support it (desktop). Mobile
  // (Android/iOS) doesn't expose process signals — we rely on explicit
  // [stop111477Proxy] calls when the player closes.
  if (!Platform.isAndroid && !Platform.isIOS) {
    try {
      ProcessSignal.sigint.watch().listen((_) async {
        await stop111477Proxy();
      });
    } catch (_) { /* not supported */ }
  }

  _serverSub = _server!.listen((req) {
    handle(req);
  });

  // Don't return until either:
  //   * the cache already has the very first byte (resume), or
  //   * the downloader has produced at least one byte from upstream.
  // Otherwise media_kit/MPV opens the URL, reads zero bytes, and aborts
  // with "Failed to open" before the captcha-solver / 1015-wait completes.
  final waitStarted = DateTime.now().millisecondsSinceEpoch;
  while (!hasByte(0)) {
    if (!_running) {
      throw StateError('111477 proxy stopped before first byte');
    }
    if (DateTime.now().millisecondsSinceEpoch - waitStarted > 90000) {
      // Give up after 90s of no progress — caller should fall back.
      await stop111477Proxy();
      throw TimeoutException(
          '111477 proxy: no upstream bytes within 90s', const Duration(seconds: 90));
    }
    await Future.delayed(const Duration(milliseconds: 200));
  }
  stdout.writeln('  first byte ready — handing URL to player');

  return 'http://127.0.0.1:$_boundPort/';
}

/// The port the proxy is currently bound to (0 if not running).
int get site111477ProxyPort => _boundPort;

/// The full base URL of the running proxy, or null if not running.
String? get site111477ProxyUrl =>
    _boundPort == 0 ? null : 'http://127.0.0.1:$_boundPort/';

// Tracks any in-flight stop so a concurrent start() (or a second stop call)
// awaits the same future instead of fighting over the same files / port.
Future<void>? _stopFuture;

Future<void> stop111477Proxy() async {
  // If a stop is already in progress, just await it.
  if (_stopFuture != null) return _stopFuture;
  if (!_running) return;
  final c = Completer<void>();
  _stopFuture = c.future;
  try {
    await _doStop();
  } finally {
    c.complete();
    _stopFuture = null;
  }
}

Future<void> _doStop() async {
  stdout.writeln('[111477] stopping proxy …');
  _running = false;
  _stopping = true;
  // Clear the global CF cooldown so the polling loops in awaiters break out
  // immediately and a subsequent start() doesn't inherit a stale deadline.
  _cf1015UntilMs = 0;
  stopDownloader();
  _stopJanitor();
  // Cancel any in-flight clients so their reader loops stop touching the
  // chunk RAFs.
  // Don't await res.close() — MPV's socket may already be torn down on the
  // peer side, and close() can hang forever waiting for TCP drain.
  try {
    activeClient?.cancelled = true;
    // ignore: unawaited_futures
    activeClient?.res.close().catchError((_) {});
  } catch (_) {}
  activeClient = null;
  try {
    await _serverSub?.cancel().timeout(const Duration(seconds: 2));
  } catch (_) {}
  _serverSub = null;
  try {
    await _server
        ?.close(force: true)
        .timeout(const Duration(seconds: 3));
  } catch (_) {}
  _server = null;
  // Drain pending cache ops (with a hard ceiling — a stuck write must NEVER
  // block teardown, otherwise the next start() deadlocks awaiting us).
  try {
    await _writeQueue.timeout(const Duration(seconds: 3));
  } catch (_) {}
  try {
    await _closeAllChunkRafs().timeout(const Duration(seconds: 3));
  } catch (_) {}
  _writeQueue = Future.value();
  // Delete the cache directory so we don't fill the device. Windows can
  // hold the file handle for several seconds after close() (antivirus,
  // indexer, dart:io finalizer). Try a handful of fast retries inline so
  // common cases succeed before we return; if that fails, schedule a
  // background sweep that won't block player teardown / app exit. The
  // next start() also clears any leftover files at the same path.
  Future<bool> tryDelete({required int attempts, required int delayMs}) async {
    for (var i = 0; i < attempts; i++) {
      var allClean = true;
      // Wipe the per-stream chunk directory first, then the parent cache
      // directory (which may contain leftovers from previous sessions).
      for (final path in [cacheKeyDir, cacheDir]) {
        if (path.isEmpty) continue;
        try {
          final d = Directory(path);
          if (!d.existsSync()) continue;
          // Best-effort per-entry delete first — often succeeds even when
          // a recursive directory delete fails.
          try {
            for (final entry
                in d.listSync(recursive: true, followLinks: false)) {
              if (entry is File) {
                try { await entry.delete(); } catch (_) {}
              }
            }
          } catch (_) {}
          try {
            await d.delete(recursive: true);
          } catch (_) {}
          // VERIFY — on Windows `delete()` can return success while files
          // are in pending-delete state, and the dir still contains
          // entries. Only declare victory if the dir is actually gone OR
          // empty of files.
          if (!d.existsSync()) continue;
          try {
            final remaining = d
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
                .length;
            if (remaining == 0) {
              try { await d.delete(recursive: true); } catch (_) {}
              continue;
            }
          } catch (_) {}
          allClean = false;
        } catch (_) {
          allClean = false;
        }
      }
      if (allClean) return true;
      await Future.delayed(Duration(milliseconds: delayMs));
    }
    return false;
  }

  var deleted = await tryDelete(attempts: 6, delayMs: 250); // ≤1.5s inline
  if (!deleted) {
    // Don't block teardown — sweep in the background.
    stdout.writeln(
        '  ! cache busy, deleting in background (will retry up to 60s)');
    // ignore: unawaited_futures
    () async {
      final ok = await tryDelete(attempts: 120, delayMs: 500); // 60s
      stdout.writeln(ok
          ? '[111477] background cache cleanup succeeded'
          : '[111477] background cache cleanup gave up (will retry next start)');
    }();
    deleted = true; // treat as cleaned for the immediate stop log
  }
  if (deleted) {
    stdout.writeln('[111477] proxy stopped, cache deleted');
  } else {
    stdout.writeln('[111477] proxy stopped (cache delete failed)');
  }
  chunkBytes.clear();
  haveChunks.clear();
  meta = null;
  _boundPort = 0;
  _currentReadOffset = 0;
}

bool get is111477ProxyRunning => _running || _stopFuture != null;

/// Best-effort wipe of the on-disk 111477 cache directory. Safe to call at
/// app exit even if the proxy was never started — it just walks the temp
/// directory and removes anything left over from previous runs (orphaned
/// cache files from force-kills, crashes, or Windows file-lock contention
/// that prevented the normal stop() cleanup from completing).
///
/// Never throws. Verifies the directory is actually empty/gone after each
/// attempt — on Windows `Directory.delete()` can succeed while files are
/// still in pending-delete state.
Future<void> purge111477Cache() async {
  try {
    final tmp = await getTemporaryDirectory();
    final dirPath = '${tmp.path}${Platform.pathSeparator}site111477_cache';
    final dir = Directory(dirPath);
    for (var i = 0; i < 12; i++) {
      try {
        if (!dir.existsSync()) return;
        // Per-file delete first.
        try {
          for (final entry in dir.listSync(recursive: true, followLinks: false)) {
            if (entry is File) {
              try { entry.deleteSync(); } catch (_) {}
            }
          }
        } catch (_) {}
        try { await dir.delete(recursive: true); } catch (_) {}
        // Verify — pending-delete on Windows.
        if (!dir.existsSync()) return;
        try {
          final remaining = dir
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .length;
          if (remaining == 0) {
            try { await dir.delete(recursive: true); } catch (_) {}
            return;
          }
        } catch (_) {}
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 250));
    }
  } catch (_) {
    // best effort — never throw at shutdown
  }
}
