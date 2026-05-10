// kisskh.co stream extractor — headless WebView based.
//
// The site signs every Episode/{epId}.png and Sub/{epId} request with a
// `kkey` parameter generated client-side by heavily obfuscated JS. Rather
// than reverse the cipher in Dart, we let the page's own JS sign it for us
// by hooking `fetch` and capturing the parsed JSON response bodies.
//
// Flow:
//   1. Open https://kisskh.co/Drama/{slug}/Episode-{n}?id={dramaId}&ep={epId}
//      in a hidden HeadlessInAppWebView.
//   2. Inject a fetch hook at AT_DOCUMENT_START that:
//      - Detects calls to `/api/DramaList/Episode/{epId}.png`.
//      - Detects calls to `/api/Sub/{epId}`.
//      - Reads the response body and forwards both URL + JSON via
//        `console.log('KKH_VIDEO:...')` / `KKH_SUBS:...`.
//   3. Wait until either both arrive or a soft timeout (then ship video
//      alone — subs are optional).

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/stream_source.dart';
import 'kisskh_service.dart';
import 'kisskh_subtitle_decryptor.dart';

class KissKhStream {
  final String url;
  final String type; // hls / mp4
  final List<Map<String, dynamic>> subtitles;
  final Map<String, String> headers;

  const KissKhStream({
    required this.url,
    required this.type,
    required this.headers,
    this.subtitles = const [],
  });
}

class KissKhExtractor {
  HeadlessInAppWebView? _web;
  Completer<_RawHit>? _videoCompleter;
  final List<Map<String, dynamic>> _subsBuffer = [];

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  Future<KissKhStream?> resolve({
    required int dramaId,
    required String dramaTitle,
    required int episodeId,
    required double episodeNumber,
    void Function(String phase, String detail)? onProgress,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    onProgress?.call('init', 'Opening kisskh page…');

    final pageUrl = KissKhService.episodePageUrl(
      dramaId: dramaId,
      title: dramaTitle,
      episodeId: episodeId,
      episodeNumber: episodeNumber,
    );

    _videoCompleter = Completer<_RawHit>();
    _subsBuffer.clear();

    try {
      _web = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(pageUrl)),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: _interceptScript(episodeId),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          userAgent: _userAgent,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
        ),
        onLoadStop: (_, _) {
          onProgress?.call('loaded', 'Waiting for stream key…');
        },
        onConsoleMessage: (_, msg) {
          var s = msg.message.trim();
          if (s.startsWith('"') && s.endsWith('"')) {
            s = s.substring(1, s.length - 1).replaceAll(r'\"', '"');
          }
          if (s.startsWith('KKH_VIDEO:')) {
            try {
              final data = jsonDecode(s.substring('KKH_VIDEO:'.length));
              final url = (data['Video'] ?? data['video'] ?? '').toString();
              if (url.isEmpty) return;
              final type = url.contains('.m3u8') ? 'hls' : 'mp4';
              if (_videoCompleter != null &&
                  !_videoCompleter!.isCompleted) {
                _videoCompleter!.complete(_RawHit(url: url, type: type));
              }
            } catch (e) {
              debugPrint('[KissKhExtractor] video parse failed: $e');
            }
            return;
          }
          if (s.startsWith('KKH_SUBS:')) {
            try {
              final data = jsonDecode(s.substring('KKH_SUBS:'.length));
              if (data is! List) return;
              for (final t in data) {
                if (t is! Map) continue;
                final src = (t['src'] ?? t['url'] ?? '').toString();
                if (src.isEmpty) continue;
                final label = (t['label'] ?? t['language'] ?? 'Unknown')
                    .toString();
                _subsBuffer.add({
                  'id': src,
                  'url': src,
                  'language': label,
                  'display': '$label - kisskh',
                  'sourceName': 'kisskh',
                });
              }
            } catch (e) {
              debugPrint('[KissKhExtractor] subs parse failed: $e');
            }
            return;
          }
          if (s.startsWith('KKH_LOG:')) {
            debugPrint('[KissKhExtractor JS] ${s.substring(8)}');
          }
        },
      );

      await _web!.run();

      final hit = await _videoCompleter!.future.timeout(
        timeout,
        onTimeout: () =>
            throw TimeoutException('No video URL in ${timeout.inSeconds}s'),
      );

      // Brief grace window so subtitles (which often arrive slightly after
      // the video URL) can land in the same payload.
      await Future.any<void>([
        Future<void>.delayed(const Duration(milliseconds: 1200)),
        // Bail early if subs are already there.
        Future<void>.delayed(const Duration(milliseconds: 0))
            .then((_) => _subsBuffer.isEmpty
                ? Future<void>.delayed(const Duration(milliseconds: 1200))
                : Future<void>.value()),
      ]);

      onProgress?.call('done', 'Stream ready');

      // ─── Decrypt subtitles ────────────────────────────────────────────
      // kisskh ships AES-128-CBC encrypted SRTs. Download + decrypt + write
      // to a temp file so the player can consume them as plain local files.
      if (_subsBuffer.isNotEmpty) {
        onProgress?.call('subs',
            'Decrypting ${_subsBuffer.length} subtitle track(s)…');
        await Future.wait(_subsBuffer.map((s) async {
          final url = (s['url'] ?? '').toString();
          if (url.isEmpty) return;
          final localUri = await KissKhSubtitleDecryptor.fetchAndDecrypt(
            url: url,
            episodeId: episodeId,
            language: (s['language'] ?? 'sub').toString(),
            userAgent: _userAgent,
            referer: '${KissKhService.baseUrl}/',
          );
          if (localUri != null) {
            s['url'] = localUri;
            s['id'] = localUri;
          }
        }));
      }

      return KissKhStream(
        url: hit.url,
        type: hit.type,
        subtitles: List<Map<String, dynamic>>.from(_subsBuffer),
        headers: const {
          'User-Agent': _userAgent,
          'Referer': '${KissKhService.baseUrl}/',
          'Origin': KissKhService.baseUrl,
        },
      );
    } catch (e) {
      onProgress?.call('error', '$e');
      return null;
    } finally {
      await _cleanup();
      _videoCompleter = null;
    }
  }

  Future<void> dispose() async {
    await _cleanup();
  }

  Future<void> _cleanup() async {
    final w = _web;
    _web = null;
    if (w != null) {
      try {
        await w.dispose();
      } catch (e) {
        debugPrint('[KissKhExtractor] dispose error: $e');
      }
    }
  }

  // ─── Build the in-page hook ─────────────────────────────────────
  String _interceptScript(int epId) {
    return '''
(function () {
  function log(msg) { console.log('KKH_LOG:' + msg); }
  function sendVideo(data) { console.log('KKH_VIDEO:' + JSON.stringify(data)); }
  function sendSubs(data)  { console.log('KKH_SUBS:'  + JSON.stringify(data)); }

  log('intercept ready for ep $epId');

  function tryHandle(url, json) {
    try {
      if (!url) return;
      if (url.indexOf('/api/DramaList/Episode/') !== -1 &&
          url.indexOf('.png') !== -1) {
        sendVideo(json || {});
      } else if (url.indexOf('/api/Sub/') !== -1) {
        if (Array.isArray(json)) sendSubs(json);
      }
    } catch (e) { log('handle err: ' + e); }
  }

  // Hook fetch
  const origFetch = window.fetch;
  window.fetch = function () {
    const req = arguments[0];
    const url = (typeof req === 'string') ? req : (req && req.url) || '';
    return origFetch.apply(this, arguments).then(function (res) {
      try {
        if (url.indexOf('/api/DramaList/Episode/') !== -1 ||
            url.indexOf('/api/Sub/') !== -1) {
          res.clone().json().then(function (j) { tryHandle(url, j); })
            .catch(function () {});
        }
      } catch (e) {}
      return res;
    });
  };

  // Hook XMLHttpRequest as well — Angular's HttpClient uses it.
  const OrigXhr = window.XMLHttpRequest;
  function HookedXhr() {
    const x = new OrigXhr();
    let _url = '';
    const _open = x.open;
    x.open = function (m, u) {
      _url = u || '';
      return _open.apply(x, arguments);
    };
    x.addEventListener('load', function () {
      try {
        if (_url.indexOf('/api/DramaList/Episode/') !== -1 ||
            _url.indexOf('/api/Sub/') !== -1) {
          let j = null;
          try { j = JSON.parse(x.responseText); } catch (e) {}
          tryHandle(_url, j);
        }
      } catch (e) {}
    });
    return x;
  }
  HookedXhr.prototype = OrigXhr.prototype;
  window.XMLHttpRequest = HookedXhr;
})();
''';
  }
}

class _RawHit {
  final String url;
  final String type;
  _RawHit({required this.url, required this.type});
}

extension KissKhStreamSources on KissKhStream {
  List<StreamSource> toSources({String label = 'kisskh'}) => [
        StreamSource(
          url: url,
          title: label,
          type: type,
          headers: Map<String, String>.from(headers),
        ),
      ];
}
