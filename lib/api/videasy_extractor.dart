// Pure-Dart Videasy extractor (no page scraping).
//
// Pipeline:
//   1. HTTP GET https://api.videasy.net/{provider}/sources-with-title?tmdbId=...
//      -> hex-encoded blob (~9000 chars).
//   2. Run that blob through the (locally bundled, patched) AssemblyScript
//      WASM `decrypt(blob, tmdbId)` -> base64 OpenSSL "Salted__..." string.
//      The patched module bypasses the verify() gate so we never need
//      `serve()` / window.hash / eval'd JS. WASM runs in a sandboxed
//      HeadlessInAppWebView pointed at about:blank — no DOM, no network,
//      no scraping, no waiting for the player UI.
//   3. base64 decode -> strip "Salted__" magic + 8-byte salt.
//   4. EVP_BytesToKey(passphrase="", salt, MD5) -> 32-byte key + 16-byte IV.
//      (CryptoJS.AES.decrypt(intermediate, "") on the JS side is identical.
//      The b35ebba4 passphrase is empty because cineby's
//      `Hashids.encode(hexString)` returns "".)
//   5. AES-256-CBC decrypt + PKCS#7 unpad -> UTF-8 -> JSON.
//
// Asset: assets/videasy/module.wasm (patched, 262931 bytes).
// See /memories/repo/videasy_player_protocol.md for full RE notes.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as cryptolib;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' as pc;

import '../models/stream_source.dart';
import 'stream_extractor.dart' show ExtractedMedia;

class VideasyExtractor {
  final void Function(String) onLog;
  VideasyExtractor({required this.onLog});

  // Providers known to respond to /{name}/sources-with-title with tmdbId only.
  // Order matters: first hits first. Limited to a few reliable English ones to
  // keep extract() snappy. Add more from the registry if needed.
  static const _providers = <String>[
    'myflixerzupcloud',
    'mb-flix',
    '1movies',
    'moviebox',
    'cdn',
    'primesrcme',
  ];

  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  static const _baseHeaders = <String, String>{
    'User-Agent': userAgent,
    'Referer': 'https://player.videasy.net/',
    'Origin': 'https://player.videasy.net',
    'Accept': '*/*',
  };

  // Headers required to actually *play* the resolved m3u8/mp4. Many of
  // videasy's CDN edges (e.g. fast3.vidplus.dev/frostcomet*.pro) hard-gate
  // on Referer + Chrome UA — missing them yields a generic 403/connection
  // close that media_kit surfaces as "Failed to open".
  static const _playbackHeaders = <String, String>{
    'User-Agent': userAgent,
    'Referer': 'https://player.videasy.net/',
    'Origin': 'https://player.videasy.net',
  };

  Future<ExtractedMedia?> extract({
    required String tmdbId,
    required bool isMovie,
    int? season,
    int? episode,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      return await _extract(
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
      ).timeout(timeout);
    } on TimeoutException {
      onLog('[Videasy] Extraction timed out after ${timeout.inSeconds}s');
      return null;
    } catch (e, st) {
      onLog('[Videasy] Extraction failed: $e\n$st');
      return null;
    }
  }

  Future<ExtractedMedia?> _extract({
    required String tmdbId,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    final tmdb = int.tryParse(tmdbId);
    if (tmdb == null) {
      onLog('[Videasy] Invalid tmdbId: $tmdbId');
      return null;
    }

    final wasm = await _VideasyWasm.instance.ensureReady(onLog: onLog);
    if (wasm == null) {
      onLog('[Videasy] WASM runtime unavailable');
      return null;
    }

    // NOTE: mediaType is case-sensitive on the api.videasy.net side.
    // `Movie` works for either casing, but TV requires lowercase `tv` —
    // capital `TV` returns 500 across every provider. Verified 2026-05.
    final qp = <String, String>{
      'tmdbId': tmdbId,
      'mediaType': isMovie ? 'movie' : 'tv',
    };
    if (!isMovie) {
      qp['seasonId'] = '${season ?? 1}';
      qp['episodeId'] = '${episode ?? 1}';
    }

    final allSources = <StreamSource>[];
    final allSubs = <Map<String, dynamic>>[];
    String? firstProvider;

    for (final provider in _providers) {
      final uri = Uri.https(
        'api.videasy.net',
        '/$provider/sources-with-title',
        qp,
      );
      onLog('[Videasy] GET $uri');

      String hex;
      try {
        final res = await http
            .get(uri, headers: _baseHeaders)
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 200 || res.body.length < 100) {
          onLog('[Videasy] $provider -> ${res.statusCode} '
              '(${res.body.length} bytes), skip');
          continue;
        }
        hex = res.body.trim();
      } catch (e) {
        onLog('[Videasy] $provider fetch error: $e');
        continue;
      }

      String intermediate;
      try {
        intermediate = await wasm.decrypt(hex, tmdb);
      } catch (e) {
        onLog('[Videasy] $provider WASM decrypt error: $e');
        continue;
      }

      String json;
      try {
        json = _opensslAesDecrypt(intermediate, '');
      } catch (e) {
        onLog('[Videasy] $provider AES decrypt error: $e');
        continue;
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(json) as Map<String, dynamic>;
      } catch (e) {
        onLog('[Videasy] $provider JSON parse error: $e');
        continue;
      }

      final srcs = (data['sources'] as List?) ?? const [];
      final subs = (data['subtitles'] as List?) ?? const [];

      for (final s in srcs) {
        if (s is! Map) continue;
        final url = (s['url'] ?? s['file'] ?? '').toString();
        if (url.isEmpty) continue;
        final quality =
            (s['quality'] ?? s['label'] ?? s['title'] ?? 'auto').toString();
        final type = (s['type'] ?? (url.contains('.m3u8') ? 'hls' : 'video'))
            .toString();
        allSources.add(StreamSource(
          url: url,
          title: '$provider · $quality',
          type: type,
          headers: _playbackHeaders,
        ));
      }
      for (final sub in subs) {
        if (sub is! Map) continue;
        final url = (sub['url'] ?? sub['file'] ?? '').toString();
        if (url.isEmpty) continue;
        // Dedup across providers (same CDN often serves identical subs).
        if (allSubs.any((e) => e['url'] == url)) continue;
        final lang =
            (sub['lang'] ?? sub['language'] ?? sub['label'] ?? 'Unknown')
                .toString();
        final label = (sub['label'] ?? sub['title'] ?? lang).toString();
        allSubs.add({
          'url': url,
          'language': lang,
          // Schema expected by the player's subtitle menu (matches the
          // shape used by stremio/kisskh/subtitlecat extractors).
          'display': '$label - videasy/$provider',
        });
      }

      firstProvider ??= provider;
      onLog('[Videasy] $provider -> ${srcs.length} sources, '
          '${subs.length} subs');
      // No early break: harvest every provider so the user gets the full
      // server list in the source-switch menu (and combined sub catalogue).
    }

    if (allSources.isEmpty) {
      onLog('[Videasy] No sources from any provider');
      return null;
    }

    // Pick the highest-quality source as primary.
    allSources.sort((a, b) => _qualityRank(b.title) - _qualityRank(a.title));
    final primary = allSources.first;

    return ExtractedMedia(
      url: primary.url,
      headers: _playbackHeaders,
      sources: allSources,
      provider: 'videasy${firstProvider != null ? '/$firstProvider' : ''}',
      externalSubtitles: allSubs.isEmpty ? null : allSubs,
    );
  }

  static int _qualityRank(String title) {
    final t = title.toLowerCase();
    if (t.contains('2160') || t.contains('4k')) return 4;
    if (t.contains('1080')) return 3;
    if (t.contains('720')) return 2;
    if (t.contains('480')) return 1;
    return 0;
  }
}

// ─── OpenSSL/CryptoJS-compatible AES decrypt ─────────────────────────────────
String _opensslAesDecrypt(String b64, String passphrase) {
  final raw = base64Decode(b64);
  if (raw.length < 16 ||
      String.fromCharCodes(raw.sublist(0, 8)) != 'Salted__') {
    throw const FormatException('not an OpenSSL Salted__ blob');
  }
  final salt = raw.sublist(8, 16);
  final ct = Uint8List.fromList(raw.sublist(16));

  // EVP_BytesToKey(passphrase, salt, MD5, keyLen=32, ivLen=16)
  final pw = utf8.encode(passphrase);
  final out = BytesBuilder();
  Uint8List prev = Uint8List(0);
  while (out.length < 48) {
    final input = BytesBuilder()
      ..add(prev)
      ..add(pw)
      ..add(salt);
    prev = Uint8List.fromList(cryptolib.md5.convert(input.toBytes()).bytes);
    out.add(prev);
  }
  final keyIv = out.toBytes();
  final key = keyIv.sublist(0, 32);
  final iv = keyIv.sublist(32, 48);

  final cipher = pc.PaddedBlockCipherImpl(
    pc.PKCS7Padding(),
    pc.CBCBlockCipher(pc.AESEngine()),
  );
  cipher.init(
    false,
    pc.PaddedBlockCipherParameters(
      pc.ParametersWithIV<pc.KeyParameter>(pc.KeyParameter(key), iv),
      null,
    ),
  );
  final pt = cipher.process(ct);
  return utf8.decode(pt);
}

// ─── WASM runtime hosted in an invisible WebView (about:blank) ───────────────
//
// The WebView is purely a JavaScript+WebAssembly engine. It never loads any
// remote URL or DOM. The WASM bytes are inlined into the page via a base64
// argument passed to `window.__init`. Once instantiated, JS exposes
// `window.videasy_decrypt(hex, tmdbId)` which we call from Dart.
class _VideasyWasm {
  _VideasyWasm._();
  static final _VideasyWasm instance = _VideasyWasm._();

  HeadlessInAppWebView? _hw;
  InAppWebViewController? _controller;
  Completer<bool>? _ready;

  Future<_VideasyWasm?> ensureReady(
      {required void Function(String) onLog}) async {
    if (_ready != null) {
      final ok = await _ready!.future;
      return ok ? this : null;
    }
    _ready = Completer<bool>();

    try {
      final bytes = await rootBundle.load('assets/videasy/module.wasm');
      final wasmB64 = base64Encode(bytes.buffer.asUint8List());

      const html = '''
<!doctype html><html><head><meta charset="utf-8"></head><body>
<script>
(function(){
  function b64ToBytes(b64){
    var bin = atob(b64), len = bin.length, out = new Uint8Array(len);
    for (var i = 0; i < len; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  window.__init = async function(b64){
    try {
      var bytes = b64ToBytes(b64);
      var imports = {
        env: {
          abort: function(m,f,l,c){ throw new Error('wasm abort '+m+':'+l+':'+c); },
          seed: function(){ return Date.now(); }
        }
      };
      var inst = await WebAssembly.instantiate(bytes, imports);
      var E = inst.instance.exports;
      var mem = E.memory;
      function readStr(ptr){
        if (!ptr) return null;
        var dv = new DataView(mem.buffer);
        var bl = dv.getUint32(ptr - 4, true);
        return new TextDecoder('utf-16le').decode(new Uint8Array(mem.buffer, ptr, bl));
      }
      function writeStr(s){
        var u = new Uint16Array(s.length);
        for (var i = 0; i < s.length; i++) u[i] = s.charCodeAt(i);
        var ptr = E.__new(u.length * 2, 1);
        new Uint8Array(mem.buffer, ptr, u.length * 2).set(new Uint8Array(u.buffer));
        E.__pin(ptr);
        return ptr;
      }
      window.videasy_decrypt = function(hex, tmdbId){
        var p = writeStr(hex);
        var rp = E.decrypt(p, tmdbId) >>> 0;
        return readStr(rp);
      };
      return 'ok';
    } catch (e) {
      return 'err:' + (e && e.message || String(e));
    }
  };
})();
</script></body></html>
''';

      final completer = Completer<void>();
      _hw = HeadlessInAppWebView(
        initialData: InAppWebViewInitialData(
          data: html,
          mimeType: 'text/html',
          encoding: 'utf-8',
          baseUrl: WebUri('about:blank'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: VideasyExtractor.userAgent,
        ),
        onLoadStop: (c, _) {
          _controller = c;
          if (!completer.isCompleted) completer.complete();
        },
        onConsoleMessage: (_, msg) {
          onLog('[Videasy/wasm-console] ${msg.message}');
        },
      );
      await _hw!.run();
      await completer.future.timeout(const Duration(seconds: 15));

      final res = await _controller!.callAsyncJavaScript(
        functionBody: 'return await window.__init(b64);',
        arguments: {'b64': wasmB64},
      );
      if (res?.error != null) {
        onLog('[Videasy] WASM init JS error: ${res!.error}');
        _ready!.complete(false);
        return null;
      }
      final value = res?.value?.toString() ?? '';
      if (!value.startsWith('ok')) {
        onLog('[Videasy] WASM init failed: $value');
        _ready!.complete(false);
        return null;
      }

      onLog('[Videasy] WASM runtime ready');
      _ready!.complete(true);
      return this;
    } catch (e, st) {
      onLog('[Videasy] WASM bootstrap failed: $e\n$st');
      if (!_ready!.isCompleted) _ready!.complete(false);
      return null;
    }
  }

  Future<String> decrypt(String hex, int tmdbId) async {
    final c = _controller;
    if (c == null) throw StateError('WASM controller not initialized');
    final res = await c.callAsyncJavaScript(
      functionBody: 'return window.videasy_decrypt(hex, tmdbId);',
      arguments: {'hex': hex, 'tmdbId': tmdbId},
    );
    if (res?.error != null) throw Exception('JS: ${res!.error}');
    final v = res?.value;
    if (v is! String || v.isEmpty) {
      throw Exception('empty decrypt result (${v.runtimeType})');
    }
    return v;
  }
}
