import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/settings_service.dart';
import 'socks5_handshake.dart';

/// Global SOCKS5 for `dart:io` [HttpClient] (used by `package:http` [IOClient]).
///
/// Call [installHttpOverrides] from `main()` before other services run network I/O.
/// After changing SOCKS settings in the UI, call [refreshFromStorage] and prefer an
/// app restart so existing [http.Client] instances pick up the new tunnel.
class PlayTorrioNetwork {
  PlayTorrioNetwork._();

  static const _secureKeyPassword = 'socks5_password';
  static final _secure = FlutterSecureStorage();

  static bool _socksEnabled = false;
  static String _socksHost = '';
  static int _socksPort = 1080;
  static String _socksUsername = '';
  static String _socksPassword = '';

  static bool get socksEnabled => _socksEnabled;
  static String get socksHost => _socksHost;
  static int get socksPort => _socksPort;
  static String get socksUsername => _socksUsername;

  /// Load prefs + password and install [HttpOverrides]. Safe to call multiple times.
  static Future<void> installHttpOverrides() async {
    if (kIsWeb) return;
    await refreshFromStorage();
  }

  /// Reload from [SharedPreferences] and secure storage; recreates [HttpOverrides.global].
  static Future<void> refreshFromStorage() async {
    if (kIsWeb) return;

    final settings = SettingsService();

    _socksEnabled = await settings.getSocks5Enabled();
    _socksHost = (await settings.getSocks5Host()).trim();
    _socksPort = await settings.getSocks5Port();
    _socksUsername = (await settings.getSocks5Username()).trim();
    _socksPassword = (await _secure.read(key: _secureKeyPassword)) ?? '';

    if (_socksPort <= 0 || _socksPort > 65535) {
      _socksPort = 1080;
    }

    HttpOverrides.global = _PlayTorrioHttpOverrides(
      enabled: _socksEnabled,
      host: _socksHost,
      port: _socksPort,
      username: _socksUsername,
      password: _socksPassword,
    );
  }

  static Future<void> savePassword(String? password) async {
    if (password == null || password.isEmpty) {
      await _secure.delete(key: _secureKeyPassword);
      _socksPassword = '';
      return;
    }
    await _secure.write(key: _secureKeyPassword, value: password);
    _socksPassword = password;
  }

  static Future<void> clearPassword() => savePassword(null);
}

class _PlayTorrioHttpOverrides extends HttpOverrides {
  _PlayTorrioHttpOverrides({
    required this.enabled,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  final bool enabled;
  final String host;
  final int port;
  final String username;
  final String password;

  bool get _active => enabled && host.isNotEmpty && port > 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (!_active) {
      return client;
    }

    final h = host;
    final p = port;
    final u = username;
    final pw = password;

    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final targetPort =
          uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final socket = await Socket.connect(
        h,
        p,
        timeout: const Duration(seconds: 25),
      );
      try {
        await Socks5Handshake.complete(
          socket,
          targetHost: uri.host,
          targetPort: targetPort,
          username: u.isNotEmpty ? u : null,
          password: pw.isNotEmpty ? pw : null,
        );
      } catch (e) {
        await socket.close();
        rethrow;
      }
      return ConnectionTask.fromSocket(
        Future<Socket>.value(socket),
        () {
          socket.destroy();
        },
      );
    };

    return client;
  }
}
