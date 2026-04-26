import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'pastesh_decryptor.dart';

/// Xtream-Codes player_api client. Login + categories + streams + episodes.
class IptvClient {
  static const _ua = 'VLC/3.0.20 LibVLC/3.0.20';

  static String _enc(String s) => Uri.encodeComponent(s);

  static Future<String?> _httpGet(String url, {Duration? timeout}) async {
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = _ua
        ..headers['Accept'] = 'application/json,*/*';
      final stream =
          await req.send().timeout(timeout ?? const Duration(seconds: 10));
      if (stream.statusCode < 200 || stream.statusCode >= 300) return null;
      return await stream.stream.bytesToString();
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> login(IptvPortal p,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final url =
        '${p.url}/player_api.php?username=${_enc(p.username)}&password=${_enc(p.password)}';
    final text = await _httpGet(url, timeout: timeout);
    if (text == null) return null;
    try {
      final root = json.decode(text) as Map<String, dynamic>;
      final info = (root['user_info'] as Map<String, dynamic>?) ?? root;
      final auth = info['auth']?.toString();
      final status = (info['status']?.toString() ?? '').toLowerCase();
      final ok = auth == '1' || status == 'active' || root.containsKey('user_info');
      if (!ok) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  static Future<VerifiedPortal?> verifyOrNull(IptvPortal p,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final info = await login(p, timeout: timeout);
    if (info == null) return null;
    return VerifiedPortal(
      portal: p,
      name: (info['username']?.toString() ?? '').isNotEmpty
          ? info['username'].toString()
          : p.username,
      expiry: _formatExpiry(info['exp_date']?.toString()),
      maxConnections: info['max_connections']?.toString() ?? '1',
      activeConnections: info['active_cons']?.toString() ?? '0',
    );
  }

  static String _formatExpiry(String? raw) {
    if (raw == null) return 'Unknown';
    final ts = int.tryParse(raw);
    if (ts == null) return 'Unknown';
    try {
      final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  static Future<List<IptvCategory>> categories(
      IptvPortal p, IptvSection kind) async {
    final action = switch (kind) {
      IptvSection.live => 'get_live_categories',
      IptvSection.vod => 'get_vod_categories',
      IptvSection.series => 'get_series_categories',
    };
    final url = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}&action=$action';
    final text = await _httpGet(url, timeout: const Duration(seconds: 8));
    if (text == null) return [];
    try {
      final arr = json.decode(text) as List;
      return arr
          .map((e) {
            final o = e as Map<String, dynamic>;
            return IptvCategory(
              id: o['category_id']?.toString() ?? '',
              name: o['category_name']?.toString() ?? '',
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<IptvStream>> streams(
      IptvPortal p, IptvSection kind, String categoryId) async {
    final action = switch (kind) {
      IptvSection.live => 'get_live_streams',
      IptvSection.vod => 'get_vod_streams',
      IptvSection.series => 'get_series',
    };
    final base = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}&action=$action';
    final url = categoryId.isEmpty ? base : '$base&category_id=${_enc(categoryId)}';
    final text = await _httpGet(url, timeout: const Duration(seconds: 15));
    if (text == null) return [];
    try {
      final arr = json.decode(text) as List;
      return arr.map((e) {
        final o = e as Map<String, dynamic>;
        final ext = switch (kind) {
          IptvSection.live => 'ts',
          IptvSection.vod => () {
              final v = o['container_extension']?.toString() ?? '';
              return v.isEmpty ? 'mp4' : v;
            }(),
          IptvSection.series => '',
        };
        final id = switch (kind) {
          IptvSection.series => () {
              final v = o['series_id']?.toString() ?? '';
              return v.isEmpty ? (o['id']?.toString() ?? '') : v;
            }(),
          _ => () {
              final v = o['stream_id']?.toString() ?? '';
              return v.isEmpty ? (o['id']?.toString() ?? '') : v;
            }(),
        };
        return IptvStream(
          streamId: id,
          name: () {
            final n = o['name']?.toString() ?? '';
            return n.isEmpty ? (o['title']?.toString() ?? '') : n;
          }(),
          icon: () {
            final i = o['stream_icon']?.toString() ?? '';
            return i.isEmpty ? (o['cover']?.toString() ?? '') : i;
          }(),
          categoryId: o['category_id']?.toString() ?? '',
          containerExt: ext,
          epgChannelId: o['epg_channel_id']?.toString() ?? '',
          kind: switch (kind) {
            IptvSection.live => 'live',
            IptvSection.vod => 'vod',
            IptvSection.series => 'series',
          },
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<IptvEpisode>> seriesEpisodes(
      IptvPortal p, String seriesId) async {
    final url = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}&action=get_series_info&series_id=${_enc(seriesId)}';
    final text = await _httpGet(url, timeout: const Duration(seconds: 15));
    if (text == null) return [];
    try {
      final root = json.decode(text) as Map<String, dynamic>;
      final episodesObj = root['episodes'] as Map<String, dynamic>?;
      if (episodesObj == null) return [];
      final out = <IptvEpisode>[];
      episodesObj.forEach((seasonKey, value) {
        final arr = value as List?;
        if (arr == null) return;
        final seasonNum = int.tryParse(seasonKey) ?? 0;
        for (final e in arr) {
          final o = e as Map<String, dynamic>?;
          if (o == null) continue;
          final info = o['info'] as Map<String, dynamic>?;
          out.add(IptvEpisode(
            id: o['id']?.toString() ?? '',
            title: o['title']?.toString() ?? '',
            containerExt: () {
              final c = o['container_extension']?.toString() ?? '';
              return c.isEmpty ? 'mp4' : c;
            }(),
            season: seasonNum,
            episode: (o['episode_num'] is num)
                ? (o['episode_num'] as num).toInt()
                : (int.tryParse(o['episode_num']?.toString() ?? '') ?? 0),
            plot: info?['plot']?.toString() ?? '',
            image: info?['movie_image']?.toString() ?? '',
          ));
        }
      });
      out.sort((a, b) {
        final s = a.season.compareTo(b.season);
        return s != 0 ? s : a.episode.compareTo(b.episode);
      });
      return out;
    } catch (_) {
      return [];
    }
  }

  static String streamUrl(IptvPortal p, IptvStream s) {
    final user = _enc(p.username);
    final pass = _enc(p.password);
    switch (s.kind) {
      case 'live':
        return '${p.url}/live/$user/$pass/${s.streamId}.${s.containerExt}';
      case 'vod':
        return '${p.url}/movie/$user/$pass/${s.streamId}.${s.containerExt}';
      default:
        return '';
    }
  }

  static String episodeUrl(IptvPortal p, IptvEpisode e) =>
      '${p.url}/series/${_enc(p.username)}/${_enc(p.password)}/${e.id}.${e.containerExt}';

  /// Fetches the next [limit] EPG programmes for [streamId] via Xtream's
  /// `get_short_epg`. Returns an empty list on any failure (no panel EPG,
  /// timeout, malformed JSON, etc.) so callers can simply hide the row.
  ///
  /// Xtream encodes `title` and `description` as base64 strings.
  static Future<List<EpgEntry>> shortEpg(
    IptvPortal p,
    String streamId, {
    int limit = 2,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (streamId.isEmpty) return const [];
    final url = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}'
        '&action=get_short_epg&stream_id=${_enc(streamId)}&limit=$limit';
    final text = await _httpGet(url, timeout: timeout);
    if (text == null) return const [];
    try {
      final root = json.decode(text);
      final List arr = root is Map<String, dynamic>
          ? (root['epg_listings'] as List? ?? const [])
          : (root is List ? root : const []);
      DateTime? parseTs(dynamic v) {
        if (v == null) return null;
        final s = v.toString();
        // Xtream sends both unix-seconds ("start_timestamp") and ISO-ish
        // strings ("start": "2026-04-25 19:00:00"). Try seconds first.
        final secs = int.tryParse(s);
        if (secs != null && secs > 1000000000) {
          return DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true)
              .toLocal();
        }
        try {
          return DateTime.parse(s.replaceFirst(' ', 'T')).toLocal();
        } catch (_) {
          return null;
        }
      }

      String decode64(dynamic v) {
        if (v == null) return '';
        final s = v.toString();
        if (s.isEmpty) return '';
        try {
          return utf8.decode(base64.decode(s), allowMalformed: true).trim();
        } catch (_) {
          return s;
        }
      }

      final out = <EpgEntry>[];
      for (final e in arr) {
        if (e is! Map<String, dynamic>) continue;
        final start = parseTs(e['start_timestamp']) ?? parseTs(e['start']);
        final stop = parseTs(e['stop_timestamp']) ?? parseTs(e['end']);
        if (start == null || stop == null) continue;
        out.add(EpgEntry(
          title: decode64(e['title']),
          description: decode64(e['description']),
          start: start,
          stop: stop,
        ));
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      return out;
    } catch (_) {
      return const [];
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Verifier — bounded concurrency, abort once `target` portals authenticated.
// ─────────────────────────────────────────────────────────────────────────────
class IptvVerifier {
  static const _parallel = 4;

  static Future<List<VerifiedPortal>> verifyUntil({
    required List<IptvPortal> portals,
    int target = 5,
    void Function(int checked, int total, int alive)? onProgress,
    void Function(VerifiedPortal v)? onAlive,
    void Function(IptvPortal p)? onAttempted,
    bool Function()? isCancelled,
  }) async {
    if (portals.isEmpty) return const [];

    var nextIdx = 0;
    var checked = 0;
    final alive = <VerifiedPortal>[];
    final completer = Completer<void>();
    var stopped = false;

    void stop() {
      if (!stopped) {
        stopped = true;
        if (!completer.isCompleted) completer.complete();
      }
    }

    Future<void> worker() async {
      while (!stopped) {
        if (isCancelled?.call() == true) {
          stop();
          break;
        }
        if (alive.length >= target) {
          stop();
          break;
        }
        final idx = nextIdx++;
        if (idx >= portals.length) break;
        onAttempted?.call(portals[idx]);
        VerifiedPortal? v;
        try {
          v = await IptvClient.verifyOrNull(portals[idx]);
        } catch (_) {
          v = null;
        }
        if (stopped) break;
        checked++;
        if (v != null && alive.length < target) {
          alive.add(v);
          onAlive?.call(v);
        }
        onProgress?.call(checked, portals.length, alive.length);
        if (alive.length >= target) {
          stop();
          break;
        }
      }
    }

    final workers = List.generate(
      _parallel.clamp(1, portals.length),
      (_) => worker(),
    );
    // Wait either all workers done or `stop()` triggered.
    await Future.any([
      Future.wait(workers),
      completer.future,
    ]);
    return List.unmodifiable(alive);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Alive checker — partial-content stream-content sniffing.
// ─────────────────────────────────────────────────────────────────────────────
class AliveProgress {
  final int checked;
  final int total;
  final int alive;
  const AliveProgress(this.checked, this.total, this.alive);
}

class IptvAliveChecker {
  static const int _minBytes = 16 * 1024;
  static const int _maxBytes = 64 * 1024;
  static const Duration _timeout = Duration(seconds: 8);
  static const int _concurrency = 24;

  /// Run alive checks. Caller controls cancellation via [isCancelled].
  /// Returns when all complete or cancelled.
  static Future<void> launchCheck({
    required List<MapEntry<String, String>> streams, // (id, url)
    required Future<void> Function(String id, bool alive) onResult,
    required Future<void> Function(AliveProgress p) onProgress,
    required Future<void> Function() onDone,
    bool Function()? isCancelled,
  }) async {
    var checked = 0;
    var alive = 0;
    final total = streams.length;
    final pending = List<MapEntry<String, String>>.from(streams);

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) return;
        if (pending.isEmpty) return;
        final job = pending.removeAt(0);
        final ok = await _isAlive(job.value);
        if (isCancelled?.call() == true) return;
        checked++;
        if (ok) alive++;
        await onResult(job.key, ok);
        await onProgress(AliveProgress(checked, total, alive));
      }
    }

    final workers = List.generate(_concurrency, (_) => worker());
    await Future.wait(workers);
    if (isCancelled?.call() != true) await onDone();
  }

  static Future<bool> _isAlive(String url) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = true
        ..headers['User-Agent'] = 'VLC/3.0.20 LibVLC/3.0.20'
        ..headers['Accept'] = '*/*'
        ..headers['Connection'] = 'keep-alive'
        ..headers['Range'] = 'bytes=0-${_maxBytes - 1}';
      final resp = await client.send(req).timeout(_timeout);
      final code = resp.statusCode;
      if (code != 206 && (code < 200 || code >= 300)) return false;
      final ct = (resp.headers['content-type'] ?? '').toLowerCase();
      final cl = int.tryParse(resp.headers['content-length'] ?? '') ?? -1;
      if (_isDeadContentType(ct)) return false;

      // Read up to MAX_BYTES (or until end)
      final buf = <int>[];
      var ended = true;
      try {
        await for (final chunk in resp.stream.timeout(_timeout)) {
          buf.addAll(chunk);
          if (buf.length >= _maxBytes) {
            ended = false;
            break;
          }
          if (buf.length >= _minBytes) {
            // got enough
            ended = false;
            break;
          }
        }
      } catch (_) {
        // partial read is fine
      }

      final isM3U8 = ct.contains('mpegurl') || url.toLowerCase().contains('.m3u8');
      if (isM3U8) {
        final headStr = utf8.decode(
            buf.sublist(0, buf.length < 1024 ? buf.length : 1024),
            allowMalformed: true);
        return headStr.contains('#EXTM3U');
      }
      if (ended && buf.length < _minBytes) return false;
      // canned offline videos typically 0..5MB
      if (cl >= 1 && cl <= 5_000_000) return false;

      // MPEG-TS sync byte (0x47), check ≥3 consecutive 188-byte packets
      if (buf.isNotEmpty && buf[0] == 0x47) {
        var validTs = true;
        var checkedPackets = 0;
        var i = 0;
        while (i < buf.length - 188 && checkedPackets < 10) {
          if (buf[i] != 0x47) {
            validTs = false;
            break;
          }
          checkedPackets++;
          i += 188;
        }
        if (validTs && checkedPackets >= 3) return true;
      }
      // MP4 ftyp
      if (buf.length >= 8) {
        final s = String.fromCharCodes(buf.sublist(4, 8));
        if (s == 'ftyp') return true;
      }
      if (_hasVideoSignature(buf)) return true;
      if (buf.length >= 32 * 1024) return true;
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  static bool _isDeadContentType(String ct) =>
      ct.contains('text/html') ||
      ct.contains('application/json') ||
      ct.contains('text/xml') ||
      ct.contains('text/plain');

  static bool _hasVideoSignature(List<int> buf) {
    if (buf.length < 4) return false;
    if (buf[0] == 0x47) return true;
    if (buf.length >= 7) {
      final s = String.fromCharCodes(buf.sublist(0, 7));
      if (s == '#EXTM3U') return true;
    }
    if (buf.length >= 4) {
      final s = String.fromCharCodes(buf.sublist(0, 4));
      if (s == '#EXT') return true;
    }
    // AAC/MPEG sync (1111 1111 111x xxxx)
    if (buf[0] == 0xFF && (buf[1] & 0xE0) == 0xE0) return true;
    // Matroska / WebM
    if (buf[0] == 0x1A && buf[1] == 0x45 && buf[2] == 0xDF && buf[3] == 0xA3) {
      return true;
    }
    // Ogg
    if (buf[0] == 0x4F && buf[1] == 0x67 && buf[2] == 0x67 && buf[3] == 0x53) {
      return true;
    }
    // H.264 NAL start code
    if (buf[0] == 0x00 && buf[1] == 0x00 && buf[2] == 0x00 && buf[3] == 0x01) {
      return true;
    }
    if (buf[0] == 0x00 && buf[1] == 0x00 && buf[2] == 0x01 && (buf[3] & 0xFF) >= 0xB0) {
      return true;
    }
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Catalog Xtream-Codes scraper
// ─────────────────────────────────────────────────────────────────────────────
class IptvScraper {
  // Reddit's `.json` endpoint returns an HTML interstitial for browser-like
  // User-Agents (anti-scraping). We therefore query the old.reddit.com host
  // with a non-browser UA, and transparently fall back to other hosts.
  // Reddit now 403s almost every unauthenticated UA. Strategy (in order):
  //   1. Try hitting reddit hosts directly with a Googlebot UA — many Reddit
  //      anti-bot rules still whitelist search-engine crawlers.
  //   2. Fall back to public fetch/CORS proxies that perform the request
  //      server-side (allorigins, corsproxy.io, r.jina.ai reader).
  //   3. Last resort: scrape the .rss feed and extract links from <description>
  //      CDATA sections (HTML, not JSON).
  static const _catalogSub = 'IPTV_ZONENEW';
  // One quick direct attempt — Reddit currently 403s almost everything, but
  // this is cheap so we try once before going through a proxy.
  static const _catalogDirectHost = 'https://www.reddit.com';
  static const _catalogDirectUa =
      'Googlebot/2.1 (+http://www.google.com/bot.html)';
  // Public fetch proxies ordered by observed reliability (corsproxy.io has
  // worked in practice; others are fallbacks). `{URL}` = URL-encoded target.
  static const _fetchProxies = <String>[
    'https://corsproxy.io/?{URL}',
    'https://api.codetabs.com/v1/proxy?quest={URL}',
    'https://api.allorigins.win/raw?url={URL}',
  ];
  static const _ua = 'Mozilla/5.0 (Linux; Android 11; PlayTorrio) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36';

  static const _pasteDomains = [
    'paste.sh', 'pastebin.com', 'justpaste.it', 'controlc.com',
    'pastes.dev', 'text.is', 'rentry.co',
  ];

  static final _b64 = RegExp(r'aHR0c[a-zA-Z0-9+/=]{10,}');
  static final _rawPaste = RegExp(
    r'https?://(?:paste\.sh|pastebin\.com|justpaste\.it|controlc\.com|pastes\.dev|text\.is|rentry\.co)/[a-zA-Z0-9#_=-]+',
    caseSensitive: false,
  );
  static final _urlParam = RegExp(
    r'''(https?://[^?\s"'<]+)\?(?:[^\s"'<]*?&)?(?:username|user)=([^&\s"'<]+)\s*&(?:password|pass)=([^&\s"'<]+)''',
    caseSensitive: false,
  );
  // Label fallback for posts that don't expose a full /get.php?username=…&password=… URL.
  // Accepts English ("Host/User/Pass"), Portuguese ("Usuário/Senha"), Spanish ("Usuario/Contraseña"),
  // unicode smallcaps variants used by WTF-M3U scanners (Hᴏsᴛ / Usᴇʀ / Pᴀss / Usᴜᴀʀɪᴏ / Sᴇɴʜᴀ),
  // and any combination of decorative separators (➢, ►, :, ., …, whitespace) between the label
  // and the value. Trailing dots after the label (Raptor's "Host......:") are absorbed by `\W*`.
  static final _label = RegExp(
    r'''(?:Portal|Host(?:\s*URL)?|H[ᴏo]s[ᴛt]|Panel|Real|URL|🔗|🌍|🌐)\W*?(https?://[^<\s"']+)[\s\S]{1,500}?(?:Username|Usu[áa]rio|Usuario|User|Us[ᴇe]r|Us[ᴜu][ᴀa]r[ɪi][ᴏo]|👤)\W*?([^\s|<"'\n]+)[\s\S]{1,200}?(?:Password|Senha|Contrase[ñn]a|Pass|P[ᴀa]ss|S[ᴇe]nh[ᴀa]|🔑)\W*?([^\s|<"'\n]+)''',
    caseSensitive: false,
  );

  static const _junkTokens = [
    'type=m3u', 'output=ts', 'password=', 'username=', 'password', 'username',
  ];

  static Future<ScrapePage> scrapeCatalogPage(
      {int maxResults = 50, String? after}) async {
    final out = <String, IptvPortal>{};
    final catalogJson = await _fetchCatalogJson(after: after);
    if (catalogJson == null) {
      debugPrint('[Catalog] fetch failed');
      return const ScrapePage(portals: [], nextAfter: null);
    }

    Map<String, dynamic>? data;
    try {
      data = (json.decode(catalogJson) as Map<String, dynamic>)['data']
          as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[Catalog] JSON parse failed: $e');
    }
    if (data == null) return const ScrapePage(portals: [], nextAfter: null);

    final posts = data['children'] as List?;
    if (posts == null) return const ScrapePage(portals: [], nextAfter: null);
    final nextAfterRaw = data['after']?.toString();
    final nextAfter =
        (nextAfterRaw == null || nextAfterRaw.isEmpty || nextAfterRaw == 'null')
            ? null
            : nextAfterRaw;
    debugPrint('[Catalog] ${posts.length} posts (after=$after, next=$nextAfter)');

    var postIdx = 0;
    for (final post in posts) {
      postIdx++;
      if (out.length >= maxResults) break;
      final pdata = ((post as Map<String, dynamic>)['data']) as Map<String, dynamic>?;
      if (pdata == null) continue;
      final title = pdata['title']?.toString() ?? '';
      final body = '$title ${pdata['selftext']?.toString() ?? ''}'.trim();
      debugPrint('[Catalog] post[$postIdx] '
          "'${title.length > 60 ? '${title.substring(0, 60)}…' : title}'"
          ' bodyLen=${body.length}');

      // 1. Direct extraction from post body
      final direct = _extractPortals(body, 'Catalog');
      if (direct.isNotEmpty) {
        debugPrint('[Catalog]   direct: ${direct.length}');
      }
      for (final p in direct) {
        _addPortal(out, p, maxResults);
      }
      if (out.length >= maxResults) break;

      // 2. Decode base64 deep links
      final deepLinks = <String>[];
      for (final m in _b64.allMatches(body)) {
        try {
          final decoded = utf8.decode(base64.decode(m.group(0)!),
              allowMalformed: true);
          if (decoded.startsWith('http') && _isPasteSite(decoded)) {
            deepLinks.add(decoded);
          } else if (!decoded.startsWith('http') && decoded.contains(':')) {
            _extractPortals(decoded, 'Catalog (decoded)')
                .forEach((p) => _addPortal(out, p, maxResults));
          }
        } catch (_) {}
      }

      // 3. Raw paste links in body
      for (final m in _rawPaste.allMatches(body)) {
        deepLinks.add(m.group(0)!);
      }

      // 4. Fetch up to 4 deep links per post
      final unique = deepLinks.toSet().take(4);
      for (final dl in unique) {
        if (out.length >= maxResults) break;
        debugPrint('[Catalog]   deep: ${_redact(dl)}');
        final text = await _fetchPaste(dl);
        if (text == null || text.isEmpty) {
          debugPrint('[Catalog]     → empty');
          continue;
        }
        final found = _extractPortals(text, 'Catalog (deep)');
        debugPrint('[Catalog]     → ${text.length} chars, ${found.length} portals');
        for (final p in found) {
          _addPortal(out, p, maxResults);
        }
      }
    }

    debugPrint('[Catalog] DONE — ${out.length} unique portals');
    return ScrapePage(portals: out.values.toList(), nextAfter: nextAfter);
  }

  static void _addPortal(
      Map<String, IptvPortal> sink, IptvPortal p, int max) {
    if (sink.length >= max) return;
    sink.putIfAbsent(p.key, () => p);
  }

  static List<IptvPortal> _extractPortals(String rawText, String source) {
    if (rawText.length < 15 || _isJunkCode(rawText)) return const [];
    final cleaned = rawText
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll(
          RegExp(r'<(?:p|br|div|li|h\d)[^>]*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '');

    final acc = <String, IptvPortal>{};
    for (final m in _urlParam.allMatches(cleaned)) {
      _finalize(acc, m.group(1)!, m.group(2)!, m.group(3)!, source);
    }
    for (final m in _label.allMatches(cleaned)) {
      _finalize(acc, m.group(1)!, m.group(2)!, m.group(3)!, source);
    }
    return acc.values.toList();
  }

  static bool _isJunkCode(String text) {
    const markers = [
      'Array.isArray', 'prototype.', 'function(', 'var ', 'const ',
      'let ', 'return!', 'void ', '.message}', 'window.', 'document.',
    ];
    var hits = 0;
    for (final m in markers) {
      if (text.contains(m)) hits++;
      if (hits >= 2) return true;
    }
    return false;
  }

  static void _finalize(Map<String, IptvPortal> acc, String rawUrl,
      String rawUser, String rawPass, String source) {
    final url = _cleanPortalUrl(rawUrl);
    final user = _cleanCred(rawUser);
    final pass = _cleanCred(rawPass);
    if (url.isEmpty || user.length < 3 || pass.length < 3) return;
    if (user.contains('http') || pass.contains('http')) return;
    final lu = user.toLowerCase();
    final lp = pass.toLowerCase();
    for (final j in _junkTokens) {
      if (lu.contains(j) || lp.contains(j)) return;
    }
    final p = IptvPortal(url: url, username: user, password: pass, source: source);
    acc.putIfAbsent(p.key, () => p);
  }

  static String _cleanPortalUrl(String raw) {
    var clean = raw.replaceAll(RegExp(r'\s+'), '');
    final qIdx = clean.indexOf('?');
    if (qIdx >= 0) clean = clean.substring(0, qIdx);
    clean = clean.trim();
    if (clean.contains('@')) {
      clean = 'http://${clean.substring(clean.lastIndexOf('@') + 1)}';
    }
    clean = clean.replaceAll(
      RegExp(
        r'/(?:get|live|portal|c|index|playlist|player_api|xmltv|index\.php|portal\.php)\.php$',
        caseSensitive: false,
      ),
      '',
    );
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (!clean.startsWith('http')) clean = 'http://$clean';
    return clean;
  }

  static String _cleanCred(String raw) {
    var s = raw;
    while (s.startsWith('=')) {
      s = s.substring(1);
    }
    final parts = s.split(RegExp(r'[ \n&?]'));
    return parts.isEmpty ? '' : parts.first.trim();
  }

  static bool _isPasteSite(String url) =>
      _pasteDomains.any((d) => url.contains(d));

  static Future<String?> _fetchPaste(String url) async {
    // paste.sh → AES-256-CBC encrypted, fragment is the client key
    if (url.contains('paste.sh/') && url.contains('#')) {
      final out = await PasteShDecryptor.decrypt(url);
      return out.isEmpty ? null : out;
    }
    if (url.contains('pastebin.com/') && !url.contains('/raw/')) {
      final id = _lastPathSegment(url);
      return _httpGetText('https://pastebin.com/raw/$id');
    }
    if (url.contains('pastes.dev/')) {
      final id = _lastPathSegment(url);
      return _httpGetText('https://api.pastes.dev/$id');
    }
    if (url.contains('rentry.co/') && !url.contains('/raw')) {
      final id = _lastPathSegment(url);
      return _httpGetText('https://rentry.co/$id/raw');
    }
    return _httpGetText(url);
  }

  static String _lastPathSegment(String url) {
    var s = url;
    final h = s.indexOf('#');
    if (h >= 0) s = s.substring(0, h);
    final q = s.indexOf('?');
    if (q >= 0) s = s.substring(0, q);
    final slash = s.lastIndexOf('/');
    return slash >= 0 ? s.substring(slash + 1) : s;
  }

  /// Strip a URL down to host + masked path so it doesn't appear in user logs.
  static String _redact(String url) {
    try {
      final u = Uri.parse(url);
      final host = u.host.isEmpty ? '?' : u.host;
      final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
      final path = segs.isEmpty
          ? ''
          : '/${segs.map((s) => s.length <= 2 ? s : '${s.substring(0, 2)}***').join('/')}';
      return '$host$path';
    } catch (_) {
      return '<url>';
    }
  }

  static Future<String?> _httpGetText(String url) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': _ua,
        'Accept': 'text/html,application/json,*/*',
      }).timeout(const Duration(seconds: 15));
      return resp.body;
    } catch (e) {
      debugPrint('[Catalog] httpGet failed: $e');
      return null;
    }
  }

  /// Fetches the subreddit listing as JSON. Reddit 403s most unauthenticated
  /// clients, so we do one quick direct attempt and then go through public
  /// fetch proxies (server-side fetch, bypasses Reddit's client-IP blocks).
  /// Accepts only responses whose first non-whitespace byte is `{` or `[`.
  static Future<String?> _fetchCatalogJson({String? after}) async {
    String buildTarget(String host) {
      final base = '$host/r/$_catalogSub/new/.json?limit=100&sort=new';
      return (after == null || after.isEmpty) ? base : '$base&after=$after';
    }

    bool looksJson(String body) {
      final t = body.trimLeft();
      return t.startsWith('{') || t.startsWith('[');
    }

    final target = buildTarget(_catalogDirectHost);

    // 1. One direct attempt with Googlebot UA.
    debugPrint('[Catalog] GET ${_redact(target)} (direct)');
    try {
      final resp = await http.get(Uri.parse(target), headers: {
        'User-Agent': _catalogDirectUa,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && looksJson(resp.body)) return resp.body;
      debugPrint('[Catalog]   direct ${resp.statusCode} len=${resp.body.length}');
    } catch (e) {
      debugPrint('[Catalog]   direct failed: $e');
    }

    // 2. Proxy attempts.
    final encoded = Uri.encodeComponent(target);
    for (final tmpl in _fetchProxies) {
      final proxyUrl = tmpl.replaceFirst('{URL}', encoded);
      debugPrint('[Catalog] proxy ${_redact(proxyUrl)}');
      try {
        final resp = await http.get(Uri.parse(proxyUrl), headers: {
          'User-Agent': _ua,
          'Accept': 'application/json, text/plain, */*',
        }).timeout(const Duration(seconds: 20));
        if (resp.statusCode != 200) {
          debugPrint('[Catalog]   proxy ${resp.statusCode}');
          continue;
        }
        if (looksJson(resp.body)) return resp.body;
        debugPrint('[Catalog]   proxy non-JSON (len=${resp.body.length})');
      } catch (e) {
        debugPrint('[Catalog]   proxy failed: $e');
      }
    }
    return null;
  }
}
