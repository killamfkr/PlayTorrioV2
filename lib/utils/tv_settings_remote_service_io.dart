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

/// Serves a small HTML UI on the LAN so a phone can change common toggles and
/// import/export full settings JSON (token-protected). Android TV only.
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

  /// Stop and start with a fresh token (invalidates old QR codes).
  Future<void> restart() async {
    await stop();
    await ensureStarted();
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
    router.get('/api/quick-state', _handleQuickState);
    router.post('/api/quick-set', _handleQuickSet);
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

  Future<Map<String, dynamic>> _readQuickStateMap() async {
    final s = SettingsService();
    return <String, dynamic>{
      'lightMode': await s.isLightModeEnabled(),
      'streamingMode': await s.isStreamingModeEnabled(),
      'continuePlaybackInBackground': await s.continuePlaybackInBackground(),
      'builtinPlayerSubtitlesEnabled': await s.getBuiltinPlayerSubtitlesEnabled(),
      'autoAdvanceNextEpisode': await s.getAutoAdvanceNextEpisode(),
      'showAndroidPipButton': await s.showAndroidPipButton(),
      'autoEnterPipAndroid': await s.autoEnterPipAndroid(),
      'torrentAutoPickEnabled': await s.getTorrentAutoPickEnabled(),
      'stremioAutoPlayEnabled': await s.getStremioAutoPlayEnabled(),
      'ptCloudProgressSync': await s.isPlaytorrioCloudProgressSyncEnabled(),
      'ptCloudSettingsSync': await s.isPlaytorrioCloudSettingsSyncEnabled(),
      'ptCloudDebridSync': await s.isPlaytorrioCloudDebridSyncEnabled(),
      'externalPlayer': await s.getExternalPlayer(),
    };
  }

  Future<Response> _handleQuickState(Request request) async {
    try {
      final map = await _readQuickStateMap();
      return Response.ok(
        json.encode(map),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: '$e');
    }
  }

  Future<Response> _handleQuickSet(Request request) async {
    try {
      final body = await request.readAsString();
      if (body.isEmpty) {
        return Response(400, body: 'Empty body');
      }
      final decoded = json.decode(body);
      if (decoded is! Map) {
        return Response(400, body: 'JSON must be an object');
      }
      final key = decoded['key']?.toString();
      final value = decoded['value'];
      if (key == null || key.isEmpty) {
        return Response(400, body: 'Missing key');
      }

      final s = SettingsService();
      switch (key) {
        case 'lightMode':
          if (value is bool) await s.setLightMode(value);
          break;
        case 'streamingMode':
          if (value is bool) await s.setStreamingMode(value);
          break;
        case 'continuePlaybackInBackground':
          if (value is bool) await s.setContinuePlaybackInBackground(value);
          break;
        case 'builtinPlayerSubtitlesEnabled':
          if (value is bool) await s.setBuiltinPlayerSubtitlesEnabled(value);
          break;
        case 'autoAdvanceNextEpisode':
          if (value is bool) await s.setAutoAdvanceNextEpisode(value);
          break;
        case 'showAndroidPipButton':
          if (value is bool) await s.setShowAndroidPipButton(value);
          break;
        case 'autoEnterPipAndroid':
          if (value is bool) await s.setAutoEnterPipAndroid(value);
          break;
        case 'torrentAutoPickEnabled':
          if (value is bool) await s.setTorrentAutoPickEnabled(value);
          break;
        case 'stremioAutoPlayEnabled':
          if (value is bool) await s.setStremioAutoPlayEnabled(value);
          break;
        case 'ptCloudProgressSync':
          if (value is bool) await s.setPlaytorrioCloudProgressSyncEnabled(value);
          break;
        case 'ptCloudSettingsSync':
          if (value is bool) await s.setPlaytorrioCloudSettingsSyncEnabled(value);
          break;
        case 'ptCloudDebridSync':
          if (value is bool) await s.setPlaytorrioCloudDebridSyncEnabled(value);
          break;
        default:
          return Response(400, body: 'Unknown or unsupported key');
      }

      SettingsService.bumpRemoteLanSettingsRevision();
      final map = await _readQuickStateMap();
      return Response.ok(
        json.encode({'ok': true, 'state': map}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    } catch (e, st) {
      debugPrint('[TvSettingsRemote] quick-set failed: $e\n$st');
      return Response(400, body: 'quick-set failed: $e');
    }
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
  body { font-family: system-ui, sans-serif; margin: 16px; max-width: 560px; line-height: 1.35; }
  h1 { font-size: 1.25rem; }
  h2 { font-size: 1.05rem; margin-top: 24px; }
  .row { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 10px 0; border-bottom: 1px solid #eee; }
  .row span { flex: 1; }
  button.small { padding: 8px 14px; font-size: 14px; margin-top: 0; }
  textarea { width: 100%; height: 160px; font-size: 12px; font-family: ui-monospace, monospace; }
  button.big { margin-top: 12px; padding: 12px 20px; font-size: 16px; }
  .ok { color: #0a0; }
  .err { color: #c00; }
  #externalPlayer { font-size: 13px; color: #444; margin: 8px 0 16px; }
</style>
</head>
<body>
  <h1>PlayTorrio on TV</h1>
  <p>Phone and TV must be on the same Wi‑Fi. Use the buttons for common options; full backup still uses JSON below.</p>
  <div id="externalPlayer"></div>
  <h2>Quick toggles</h2>
  <div id="quick"></div>
  <p id="quickMsg" class="err"></p>

  <h2>Full backup</h2>
  <p>Paste JSON from <strong>Export settings</strong> on another device, then tap Import.</p>
  <textarea id="json" placeholder='{"version":1,...}'></textarea>
  <div>
    <button type="button" class="big" id="go">Import full JSON to TV</button>
  </div>
  <p id="msg"></p>

  <script>
    const T = ${jsonEncode(tok)};
    const labels = {
      lightMode: 'Light mode',
      streamingMode: 'Direct streaming mode',
      continuePlaybackInBackground: 'Continue playback in background',
      builtinPlayerSubtitlesEnabled: 'Show subtitles (built-in)',
      autoAdvanceNextEpisode: 'Auto-advance next episode',
      showAndroidPipButton: 'PiP button (Android)',
      autoEnterPipAndroid: 'Auto-enter PiP',
      torrentAutoPickEnabled: 'Torrent auto-pick',
      stremioAutoPlayEnabled: 'Stremio auto-play',
      ptCloudProgressSync: 'Cloud: sync Continue watching',
      ptCloudSettingsSync: 'Cloud: sync app settings',
      ptCloudDebridSync: 'Cloud: sync debrid keys'
    };
    const boolKeys = Object.keys(labels);

    async function api(path, opts) {
      const u = path + (path.includes('?') ? '&' : '?') + 't=' + encodeURIComponent(T);
      return fetch(u, Object.assign({}, opts, {
        headers: Object.assign({'X-PT-Token': T}, (opts && opts.headers) || {})
      }));
    }

    function renderQuick(state) {
      const root = document.getElementById('quick');
      root.innerHTML = '';
      const ep = document.getElementById('externalPlayer');
      ep.textContent = 'Video player: ' + (state.externalPlayer || '—');
      for (const k of boolKeys) {
        const row = document.createElement('div');
        row.className = 'row';
        const lab = document.createElement('span');
        lab.textContent = labels[k] || k;
        const btn = document.createElement('button');
        btn.className = 'small';
        btn.type = 'button';
        const on = !!state[k];
        btn.textContent = on ? 'On' : 'Off';
        btn.onclick = async () => {
          document.getElementById('quickMsg').textContent = '';
          try {
            const res = await api('/api/quick-set', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({ key: k, value: !on })
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok) throw new Error(data.error || res.status);
            renderQuick(data.state || state);
          } catch (e) {
            document.getElementById('quickMsg').textContent = String(e);
          }
        };
        row.appendChild(lab);
        row.appendChild(btn);
        root.appendChild(row);
      }
    }

    async function loadQuick() {
      try {
        const res = await api('/api/quick-state');
        const state = await res.json();
        if (!res.ok) throw new Error(JSON.stringify(state));
        renderQuick(state);
      } catch (e) {
        document.getElementById('quickMsg').textContent = 'Could not load state: ' + e;
      }
    }

    loadQuick();

    document.getElementById('go').onclick = async function() {
      const msg = document.getElementById('msg');
      msg.textContent = '';
      const raw = document.getElementById('json').value.trim();
      if (!raw) { msg.textContent = 'Paste JSON first.'; msg.className = 'err'; return; }
      try {
        const res = await api('/api/import', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: raw
        });
        const text = await res.text();
        if (res.ok) {
          msg.textContent = 'Imported. Check your TV.';
          msg.className = 'ok';
          loadQuick();
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
      SettingsService.bumpRemoteLanSettingsRevision();
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
    _lanIp = null;
  }
}
