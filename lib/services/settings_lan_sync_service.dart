import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../network/play_torrio_network.dart';
import 'settings_sync_payload.dart';

/// Short-lived HTTP server on the phone so Android TV (same LAN) can pull settings.
class SettingsLanSyncService {
  SettingsLanSyncService._();
  static final SettingsLanSyncService instance = SettingsLanSyncService._();

  static const int defaultPort = 37521;
  static const String pathPrefix = '/playtorrio-sync/v1';
  static const Duration hostTimeout = Duration(minutes: 15);

  HttpServer? _server;
  String? _token;
  Timer? _shutdownTimer;

  bool get isHosting => _server != null;
  int get port => _server?.port ?? 0;
  String? get token => _token;

  /// Best-effort LAN IPv4 for display (phone → TV setup).
  static Future<String?> guessLanIPv4() async {
    try {
      for (final iface in await NetworkInterface.list()) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('[LanSync] guessLanIPv4: $e');
    }
    return null;
  }

  String _newToken() {
    final r = Random.secure();
    return (100000 + r.nextInt(900000)).toString();
  }

  /// Binds [InternetAddress.anyIPv4] starting at [defaultPort].
  Future<void> startHosting() async {
    if (kIsWeb) return;
    await stopHosting();

    _token = _newToken();
    final router = Router();

    router.get('$pathPrefix/ping', (Request request) {
      return Response.ok(
        json.encode({'app': 'playtorrio', 'syncVersion': SettingsSyncPayload.currentVersion}),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('$pathPrefix/export', (Request request) async {
      final auth = request.headers['authorization'] ?? '';
      final expected = 'Bearer ${_token ?? ''}';
      if (auth != expected) {
        return Response.forbidden(
          json.encode({'error': 'invalid or missing token'}),
          headers: {'content-type': 'application/json'},
        );
      }
      try {
        final body = await SettingsSyncPayload.buildExport();
        return Response.ok(
          json.encode(body),
          headers: {'content-type': 'application/json'},
        );
      } catch (e, st) {
        debugPrint('[LanSync] export failed: $e\n$st');
        return Response.internalServerError(
          body: json.encode({'error': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    Object? bindError;
    for (var attempt = 0; attempt < 20; attempt++) {
      final tryPort = defaultPort + attempt;
      try {
        _server = await shelf_io.serve(
          router.call,
          InternetAddress.anyIPv4,
          tryPort,
        );
        bindError = null;
        break;
      } catch (e) {
        bindError = e;
        _server = null;
      }
    }
    if (_server == null) {
      _token = null;
      throw StateError('Could not bind LAN sync server: $bindError');
    }

    debugPrint('[LanSync] Hosting on 0.0.0.0:${_server!.port} token=$_token');

    _shutdownTimer?.cancel();
    _shutdownTimer = Timer(hostTimeout, () {
      debugPrint('[LanSync] Auto-stopping host after timeout');
      stopHosting();
    });
  }

  Future<void> stopHosting() async {
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
    final s = _server;
    _server = null;
    _token = null;
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (e) {
        debugPrint('[LanSync] close server: $e');
      }
    }
  }

  /// TV / receiver: fetch settings from phone at `http://IP:port`.
  static Future<void> importFromHost({
    required String host,
    required int port,
    required String token,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('LAN sync is not available on web');
    }

    final base = host.trim();
    if (base.isEmpty) {
      throw ArgumentError('Host is empty');
    }
    final uri = Uri(
      scheme: 'http',
      host: base,
      port: port,
      path: '$pathPrefix/export',
    );

    final client = http.Client();
    try {
      final res = await client
          .get(
            uri,
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        throw HttpException('Sync failed (${res.statusCode}): ${res.body}');
      }

      final decoded = json.decode(res.body);
      if (decoded is! Map) {
        throw const FormatException('Sync response is not a JSON object');
      }
      final raw = Map<String, dynamic>.from(decoded);
      await SettingsSyncPayload.applyImport(raw);
      await PlayTorrioNetwork.refreshFromStorage();
    } finally {
      client.close();
    }
  }
}
