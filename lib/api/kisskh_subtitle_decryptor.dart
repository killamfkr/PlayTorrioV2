// kisskh.co subtitle decryptor.
//
// kisskh ships SRT/VTT files where each cue's text body is AES-128-CBC
// encrypted and base64-encoded. The site decrypts client-side via an
// obfuscated CryptoJS bundle. Three key/IV pairs are in rotation, picked
// by the subtitle URL's file extension:
//
//   .srt  → plaintext (no encryption)
//   .txt  → key="8056483646328763"  iv="6852612370185273" (legacy)
//   .txt1 → key="AmSmZVcH93UQUezi"  iv="ReBKWW8cqdjPEnF6" (Feb 2025+)
//   other → key="sWODXX04QRTkHdlZ"  iv="8pwhapJeC4hrS9hO" (default)
//
// Source: kisskh-dl issue #14 + Prudhvi-pln/udb KissKhClient.py
//
// We download the file, decrypt cue-by-cue (lines that aren't valid
// ciphertext are kept verbatim → graceful fallback for partially-encrypted
// or future-rotated subs), write the result to the app's temp directory
// and return a `file://` URI for the player to consume directly.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

class _KeyIv {
  final Uint8List key;
  final Uint8List iv;
  const _KeyIv(this.key, this.iv);
}

class KissKhSubtitleDecryptor {
  static Uint8List _u8(String s) => Uint8List.fromList(utf8.encode(s));

  // Ordered list of candidate key/IV pairs, tried until one yields valid
  // PKCS7 padding & UTF-8. Order: most-recent first, then legacy, then
  // default fallback.
  static final List<_KeyIv> _keyVariants = [
    _KeyIv(_u8('AmSmZVcH93UQUezi'), _u8('ReBKWW8cqdjPEnF6')), // .txt1
    _KeyIv(_u8('8056483646328763'), _u8('6852612370185273')), // .txt legacy
    _KeyIv(_u8('sWODXX04QRTkHdlZ'), _u8('8pwhapJeC4hrS9hO')), // default
  ];

  /// Pick a preferred key/IV by URL file extension. Returns null for `.srt`
  /// (already plaintext).
  static _KeyIv? _preferredFor(String url) {
    final ext = url.split('?').first.split('.').last.toLowerCase();
    switch (ext) {
      case 'srt':
        return null;
      case 'txt':
        return _keyVariants[1];
      case 'txt1':
        return _keyVariants[0];
      default:
        return _keyVariants[2];
    }
  }

  static String? _tryDecrypt(Uint8List ct, _KeyIv kiv) {
    try {
      final cipher = CBCBlockCipher(AESEngine())
        ..init(false, ParametersWithIV(KeyParameter(kiv.key), kiv.iv));
      final out = Uint8List(ct.length);
      for (var off = 0; off < ct.length; off += 16) {
        cipher.processBlock(ct, off, out, off);
      }
      final pad = out.last;
      if (pad < 1 || pad > 16) return null;
      for (var i = out.length - pad; i < out.length; i++) {
        if (out[i] != pad) return null;
      }
      return utf8.decode(out.sublist(0, out.length - pad), allowMalformed: false);
    } catch (_) {
      return null;
    }
  }

  /// Try to decrypt a single base64-encoded ciphertext line. If [preferred]
  /// is given, that key/IV is tried first. Returns null on any failure so
  /// the caller can fall back to the original text.
  static String? decryptCue(String b64, {Object? preferred}) {
    final trimmed = b64.trim();
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(trimmed)) return null;
    Uint8List ct;
    try {
      ct = base64.decode(trimmed);
    } catch (_) {
      return null;
    }
    if (ct.isEmpty || ct.length % 16 != 0) return null;
    if (preferred != null) {
      final r = _tryDecrypt(ct, preferred as _KeyIv);
      if (r != null) return r;
    }
    for (final kiv in _keyVariants) {
      if (identical(kiv, preferred)) continue;
      final r = _tryDecrypt(ct, kiv);
      if (r != null) return r;
    }
    return null;
  }

  /// Decrypt every cue text line in a SRT/VTT body. Index lines, timestamp
  /// lines (`-->`), the `WEBVTT` header and blank separators are kept as-is.
  static String decryptBody(String body, {String? sourceUrl}) {
    final preferred = sourceUrl != null ? _preferredFor(sourceUrl) : null;
    final lines = body.split(RegExp(r'\r?\n'));
    final out = StringBuffer();
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty ||
          t == 'WEBVTT' ||
          t.startsWith('NOTE') ||
          RegExp(r'^\d+$').hasMatch(t) ||
          line.contains('-->')) {
        out.writeln(line);
        continue;
      }
      final decoded = decryptCue(line, preferred: preferred);
      out.writeln(decoded ?? line);
    }
    return out.toString();
  }

  /// Download the subtitle at [url] (with kisskh headers), decrypt it, persist
  /// to the temp directory and return a `file://` URI. Returns null on any
  /// failure so the caller can keep the original remote URL.
  static Future<String?> fetchAndDecrypt({
    required String url,
    required int episodeId,
    required String language,
    required String userAgent,
    required String referer,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', userAgent);
      req.headers.set('Referer', referer);
      req.headers.set('Accept', '*/*');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        debugPrint('[KissKhSub] HTTP ${res.statusCode} for $url');
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      debugPrint('[KissKhSub] fetched ${body.length} chars from $url');
      final ext = url.split('?').first.split('.').last.toLowerCase();
      final decoded = (ext == 'srt') ? body : decryptBody(body, sourceUrl: url);

      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/kisskh_subs');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final safeLang = language.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final isVtt = url.toLowerCase().contains('.vtt') ||
          decoded.trimLeft().startsWith('WEBVTT');
      final outExt = isVtt ? 'vtt' : 'srt';
      final file =
          File('${dir.path}/${episodeId}_${safeLang}_$ts.$outExt');
      await file.writeAsString(decoded);
      debugPrint('[KissKhSub] wrote ${file.path} (${decoded.length} chars)');

      return Uri.file(file.path).toString();
    } catch (e, st) {
      debugPrint('[KissKhSub] decrypt failed for $url: $e\n$st');
      return null;
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }
}
