import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
  final http.Client _client = http.Client();

  /// 1-based virtual channel index → Xtream stream URL for the current lineup.
  Map<int, String> _virtToUrl = {};

  static final _autoPath = RegExp(r'^/auto/v(\d+)$');

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
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (e) {
        debugPrint('[PtTvHdhr] stop: $e');
      }
    }
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
      'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
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

  Future<Response> _dispatch(Request request) async {
    final path = request.requestedUri.path;
    if (path == '/discover.json' && request.method == 'GET') {
      return _handleDiscover(request);
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
    final m = _autoPath.firstMatch(path);
    if (m != null &&
        (request.method == 'GET' || request.method == 'HEAD')) {
      return _handleAutoTune(request, m.group(1)!);
    }
    return Response.notFound('Not found');
  }

  Future<Response> _handleAutoTune(Request request, String virtStr) async {
    final n = int.tryParse(virtStr);
    if (n == null || n < 1) {
      return Response.notFound('Bad channel');
    }
    final url = _virtToUrl[n];
    if (url == null || url.isEmpty) {
      return Response.notFound('Channel not in lineup (open PT TV Guide in app)');
    }
    return _proxyMedia(request, url, request.requestedUri.origin);
  }

  Future<Response> _handlePtClip(Request request) async {
    final raw = request.url.queryParameters['u'];
    if (raw == null || raw.isEmpty) {
      return Response(400, body: 'Missing u');
    }
    String target;
    try {
      target = Uri.decodeComponent(raw);
    } catch (_) {
      target = raw;
    }
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      return Response(400, body: 'Invalid URL');
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
      'TunerCount': 1,
    });
    return Response.ok(body, headers: {'Content-Type': 'application/json'});
  }

  Response _handleLineupStatus() {
    final body = json.encode({
      'ScanInProgress': 0,
      'ScanPossible': 1,
      'Source': 'Cable',
      'SourceList': ['Antenna', 'Cable'],
    });
    return Response.ok(body, headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _handleLineupPost(Request request) async {
    final scan = request.url.queryParameters['scan'];
    if (scan == 'start' || scan == 'abort') {
      await _rebuildLineupMap();
    }
    return Response.ok('OK', headers: {'Content-Type': 'text/plain'});
  }

  Future<List<Map<String, dynamic>>> _buildLineupList(Request request) async {
    await _rebuildLineupMap();
    final origin = request.requestedUri.origin;
    final list = <Map<String, dynamic>>[];
    final keys = _virtToUrl.keys.toList()..sort();
    for (final k in keys) {
      final u = _virtToUrl[k];
      if (u == null) continue;
      final slot = await _slotForVirt(k);
      list.add({
        'GuideNumber': '$k',
        'GuideName': slot?.$1 ?? 'Channel $k',
        'HD': 1,
        'URL': '$origin/auto/v$k',
        'LogoURL': slot?.$2 ?? '',
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

  Future<(String, String)?> _slotForVirt(int virt) async {
    final slots = await _loadTvGuideSlots();
    final i = virt - 1;
    if (i < 0 || i >= slots.length) return null;
    final s = slots[i];
    return (s.stream.name, s.stream.icon);
  }

  Future<void> _rebuildLineupMap() async {
    final slots = await _loadTvGuideSlots();
    final m = <int, String>{};
    for (var i = 0; i < slots.length; i++) {
      final u = IptvClient.streamUrl(slots[i].portal.portal, slots[i].stream);
      if (u.isNotEmpty) {
        m[i + 1] = u;
      }
    }
    _virtToUrl = m;
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

  Future<Response> _proxyMedia(
    Request request,
    String targetUrl,
    String selfOrigin,
  ) async {
    final targetUri = Uri.parse(targetUrl);
    final upstreamOrigin = '${targetUri.scheme}://${targetUri.host}'
        '${targetUri.hasPort ? ':${targetUri.port}' : ''}';

    final hdr = <String, String>{
      'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
      'Referer': '$upstreamOrigin/',
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
    };

    final rq = http.Request(request.method, targetUri);
    rq.headers.addAll(hdr);
    final range = request.headers['range'];
    if (range != null) rq.headers['Range'] = range;

    http.StreamedResponse upstream;
    try {
      upstream = await _client.send(rq);
    } catch (e) {
      return Response.internalServerError(body: 'Upstream: $e');
    }

    final ct = upstream.headers['content-type'] ?? '';
    final lowerUrl = targetUrl.toLowerCase();
    final looksLikeHls = ct.contains('mpegurl') ||
        ct.contains('x-mpegurl') ||
        lowerUrl.contains('.m3u8');

    if (looksLikeHls && request.method == 'GET') {
      final text = await upstream.stream.bytesToString();
      if (upstream.statusCode >= 400) {
        return Response(upstream.statusCode, body: text);
      }
      final basePath =
          targetUrl.substring(0, targetUrl.lastIndexOf('/') + 1);
      final out = text.split('\n').map((line) {
        final t = line.trimRight();
        if (t.isEmpty || t.startsWith('#')) {
          if (t.contains('URI="')) {
            return t.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) {
              final uri = m.group(1)!;
              final full = uri.startsWith('http')
                  ? uri
                  : uri.startsWith('/')
                      ? '$upstreamOrigin$uri'
                      : '$basePath$uri';
              return 'URI="${_clip(selfOrigin, full)}"';
            });
          }
          return line;
        }
        final full = t.startsWith('http')
            ? t
            : t.startsWith('/')
                ? '$upstreamOrigin$t'
                : '$basePath$t';
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
      'Content-Type': ct.isEmpty ? 'application/octet-stream' : ct,
    };
    for (final k in const [
      'content-length',
      'content-range',
      'accept-ranges',
    ]) {
      final v = upstream.headers[k];
      if (v != null) outHeaders[k] = v;
    }

    return Response(
      upstream.statusCode,
      body: upstream.stream,
      headers: outHeaders,
    );
  }

  String _clip(String origin, String u) =>
      '$origin/ptclip?u=${Uri.encodeComponent(u)}';
}
