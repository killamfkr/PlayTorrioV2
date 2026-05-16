import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../features/iptv/playtorrio_tv/data/iptv_network.dart';
import '../features/iptv/playtorrio_tv/data/models.dart';
import '../features/iptv/playtorrio_tv/data/storage.dart';
import '../utils/lan_ipv4_picker_io.dart';
import 'settings_service.dart';

/// Serves a minimal SiliconDust-style HTTP surface on the LAN so apps that
/// expect HDHomeRun-style `discover.json`, `lineup.json`, and `/auto/v…` tune
/// URLs can play **PT TV Guide** channels (starred Live rows from PT IPTV).
///
/// Binds [InternetAddress.anyIPv4] so other devices on the Wi‑Fi can connect.
class PtTvHdhomerunServer {
  static final PtTvHdhomerunServer _instance = PtTvHdhomerunServer._internal();
  factory PtTvHdhomerunServer() => _instance;
  PtTvHdhomerunServer._internal();

  HttpServer? _server;
  int _boundPort = 0;

  /// Raw client for upstream IPTV; redirects followed manually for a reliable final URL.
  HttpClient? _upstreamHttp;

  static const _ptclipTokenTtl = Duration(hours: 4);
  static const _ptclipTokenMaxEntries = 600;
  /// Long `u=` query strings hit reverse-proxy / server limits (Plex → ffmpeg → us).
  static const _ptclipMaxEncodedQueryLen = 2000;

  final Map<String, ({String url, DateTime expires, DateTime insertedAt})>
      _ptclipTokenToUrl = {};

  HttpClient get _upstreamRaw {
    _upstreamHttp ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 45)
      ..maxConnectionsPerHost = 64;
    return _upstreamHttp!;
  }

  /// Advertised to clients (Plex, etc.); each slot accepts concurrent streams — we
  /// do not serialize tuners like real hardware.
  static const int advertisedTunerCount = 8;

  /// 1-based virtual channel index → Xtream stream URL for the current lineup.
  Map<int, String> _virtToUrl = {};

  /// Built together with [_virtToUrl] so lineup.json does not re-fetch Xtream per row.
  List<({TvGuideSlot slot, String url})> _lineupRows = [];

  /// ATSC-style virtual channel (e.g. `4.1`); major index maps to our 1-based lineup slot.
  static final _autoPath = RegExp(r'^/auto/v([\d.]+)$');
  static final _tunerVirtPath = RegExp(r'^/tuner(\d+)/v([\d.]+)$');
  static final _tunerAutoVirtPath = RegExp(r'^/tuner(\d+)/auto/v([\d.]+)$');

  static int? _virtMajorFromPath(String virt) {
    final dot = virt.indexOf('.');
    final head = dot < 0 ? virt : virt.substring(0, dot);
    return int.tryParse(head);
  }

  bool get isRunning => _server != null;
  int get boundPort => _boundPort;

  Future<String?> describeLanBaseUrl() async {
    final settings = SettingsService();
    final port = isRunning ? _boundPort : await settings.getIptvPtHdhomerunLanPort();
    final override = await settings.getIptvPtHdhomerunLanIpv4Override();
    final ip = await resolvePreferredLanIpv4(override);
    if (ip == null) return null;
    return 'http://$ip:$port';
  }

  /// Reads [SettingsService] and starts or stops the listener.
  Future<void> applyFromSettings() async {
    if (kIsWeb) return;
    final settings = SettingsService();
    final on = await settings.getIptvPtHdhomerunLanBroadcastEnabled();
    if (!on) {
      await stop();
      return;
    }
    final port = await settings.getIptvPtHdhomerunLanPort();
    await _ensureStarted(port);
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _boundPort = 0;
    _virtToUrl = {};
    _lineupRows = [];
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (e) {
        debugPrint('[PtTvHdhr] stop: $e');
      }
    }
    try {
      _upstreamHttp?.close(force: true);
    } catch (_) {}
    _upstreamHttp = null;
    _ptclipTokenToUrl.clear();
  }

  Future<void> _ensureStarted(int preferredPort) async {
    if (_server != null && _boundPort == preferredPort) {
      await _rebuildLineupMap();
      return;
    }
    await stop();

    var handler = Pipeline()
        .addMiddleware(_corsMiddleware)
        .addHandler(_dispatch);

    const fallbacks = 24;
    for (var i = 0; i < fallbacks; i++) {
      final p = preferredPort + i;
      if (p > 65535) break;
      try {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          p,
        );
        _boundPort = p;
        if (p != preferredPort) {
          debugPrint('[PtTvHdhr] Port $preferredPort busy; bound $p instead');
          await SettingsService().setIptvPtHdhomerunLanPort(p);
        }
        debugPrint('[PtTvHdhr] Listening on 0.0.0.0:$_boundPort');
        await _rebuildLineupMap();
        return;
      } catch (e) {
        debugPrint('[PtTvHdhr] bind :$p failed: $e');
      }
    }
    debugPrint('[PtTvHdhr] Could not bind any port near $preferredPort');
  }

  Middleware get _corsMiddleware {
    const headers = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, HEAD, POST, OPTIONS',
      'Access-Control-Allow-Headers': '*',
    };
    return (Handler inner) {
      return (Request req) async {
        if (req.method == 'OPTIONS') {
          return Response.ok('', headers: headers);
        }
        final res = await inner(req);
        final merged = <String, String>{...res.headers, ...headers};
        return res.change(headers: merged);
      };
    };
  }

  String _normPath(Request request) {
    var p = request.requestedUri.path;
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  Future<Response> _dispatch(Request request) async {
    final path = _normPath(request);
    if (path == '/discover.json' && request.method == 'GET') {
      return _handleDiscover(request);
    }
    if ((path == '/' || path.isEmpty) && request.method == 'GET') {
      return Response(
        302,
        headers: {'Location': '${request.requestedUri.origin}/discover.json'},
      );
    }
    if (path == '/lineup.json' && request.method == 'GET') {
      return _handleLineup(request);
    }
    if (path == '/lineup_status.json' && request.method == 'GET') {
      return _handleLineupStatus();
    }
    if (path == '/lineup.m3u' && request.method == 'GET') {
      return _handleLineupM3u(request);
    }
    if (path == '/lineup.post' &&
        (request.method == 'GET' || request.method == 'POST')) {
      return _handleLineupPost(request);
    }
    if (path == '/ptclip' &&
        (request.method == 'GET' || request.method == 'HEAD')) {
      return _handlePtClip(request);
    }
    final tunerAuto = _tunerAutoVirtPath.firstMatch(path);
    if (tunerAuto != null &&
        (request.method == 'GET' || request.method == 'HEAD')) {
      return _handleAutoTune(request, tunerAuto.group(2)!);
    }
    final tunerVirt = _tunerVirtPath.firstMatch(path);
    if (tunerVirt != null &&
        (request.method == 'GET' || request.method == 'HEAD')) {
      return _handleAutoTune(request, tunerVirt.group(2)!);
    }
    final m = _autoPath.firstMatch(path);
    if (m != null &&
        (request.method == 'GET' || request.method == 'HEAD')) {
      return _handleAutoTune(request, m.group(1)!);
    }
    return Response.notFound('Not found');
  }

  Future<Response> _handleAutoTune(Request request, String virtStr) async {
    final n = _virtMajorFromPath(virtStr);
    if (n == null || n < 1) {
      return Response.notFound('Bad channel');
    }
    final url = _virtToUrl[n];
    if (url == null || url.isEmpty) {
      return Response.notFound('Channel not in lineup (open PT TV Guide in app)');
    }
    // Plex/ffmpeg probe with HEAD; many Xtream/CDN URLs reject HEAD → "could not tune".
    if (request.method == 'HEAD') {
      return _syntheticStreamHead(url);
    }
    return _proxyMedia(request, url, request.requestedUri.origin);
  }

  Future<Response> _handlePtClip(Request request) async {
    String target;
    final token = request.url.queryParameters['t'];
    if (token != null && token.isNotEmpty) {
      final ent = _ptclipTokenToUrl[token];
      if (ent == null || ent.expires.isBefore(DateTime.now())) {
        return Response(404, body: 'Unknown or expired clip token');
      }
      target = ent.url;
    } else {
      final raw = request.url.queryParameters['u'];
      if (raw == null || raw.isEmpty) {
        return Response(400, body: 'Missing u or t');
      }
      try {
        target = Uri.decodeComponent(raw);
      } catch (_) {
        target = raw;
      }
    }
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      return Response(400, body: 'Invalid URL');
    }
    if (request.method == 'HEAD') {
      return _syntheticStreamHead(target);
    }
    return _proxyMedia(request, target, request.requestedUri.origin);
  }

  Future<Response> _handleDiscover(Request request) async {
    final origin = request.requestedUri.origin;
    // Plex and other clients expect SiliconDust-shaped metadata.
    final body = json.encode({
      'FriendlyName': 'PlayTorrio PT TV Guide',
      'ModelNumber': 'HDHR4-2US',
      'FirmwareName': 'hdhomerun4_atsc',
      'FirmwareVersion': '20240101',
      'DeviceID': '42545456',
      'DeviceAuth': '',
      'BaseURL': origin,
      'LineupURL': '$origin/lineup.json',
      'TunerCount': advertisedTunerCount,
    });
    return Response.ok(body, headers: {'Content-Type': 'application/json'});
  }

  Response _handleLineupStatus() {
    // ScanPossible 0: Plex must not run an OTA-style scan (we have no RF scan).
    // ScanPossible 1 caused Plex to POST lineup.post and wait on a long rebuild.
    final body = json.encode({
      'ScanInProgress': 0,
      'ScanPossible': 0,
      'Source': 'Cable',
      'SourceList': ['Cable'],
    });
    return Response.ok(body, headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _handleLineupPost(Request request) async {
    if (kDebugMode) {
      debugPrint(
        '[PtTvHdhr] lineup.post ${request.method} q=${request.requestedUri.query}',
      );
    }
    // Answer immediately; refresh lineup in the background so Plex never blocks.
    final scan = request.url.queryParameters['scan'];
    if (scan == 'start' || scan == 'abort') {
      unawaited(_rebuildLineupMap());
    }
    return Response.ok('OK', headers: {'Content-Type': 'text/plain'});
  }

  Future<List<Map<String, dynamic>>> _buildLineupList(Request request) async {
    await _rebuildLineupMap();
    final origin = request.requestedUri.origin;
    final list = <Map<String, dynamic>>[];
    for (var i = 0; i < _lineupRows.length; i++) {
      final k = i + 1;
      final row = _lineupRows[i];
      // Plex/SiliconDust expect ATSC-style major.minor; URL path must match GuideNumber.
      list.add({
        'GuideNumber': '$k.1',
        'GuideName': row.slot.stream.name,
        'HD': 1,
        'DRM': 0,
        'URL': '$origin/auto/v$k.1',
        'LogoURL': row.slot.stream.icon,
        'Favorite': 0,
      });
    }
    return list;
  }

  Future<Response> _handleLineup(Request request) async {
    final list = await _buildLineupList(request);
    return Response.ok(
      json.encode(list),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _handleLineupM3u(Request request) async {
    final list = await _buildLineupList(request);
    final buf = StringBuffer('#EXTM3U\n');
    for (final row in list) {
      final name = row['GuideName'] as String? ?? 'TV';
      final url = row['URL'] as String? ?? '';
      final logo = row['LogoURL'] as String? ?? '';
      final gn = row['GuideNumber'] as String? ?? '';
      if (url.isEmpty) continue;
      final logoAttr =
          logo.isNotEmpty ? ' tvg-logo="${_escapeM3uAttr(logo)}"' : '';
      buf.write(
        '#EXTINF:-1 tvg-id="$gn" tvg-name="${_escapeM3uAttr(name)}"$logoAttr'
        ',${_escapeM3uName(name)}\n$url\n',
      );
    }
    return Response.ok(
      buf.toString(),
      headers: {'Content-Type': 'audio/x-mpegurl'},
    );
  }

  String _escapeM3uAttr(String s) =>
      s.replaceAll('\\', r'\\').replaceAll('"', r'\"');

  String _escapeM3uName(String s) => s.replaceAll(',', ' ');

  /// HEAD probe for Plex/ffmpeg — do not forward HEAD upstream (often 403/405 on IPTV).
  Response _syntheticStreamHead(String targetUrl) {
    final lower = targetUrl.toLowerCase();
    final isHls =
        lower.contains('.m3u8') || lower.contains('.m3u');
    final ct = isHls
        ? 'application/vnd.apple.mpegurl'
        : 'video/mp2t';
    return Response(
      200,
      headers: {
        'Content-Type': ct,
        'Content-Length': '0',
        'Accept-Ranges': 'bytes',
        'Access-Control-Allow-Origin': '*',
      },
    );
  }

  Future<void> _rebuildLineupMap() async {
    final slots = await _loadTvGuideSlots();
    final rows = <({TvGuideSlot slot, String url})>[];
    for (final slot in slots) {
      final u = IptvClient.streamUrl(slot.portal.portal, slot.stream);
      if (u.isNotEmpty) {
        rows.add((slot: slot, url: u));
      }
    }
    _lineupRows = rows;
    _virtToUrl = {
      for (var i = 0; i < rows.length; i++) i + 1: rows[i].url,
    };
  }

  Future<List<TvGuideSlot>> _loadTvGuideSlots() async {
    final verified = await IptvStore.load();
    final slots = <TvGuideSlot>[];
    for (final v in verified) {
      final favIds = await IptvBrowserFavoritesStore.load(v.key);
      if (favIds.isEmpty) continue;
      List<IptvStream> streams;
      try {
        streams = await IptvClient.streams(v.portal, IptvSection.live, '');
      } catch (_) {
        continue;
      }
      final byId = {for (final s in streams) s.streamId: s};
      for (final id in favIds) {
        var stream = byId[id];
        if (stream == null && id.isNotEmpty) {
          try {
            streams = await IptvClient.streams(v.portal, IptvSection.live, '');
            stream = {for (final s in streams) s.streamId: s}[id];
          } catch (_) {}
        }
        if (stream != null && stream.kind == 'live') {
          slots.add(TvGuideSlot(portal: v, stream: stream));
        } else if (id.isNotEmpty) {
          slots.add(
            TvGuideSlot(
              portal: v,
              stream: IptvStream(
                streamId: id,
                name: 'Starred channel',
                icon: '',
                categoryId: '',
                containerExt: 'ts',
                kind: 'live',
              ),
            ),
          );
        }
      }
    }
    slots.sort((a, b) {
      final pn = a.portal.name.compareTo(b.portal.name);
      if (pn != 0) return pn;
      return a.stream.name.compareTo(b.stream.name);
    });
    return slots;
  }

  void _prunePtclipTokens() {
    final now = DateTime.now();
    _ptclipTokenToUrl.removeWhere((_, v) => v.expires.isBefore(now));
    while (_ptclipTokenToUrl.length > _ptclipTokenMaxEntries) {
      String? oldestKey;
      DateTime? oldestAt;
      for (final e in _ptclipTokenToUrl.entries) {
        if (oldestAt == null || e.value.insertedAt.isBefore(oldestAt)) {
          oldestAt = e.value.insertedAt;
          oldestKey = e.key;
        }
      }
      if (oldestKey == null) break;
      _ptclipTokenToUrl.remove(oldestKey);
    }
  }

  String _newClipToken() {
    final r = Random.secure();
    final bytes = List<int>.generate(18, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _clip(String origin, String u) {
    final enc = Uri.encodeComponent(u);
    if (enc.length <= _ptclipMaxEncodedQueryLen) {
      return '$origin/ptclip?u=$enc';
    }
    _prunePtclipTokens();
    String token;
    do {
      token = _newClipToken();
    } while (_ptclipTokenToUrl.containsKey(token));
    final now = DateTime.now();
    _ptclipTokenToUrl[token] = (
      url: u,
      expires: now.add(_ptclipTokenTtl),
      insertedAt: now,
    );
    return '$origin/ptclip?t=$token';
  }

  String _resolveHlsUriRef(String uri, String upstreamOrigin, String basePath) {
    if (uri.startsWith('http')) return uri;
    if (uri.startsWith('/')) return '$upstreamOrigin$uri';
    return '$basePath$uri';
  }

  String _rewriteHlsTagLine(
    String line,
    String selfOrigin,
    String upstreamOrigin,
    String basePath,
  ) {
    if (!line.contains('URI=')) return line;
    var out = line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) {
      final uri = m.group(1)!;
      final full = _resolveHlsUriRef(uri, upstreamOrigin, basePath);
      return 'URI="${_clip(selfOrigin, full)}"';
    });
    out = out.replaceAllMapped(RegExp(r"URI='([^']+)'"), (m) {
      final uri = m.group(1)!;
      final full = _resolveHlsUriRef(uri, upstreamOrigin, basePath);
      return 'URI="${_clip(selfOrigin, full)}"';
    });
    return out;
  }

  void _applyUpstreamBrowserHeaders(HttpClientRequest req, Uri forUri) {
    final o =
        '${forUri.scheme}://${forUri.host}${forUri.hasPort ? ':${forUri.port}' : ''}';
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );
    req.headers.set(HttpHeaders.refererHeader, '$o/');
    req.headers.set('origin', o);
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  }

  /// Follow redirects manually so the final playlist URL is always known (HLS
  /// relative URLs). Also refreshes Referer/Origin per hop for picky CDNs.
  Future<({Uri finalUri, HttpClientResponse ioRes})> _upstreamOpenFollowed(
    String method,
    Uri initial,
  ) async {
    var current = initial;
    HttpClientResponse? res;
    for (var hop = 0; hop < 16; hop++) {
      final ioReq = await _upstreamRaw.openUrl(method, current);
      ioReq.followRedirects = false;
      _applyUpstreamBrowserHeaders(ioReq, current);
      res = await ioReq.close();
      if (res.statusCode >= 300 && res.statusCode < 400) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        try {
          await res.drain();
        } catch (_) {}
        if (loc == null) {
          return (finalUri: current, ioRes: res);
        }
        current = current.resolve(Uri.parse(loc));
        continue;
      }
      return (finalUri: current, ioRes: res);
    }
    return (finalUri: current, ioRes: res!);
  }

  Future<Response> _proxyMedia(
    Request request,
    String targetUrl,
    String selfOrigin,
  ) async {
    final uri = Uri.parse(targetUrl);

    late final Uri finalUri;
    late final HttpClientResponse ioRes;
    try {
      final opened = await _upstreamOpenFollowed(request.method, uri);
      finalUri = opened.finalUri;
      ioRes = opened.ioRes;
    } catch (e) {
      return Response.internalServerError(body: 'Upstream: $e');
    }

    if (ioRes.statusCode >= 400 && kDebugMode) {
      debugPrint(
        '[PtTvHdhr] upstream HTTP ${ioRes.statusCode} for $targetUrl',
      );
    }

    final effectiveTarget = finalUri.toString();
    final upstreamOrigin =
        '${finalUri.scheme}://${finalUri.host}${finalUri.hasPort ? ':${finalUri.port}' : ''}';
    final slash = effectiveTarget.lastIndexOf('/');
    final basePath =
        slash >= 0 ? effectiveTarget.substring(0, slash + 1) : '$effectiveTarget/';

    final ctFull = ioRes.headers.value('content-type') ?? '';
    final ctLower = ctFull.toLowerCase();
    final lowerUrl = effectiveTarget.toLowerCase();
    final looksLikeHls = ctLower.contains('mpegurl') ||
        ctLower.contains('x-mpegurl') ||
        lowerUrl.contains('.m3u8');

    if (looksLikeHls && request.method == 'GET') {
      final text = await ioRes.transform(utf8.decoder).join();
      if (ioRes.statusCode >= 400) {
        return Response(ioRes.statusCode, body: text);
      }
      final out = text.split('\n').map((rawLine) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) {
          return _rewriteHlsTagLine(line, selfOrigin, upstreamOrigin, basePath);
        }
        final full = line.startsWith('http')
            ? line
            : line.startsWith('/')
                ? '$upstreamOrigin$line'
                : '$basePath$line';
        return _clip(selfOrigin, full);
      }).join('\n');
      return Response.ok(
        out,
        headers: {
          'Content-Type': 'application/vnd.apple.mpegurl',
          'Access-Control-Allow-Origin': '*',
        },
      );
    }

    final outHeaders = <String, String>{
      'Access-Control-Allow-Origin': '*',
      'Accept-Ranges': 'bytes',
      'Content-Type': ctFull.isEmpty ? 'application/octet-stream' : ctFull,
    };
    for (final k in const [
      'content-length',
      'content-range',
      'accept-ranges',
    ]) {
      final v = ioRes.headers.value(k);
      if (v != null) {
        outHeaders[k] = v;
      }
    }

    return Response(
      ioRes.statusCode,
      body: ioRes,
      headers: outHeaders,
    );
  }
}
