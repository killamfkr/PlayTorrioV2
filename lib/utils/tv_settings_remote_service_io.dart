import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import '../api/settings_service.dart';
import '../platform_flags.dart';

/// Serves a tiny HTML page on the LAN so a phone can paste exported settings JSON
/// and POST them to the TV (token-protected). Android TV only.
class TvSettingsRemoteService {
  static final TvSettingsRemoteService _instance =
      TvSettingsRemoteService._internal();
  factory TvSettingsRemoteService() => _instance;
  TvSettingsRemoteService._internal();

  static const MethodChannel _deviceChannel =
      MethodChannel('com.example.play_torrio_native/device');

  HttpServer? _server;
  String? _token;
  String? _lanIp;
  int _port = 0;

  int get port => _port;
  String? get remoteUrl {
    if (_lanIp == null || _token == null || _port == 0) return null;
    return 'http://$_lanIp:$_port/?t=${Uri.encodeQueryComponent(_token!)}';
  }

  bool get isRunning => _server != null;

  /// Re-read LAN IPv4 (e.g. after resume or DHCP change) so the QR URL stays correct.
  Future<void> refreshLanIp() async {
    if (_server == null || kIsWeb || !platformIsAndroid) return;
    try {
      final ip = await _deviceChannel.invokeMethod<String>('getLanIpv4');
      if (ip != null && ip.isNotEmpty) {
        _lanIp = ip;
        debugPrint('[TvSettingsRemote] LAN IP refreshed: $ip');
      }
    } catch (e) {
      debugPrint('[TvSettingsRemote] refreshLanIp: $e');
    }
  }

  Future<void> ensureStarted() async {
    if (_server != null) return;
    if (kIsWeb || !platformIsAndroid) return;

    bool isTv = false;
    try {
      isTv = await _deviceChannel.invokeMethod<bool>('isAndroidTv') ?? false;
    } catch (_) {}
    if (!isTv) return;

    String? ip;
    try {
      ip = await _deviceChannel.invokeMethod<String>('getLanIpv4');
    } catch (_) {}
    if (ip == null || ip.isEmpty) {
      debugPrint('[TvSettingsRemote] No LAN IPv4; remote settings disabled');
      return;
    }

    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    _token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _lanIp = ip;

    final router = Router();
    router.get('/', _handleIndex);
    router.post('/api/import', _handleImport);
    router.get('/api/export', _handleExport);

    Handler pipeline = const Pipeline()
        .addMiddleware(_authMiddleware())
        .addHandler(router.call);

    const candidates = [8787, 8788, 8789, 8790, 8791, 8792];
    for (final p in candidates) {
      try {
        _server = await io.serve(
          pipeline,
          InternetAddress.anyIPv4,
          p,
        );
        _port = p;
        debugPrint('[TvSettingsRemote] http://$ip:$p/ (token in URL)');
        return;
      } catch (e) {
        debugPrint('[TvSettingsRemote] Port $p busy: $e');
      }
    }
    _token = null;
    _lanIp = null;
    debugPrint('[TvSettingsRemote] Could not bind; giving up');
  }

  Middleware _authMiddleware() {
    return (Handler inner) {
      return (Request request) {
        final t = request.url.queryParameters['t'] ??
            request.headers['x-pt-token'];
        if (t == null || t != _token) {
          return Response.forbidden('Invalid or missing token');
        }
        return inner(request);
      };
    };
  }

  Future<Response> _handleIndex(Request request) {
    final tok = _token!;
    final html = '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>PlayTorrio — TV settings</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 16px; max-width: 560px; }
  h1 { font-size: 1.2rem; }
  textarea { width: 100%; height: 200px; font-size: 12px; }
  button { margin-top: 12px; padding: 12px 20px; font-size: 16px; }
  .ok { color: #0a0; }
  .err { color: #c00; }
</style>
</head>
<body>
  <h1>Send settings to TV</h1>
  <p>Paste the JSON from <strong>Export settings</strong> on another device, then tap Import.</p>
  <textarea id="json" placeholder='{"version":1,...}'></textarea>
  <div>
    <button type="button" id="go">Import to TV</button>
  </div>
  <p id="msg"></p>
  <script>
    const T = ${jsonEncode(tok)};
    document.getElementById('go').onclick = async function() {
      const msg = document.getElementById('msg');
      msg.textContent = '';
      const raw = document.getElementById('json').value.trim();
      if (!raw) { msg.textContent = 'Paste JSON first.'; msg.className = 'err'; return; }
      try {
        const res = await fetch('/api/import?t=' + encodeURIComponent(T), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-PT-Token': T },
          body: raw
        });
        const text = await res.text();
        if (res.ok) {
          msg.textContent = 'Imported. Check your TV.';
          msg.className = 'ok';
        } else {
          msg.textContent = 'Error: ' + res.status + ' ' + text;
          msg.className = 'err';
        }
      } catch (e) {
        msg.textContent = String(e);
        msg.className = 'err';
      }
    };
  </script>
</body>
</html>
''';
    return Future.value(Response.ok(
      html,
      headers: {'content-type': 'text/html; charset=utf-8'},
    ));
  }

  Future<Response> _handleImport(Request request) async {
    try {
      final body = await request.readAsString();
      if (body.isEmpty) {
        return Response(400, body: 'Empty body');
      }
      final data = json.decode(body);
      if (data is! Map<String, dynamic>) {
        return Response(400, body: 'JSON must be an object');
      }
      await SettingsService().importAllSettings(data);
      return Response.ok(
        json.encode({'ok': true}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e, st) {
      debugPrint('[TvSettingsRemote] import failed: $e\n$st');
      return Response(400, body: 'Import failed: $e');
    }
  }

  Future<Response> _handleExport(Request request) async {
    try {
      final data = await SettingsService().exportAllSettings();
      return Response.ok(
        JsonEncoder.withIndent('  ').convert(data),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: '$e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
    _token = null;
  }
}
