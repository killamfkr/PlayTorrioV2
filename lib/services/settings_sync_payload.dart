import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/settings_service.dart';
import '../api/trakt_service.dart';

/// Serializable snapshot of SharedPreferences + known secure keys for LAN sync.
class SettingsSyncPayload {
  SettingsSyncPayload._();

  static const int currentVersion = 1;

  /// All [FlutterSecureStorage] keys this app uses (debrid, trakt, SOCKS5).
  static const List<String> secureStorageKeys = [
    'rd_client_id',
    'rd_client_secret',
    'rd_access_token',
    'rd_refresh_token',
    'rd_token_expiry',
    'torbox_api_key',
    'trakt_access_token',
    'trakt_refresh_token',
    'trakt_expires_at',
    'socks5_password',
  ];

  static Map<String, dynamic>? _typedPref(SharedPreferences p, String key) {
    final list = p.getStringList(key);
    if (list != null) {
      return {'type': 'StringList', 'value': list};
    }
    final s = p.getString(key);
    if (s != null) {
      return {'type': 'String', 'value': s};
    }
    final i = p.getInt(key);
    if (i != null) {
      return {'type': 'int', 'value': i};
    }
    final d = p.getDouble(key);
    if (d != null) {
      return {'type': 'double', 'value': d};
    }
    final b = p.getBool(key);
    if (b != null) {
      return {'type': 'bool', 'value': b};
    }
    return null;
  }

  /// Build JSON-ready map for export over the network.
  static Future<Map<String, dynamic>> buildExport() async {
    final prefs = await SharedPreferences.getInstance();
    final prefMap = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final typed = _typedPref(prefs, key);
      if (typed != null) {
        prefMap[key] = typed;
      }
    }

    const secure = FlutterSecureStorage();
    final secrets = <String, String?>{};
    for (final key in secureStorageKeys) {
      secrets[key] = await secure.read(key: key);
    }

    return {
      'syncVersion': currentVersion,
      'preferences': prefMap,
      'secure': secrets,
    };
  }

  /// Apply payload from [buildExport]. Throws if version is unsupported.
  static Future<void> applyImport(Map<String, dynamic> raw) async {
    final ver = raw['syncVersion'];
    final verInt = ver is int ? ver : (ver is num ? ver.toInt() : null);
    if (verInt != currentVersion) {
      throw FormatException('Unsupported sync payload version: $ver');
    }

    final prefsRaw = raw['preferences'];
    if (prefsRaw is! Map) {
      throw const FormatException('Invalid preferences in sync payload');
    }
    final prefsData = Map<String, dynamic>.from(prefsRaw);

    final prefs = await SharedPreferences.getInstance();
    for (final e in prefsData.entries) {
      final key = e.key;
      final wrap = e.value;
      if (wrap is! Map) continue;
      final wm = Map<String, dynamic>.from(wrap);
      final type = wm['type'];
      final value = wm['value'];
      switch (type) {
        case 'String':
          if (value is String) await prefs.setString(key, value);
          break;
        case 'bool':
          if (value is bool) await prefs.setBool(key, value);
          break;
        case 'int':
          if (value is int) await prefs.setInt(key, value);
          break;
        case 'double':
          if (value is num) await prefs.setDouble(key, value.toDouble());
          break;
        case 'StringList':
          if (value is List) {
            await prefs.setStringList(
              key,
              value.map((x) => x.toString()).toList(),
            );
          }
          break;
        default:
          debugPrint('[SettingsSync] Skipping unknown pref type for $key: $type');
      }
    }

    final secRaw = raw['secure'];
    if (secRaw is Map) {
      final sec = Map<String, dynamic>.from(secRaw);
      const secure = FlutterSecureStorage();
      for (final e in sec.entries) {
        final k = e.key;
        final v = e.value;
        if (v == null || (v is String && v.isEmpty)) {
          await secure.delete(key: k);
        } else if (v is String) {
          await secure.write(key: k, value: v);
        }
      }
    }

    SettingsService.addonChangeNotifier.value++;
    SettingsService.navbarChangeNotifier.value++;
    final trakt = TraktService();
    TraktService.loginNotifier.value = await trakt.isLoggedIn();
  }
}
