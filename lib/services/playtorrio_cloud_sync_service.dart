import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/debrid_api.dart';
import '../api/settings_service.dart';
import 'watch_history_service.dart';

/// **Supabase** — defaults point at the PlayTorrio project; override with
/// `PLAYTORRIO_SUPABASE_URL` / `PLAYTORRIO_SUPABASE_ANON_KEY` via `--dart-define` if needed.
///
/// **Database:** run `supabase/migrations/20260401000000_playtorrio_user_sync.sql` in the SQL editor.

const String kPlaytorrioSupabaseUrl = String.fromEnvironment(
  'PLAYTORRIO_SUPABASE_URL',
  defaultValue: 'https://lxapazzlduwwecatebti.supabase.co',
);
const String kPlaytorrioSupabaseAnonKey = String.fromEnvironment(
  'PLAYTORRIO_SUPABASE_ANON_KEY',
  defaultValue:
      'sb_publishable_kg9O7hjt0PKdXDpvuC9scQ_KRsw4MLg',
);

class PlaytorrioCloudSyncService {
  PlaytorrioCloudSyncService._();
  static final PlaytorrioCloudSyncService instance = PlaytorrioCloudSyncService._();

  static const _accessKey = 'pt_supabase_access_token';
  static const _refreshKey = 'pt_supabase_refresh_token';

  static const _restWatch = '/rest/v1/user_watch_history';
  static const _restSettings = '/rest/v1/user_settings';
  static const _restDebrid = '/rest/v1/user_debrid_secrets';

  final _secure = const FlutterSecureStorage();
  final _settings = SettingsService();

  String? _access;
  String? _refresh;

  String? get _base {
    final u = kPlaytorrioSupabaseUrl.trim();
    if (u.isEmpty) return null;
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  String? get _anon {
    final k = kPlaytorrioSupabaseAnonKey.trim();
    return k.isEmpty ? null : k;
  }

  bool get isConfigured => _base != null && _anon != null;

  void _requireConfig() {
    if (!isConfigured) {
      throw const PlaytorrioCloudException(
        'Supabase URL/key missing. Set PLAYTORRIO_SUPABASE_URL and '
        'PLAYTORRIO_SUPABASE_ANON_KEY in your build, or edit the defaults in '
        'lib/services/playtorrio_cloud_sync_service.dart (dev only). '
        'Apply the SQL in supabase/migrations/ for tables and RLS.',
      );
    }
  }

  Future<String?> get _accessToken async {
    if (_access != null && _access!.isNotEmpty) return _access;
    _access = await _secure.read(key: _accessKey);
    return _access;
  }

  Future<String?> get _refreshToken async {
    if (_refresh != null && _refresh!.isNotEmpty) return _refresh;
    _refresh = await _secure.read(key: _refreshKey);
    return _refresh;
  }

  Future<void> _saveSession(String access, String? refresh) async {
    _access = access;
    await _secure.write(key: _accessKey, value: access);
    if (refresh != null && refresh.isNotEmpty) {
      _refresh = refresh;
      await _secure.write(key: _refreshKey, value: refresh);
    }
  }

  Map<String, String> _headers(String token) => {
        'apikey': _anon!,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  static String? userIdFromJwt(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    var seg = parts[1];
    final m = seg.length % 4;
    if (m > 0) seg += '=' * (4 - m);
    try {
      final jsonMap = json.decode(utf8.decode(base64Url.decode(seg)))
          as Map<String, dynamic>;
      return jsonMap['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _currentUserId() async {
    final t = await _accessToken;
    if (t == null) return null;
    return userIdFromJwt(t);
  }

  Future<void> _ensureAccess() async {
    if ((await _accessToken)?.isNotEmpty == true) return;
    final rt = await _refreshToken;
    if (rt == null || rt.isEmpty) {
      throw const PlaytorrioCloudException('Not signed in');
    }
    _requireConfig();
    final res = await http.post(
      Uri.parse('$_base/auth/v1/token?grant_type=refresh_token'),
      headers: {
        'apikey': _anon!,
        'Content-Type': 'application/json',
      },
      body: json.encode({'refresh_token': rt}),
    );
    if (res.statusCode != 200) {
      await signOut();
      throw const PlaytorrioCloudException('Session expired. Sign in again.');
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    await _saveSession(
      data['access_token'] as String,
      data['refresh_token'] as String?,
    );
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _requireConfig();
    final res = await http.post(
      Uri.parse('$_base/auth/v1/token?grant_type=password'),
      headers: {
        'apikey': _anon!,
        'Content-Type': 'application/json',
      },
      body: json.encode({'email': email.trim(), 'password': password}),
    );
    if (res.statusCode != 200) {
      var msg = res.body;
      try {
        final m = json.decode(res.body) as Map<String, dynamic>?;
        msg = m?['error_description']?.toString() ?? m?['message']?.toString() ?? msg;
      } catch (_) {}
      throw PlaytorrioCloudException(msg);
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    await _saveSession(
      data['access_token'] as String,
      data['refresh_token'] as String?,
    );
  }

  /// Create account. If email confirmation is required, user must sign in after confirming.
  Future<void> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    _requireConfig();
    final res = await http.post(
      Uri.parse('$_base/auth/v1/signup'),
      headers: {
        'apikey': _anon!,
        'Content-Type': 'application/json',
      },
      body: json.encode({'email': email.trim(), 'password': password}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      var msg = res.body;
      try {
        final m = json.decode(res.body) as Map<String, dynamic>?;
        msg = m?['error_description']?.toString() ?? m?['message']?.toString() ?? msg;
      } catch (_) {}
      throw PlaytorrioCloudException(msg);
    }
    final data = json.decode(res.body) as Map<String, dynamic>?;
    final at = data?['access_token'] as String?;
    if (at != null && at.isNotEmpty) {
      await _saveSession(at, data!['refresh_token'] as String?);
      return;
    }
    await signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    final token = await _accessToken;
    if (token != null && token.isNotEmpty && isConfigured) {
      try {
        unawaited(http.post(
          Uri.parse('$_base/auth/v1/logout'),
          headers: {
            'apikey': _anon!,
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ));
      } catch (_) {}
    }
    _access = null;
    _refresh = null;
    await _secure.delete(key: _accessKey);
    await _secure.delete(key: _refreshKey);
  }

  Future<bool> hasStoredSession() async =>
      (await _accessToken)?.isNotEmpty == true || (await _refreshToken)?.isNotEmpty == true;

  // ── Watch history sync ─────────────────────────────────────────────────

  Future<bool> isProgressSyncEnabled() => _settings.isPlaytorrioCloudProgressSyncEnabled();

  Future<void> setProgressSyncEnabled(bool v) =>
      _settings.setPlaytorrioCloudProgressSyncEnabled(v);

  // ── Settings (prefs) sync ─────────────────────────────────────────────

  Future<bool> isSettingsSyncEnabled() => _settings.isPlaytorrioCloudSettingsSyncEnabled();

  Future<void> setSettingsSyncEnabled(bool v) =>
      _settings.setPlaytorrioCloudSettingsSyncEnabled(v);

  Future<bool> isDebridSyncEnabled() => _settings.isPlaytorrioCloudDebridSyncEnabled();

  Future<void> setDebridSyncEnabled(bool v) =>
      _settings.setPlaytorrioCloudDebridSyncEnabled(v);

  /// Merge remote `Continue watching` into local storage.
  Future<void> pullAndMergeProgress() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await isProgressSyncEnabled()) return;
    if (!await hasStoredSession()) return;
    await _ensureAccess();
    final token = await _accessToken;
    if (token == null) return;

    final res = await http.get(
      Uri.parse('$_base$_restWatch?select=entries'),
      headers: _headers(token),
    );
    if (res.statusCode == 401) {
      await signOut();
      return;
    }
    if (res.statusCode != 200) {
      debugPrint('[PT Cloud] pull history: ${res.statusCode} ${res.body}');
      return;
    }
    final decoded = json.decode(res.body);
    if (decoded is! List || decoded.isEmpty) return;
    final first = decoded.first;
    if (first is! Map) return;
    final entriesRaw = first['entries'];
    if (entriesRaw is! List) return;

    final wh = WatchHistoryService();
    final local = await wh.getHistory();
    final byUnique = {for (final m in local) m['uniqueId'] as String: m};

    for (final raw in entriesRaw) {
      if (raw is! Map) continue;
      final e = Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
      final uid = e['uniqueId']?.toString();
      if (uid == null || uid.isEmpty) continue;
      final newPos = e['position'] is int
          ? e['position'] as int
          : int.tryParse('${e['position'] ?? 0}') ?? 0;
      final old = byUnique[uid];
      if (old != null) {
        final oldPos = old['position'] is int
            ? old['position'] as int
            : (old['position'] as num?)?.toInt() ?? 0;
        if (newPos <= oldPos) continue;
      }
      byUnique[uid] = e;
    }

    var merged = byUnique.values.toList();
    merged.sort(
      (a, b) => (b['updatedAt'] as int? ?? 0).compareTo(a['updatedAt'] as int? ?? 0),
    );
    if (merged.length > 50) merged = merged.sublist(0, 50);
    await wh.replaceAll(merged);
  }

  /// Push a single local entry (full list upsert) after [WatchHistoryService.saveProgress].
  Future<void> pushProgressFromEntry(Map<String, dynamic> newEntry) async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await isProgressSyncEnabled()) return;
    if (!await hasStoredSession()) return;
    if (newEntry['tmdbId'] == null) return;

    await _ensureAccess();
    final token = await _accessToken;
    if (token == null) return;
    final uid = await _currentUserId();
    if (uid == null) {
      debugPrint('[PT Cloud] no user id in token');
      return;
    }

    final wh = WatchHistoryService();
    var list = await wh.getHistory();
    // Ensure latest entry is the one we just saved
    list.removeWhere((e) => e['uniqueId'] == newEntry['uniqueId']);
    list.insert(0, newEntry);
    if (list.length > 50) list = list.sublist(0, 50);

    final res = await http.post(
      Uri.parse('$_base$_restWatch'),
      headers: {
        ..._headers(token),
        'Prefer': 'return=minimal,resolution=merge-duplicates',
      },
      body: json.encode({
        'user_id': uid,
        'entries': list,
      }),
    );
    if (res.statusCode == 401) await signOut();
    if (res.statusCode == 409 || res.statusCode == 400) {
      final patch = await http.patch(
        Uri.parse('$_base$_restWatch?user_id=eq.$uid'),
        headers: {..._headers(token), 'Prefer': 'return=minimal'},
        body: json.encode({'entries': list}),
      );
      if (patch.statusCode == 401) await signOut();
      if (patch.statusCode < 200 || patch.statusCode >= 300) {
        debugPrint('[PT Cloud] push history patch: ${patch.statusCode} ${patch.body}');
      }
      return;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('[PT Cloud] push history: ${res.statusCode} ${res.body}');
    }
  }

  void scheduleProgressPush(Map<String, dynamic> entry) {
    if (kIsWeb) return;
    unawaited(() async {
      try {
        await pushProgressFromEntry(entry);
      } catch (e, st) {
        debugPrint('[PT Cloud] push: $e $st');
      }
    }());
  }

  /// Download remote JSON preferences and apply over local (non-destructive merge for known keys).
  Future<void> pullUserSettings() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await isSettingsSyncEnabled()) return;
    if (!await hasStoredSession()) return;
    await _ensureAccess();
    final token = await _accessToken;
    if (token == null) return;

    final res = await http.get(
      Uri.parse('$_base$_restSettings?select=prefs'),
      headers: _headers(token),
    );
    if (res.statusCode == 401) {
      await signOut();
      return;
    }
    if (res.statusCode != 200) {
      debugPrint('[PT Cloud] pull settings: ${res.statusCode}');
      return;
    }
    final decoded = json.decode(res.body);
    if (decoded is! List || decoded.isEmpty) return;
    final first = decoded.first;
    if (first is! Map) return;
    final p = first['prefs'];
    if (p is! Map) return;
    await _settings.applyCloudPreferenceMap(
      p.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  /// Upload current local whitelisted preferences.
  Future<void> pushUserSettings() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await isSettingsSyncEnabled()) return;
    if (!await hasStoredSession()) return;
    await _ensureAccess();
    final token = await _accessToken;
    if (token == null) return;
    final uid = await _currentUserId();
    if (uid == null) return;

    final map = await _exportPrefsMap();
    if (map.isEmpty) return;

    final res = await http.post(
      Uri.parse('$_base$_restSettings'),
      headers: {
        ..._headers(token),
        'Prefer': 'return=minimal,resolution=merge-duplicates',
      },
      body: json.encode({
        'user_id': uid,
        'prefs': map,
      }),
    );
    if (res.statusCode == 401) await signOut();
    if (res.statusCode == 409 || res.statusCode == 400) {
      final patch = await http.patch(
        Uri.parse('$_base$_restSettings?user_id=eq.$uid'),
        headers: {..._headers(token), 'Prefer': 'return=minimal'},
        body: json.encode({'prefs': map}),
      );
      if (patch.statusCode == 401) await signOut();
      if (patch.statusCode < 200 || patch.statusCode >= 300) {
        debugPrint('[PT Cloud] push settings patch: ${patch.statusCode} ${patch.body}');
      }
      return;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('[PT Cloud] push settings: ${res.statusCode} ${res.body}');
    }
  }

  void scheduleSettingsPush() {
    if (kIsWeb) return;
    unawaited(() async {
      try {
        await pushUserSettings();
      } catch (e) {
        debugPrint('[PT Cloud] settings push: $e');
      }
    }());
  }

  Future<void> pushDebridSecrets() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await isDebridSyncEnabled()) return;
    if (!await hasStoredSession()) return;
    await _ensureAccess();
    final token = await _accessToken;
    if (token == null) return;
    final uid = await _currentUserId();
    if (uid == null) return;

    final secrets = await DebridApi().exportDebridKeysForCloud();
    final res = await http.post(
      Uri.parse('$_base$_restDebrid'),
      headers: {
        ..._headers(token),
        'Prefer': 'return=minimal,resolution=merge-duplicates',
      },
      body: json.encode({
        'user_id': uid,
        'secrets': secrets,
      }),
    );
    if (res.statusCode == 401) await signOut();
    if (res.statusCode == 409 || res.statusCode == 400) {
      final patch = await http.patch(
        Uri.parse('$_base$_restDebrid?user_id=eq.$uid'),
        headers: {..._headers(token), 'Prefer': 'return=minimal'},
        body: json.encode({'secrets': secrets}),
      );
      if (patch.statusCode == 401) await signOut();
      if (patch.statusCode < 200 || patch.statusCode >= 300) {
        debugPrint('[PT Cloud] debrid patch: ${patch.statusCode} ${patch.body}');
      }
      return;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('[PT Cloud] debrid push: ${res.statusCode} ${res.body}');
    }
  }

  Future<void> pullDebridSecrets() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await isDebridSyncEnabled()) return;
    if (!await hasStoredSession()) return;
    await _ensureAccess();
    final token = await _accessToken;
    if (token == null) return;

    final res = await http.get(
      Uri.parse('$_base$_restDebrid?select=secrets'),
      headers: _headers(token),
    );
    if (res.statusCode == 401) {
      await signOut();
      return;
    }
    if (res.statusCode != 200) {
      debugPrint('[PT Cloud] debrid pull: ${res.statusCode}');
      return;
    }
    final decoded = json.decode(res.body);
    if (decoded is! List || decoded.isEmpty) return;
    final first = decoded.first;
    if (first is! Map) return;
    final s = first['secrets'];
    if (s is! Map) return;
    await DebridApi()
        .applyDebridKeysFromCloudMap(s.map((k, v) => MapEntry(k.toString(), v)));
  }

  Future<void> scheduleDebridPush() async {
    if (kIsWeb) return;
    try {
      await pushDebridSecrets();
    } catch (e) {
      debugPrint('[PT Cloud] debrid push: $e');
    }
  }

  Future<void> pullOnStartup() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await hasStoredSession()) return;
    try {
      if (await isProgressSyncEnabled()) {
        await pullAndMergeProgress();
      }
      if (await isSettingsSyncEnabled()) {
        await pullUserSettings();
      }
      if (await isDebridSyncEnabled()) {
        await pullDebridSecrets();
      }
    } catch (e) {
      debugPrint('[PT Cloud] startup: $e');
    }
  }

  Future<Map<String, dynamic>> _exportPrefsMap() => SettingsService().exportForCloudSync();
}

class PlaytorrioCloudException implements Exception {
  const PlaytorrioCloudException(this.message);
  final String message;
  @override
  String toString() => message;
}
