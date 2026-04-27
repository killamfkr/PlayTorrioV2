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
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx4YXBhenpsZHV3d2VjYXRlYnRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyOTI2NDQsImV4cCI6MjA5Mjg2ODY0NH0.a9e7zUEdWDmf4Qor-rbYZ6G0sMTEYcfKnwTrXjVrBWY',
);

class PlaytorrioCloudSyncService {
  PlaytorrioCloudSyncService._();
  static final PlaytorrioCloudSyncService instance = PlaytorrioCloudSyncService._();

  static const _accessKey = 'pt_supabase_access_token';
  static const _refreshKey = 'pt_supabase_refresh_token';

  static const _restWatch = '/rest/v1/user_watch_history';
  static const _restSettings = '/rest/v1/user_settings';
  static const _restDebrid = '/rest/v1/user_debrid_secrets';
  static const _restProfileMeta = '/rest/v1/user_profile_meta';

  Future<int> _activeProfileId() => _settings.getPlaytorrioProfileId();

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

  /// PostgREST/Auth need the **anon (legacy) JWT** from Project Settings → API, not
  /// the newer `sb_publishable_` key. If this is false, every REST call returns 401/404.
  bool get isAnonKeyJwtFormat {
    final k = _anon;
    if (k == null || k.isEmpty) return false;
    return k.split('.').length == 3 && k.startsWith('eyJ');
  }

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

  /// Full backup for the active [profile_id]: history + settings + debrid + profile meta.
  Future<void> pushFullProfileBackup() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await hasStoredSession()) return;
    if (!isAnonKeyJwtFormat) {
      debugPrint(
        '[PT Cloud] pushFullProfileBackup skipped: apikey must be legacy anon JWT (eyJ…), '
        'not sb_publishable — PostgREST will reject writes.',
      );
      return;
    }
    try {
      await _ensureAccess();
      final wh = WatchHistoryService();
      await _pushProgressList(await wh.getHistory());
      if (await isSettingsSyncEnabled()) await pushUserSettings();
      if (await isDebridSyncEnabled()) await pushDebridSecrets();
      await pushProfileMetaRow();
    } catch (e) {
      debugPrint('[PT Cloud] full profile backup: $e');
    }
  }

  Future<void> _pushProgressList(List<Map<String, dynamic>> list) async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await hasStoredSession()) return;
    await _ensureAccess();
    final token = await _accessToken;
    if (token == null) return;
    final uid = await _currentUserId();
    if (uid == null) return;
    final pid = await _activeProfileId();
    var bounded = list;
    if (bounded.length > 50) bounded = bounded.sublist(0, 50);

    final res = await http.post(
      Uri.parse('$_base$_restWatch'),
      headers: {
        ..._headers(token),
        'Prefer': 'return=minimal,resolution=merge-duplicates',
      },
      body: json.encode({
        'user_id': uid,
        'profile_id': pid,
        'entries': bounded,
      }),
    );
    if (res.statusCode == 401) await signOut();
    if (res.statusCode == 409 || res.statusCode == 400) {
      final patch = await http.patch(
        Uri.parse('$_base$_restWatch?user_id=eq.$uid&profile_id=eq.$pid'),
        headers: {..._headers(token), 'Prefer': 'return=minimal'},
        body: json.encode({'entries': bounded}),
      );
      if (patch.statusCode == 401) await signOut();
    }
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
    final userId = await _currentUserId();
    if (userId == null) return;

    final pid = await _activeProfileId();
    final res = await http.get(
      Uri.parse(
        '$_base$_restWatch?select=entries&user_id=eq.$userId&profile_id=eq.$pid',
      ),
      headers: _headers(token),
    );
    if (res.statusCode == 401) {
      await signOut();
      return;
    }
    if (res.statusCode != 200) {
      debugPrint(
        '[PT Cloud] pull history FAILED: ${res.statusCode} body=${res.body} '
        'anonKeyJwt=${isAnonKeyJwtFormat} — use legacy anon JWT in Project → API, '
        'or run supabase/migrations for profile_id + tables.',
      );
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
      final entryUid = e['uniqueId']?.toString();
      if (entryUid == null || entryUid.isEmpty) continue;
      final newPos = e['position'] is int
          ? e['position'] as int
          : int.tryParse('${e['position'] ?? 0}') ?? 0;
      final old = byUnique[entryUid];
      if (old != null) {
        final oldPos = old['position'] is int
            ? old['position'] as int
            : (old['position'] as num?)?.toInt() ?? 0;
        if (newPos <= oldPos) continue;
      }
      byUnique[entryUid] = e;
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
    final pid = await _activeProfileId();

    final res = await http.post(
      Uri.parse('$_base$_restWatch'),
      headers: {
        ..._headers(token),
        'Prefer': 'return=minimal,resolution=merge-duplicates',
      },
      body: json.encode({
        'user_id': uid,
        'profile_id': pid,
        'entries': list,
      }),
    );
    if (res.statusCode == 401) await signOut();
    if (res.statusCode == 409 || res.statusCode == 400) {
      final patch = await http.patch(
        Uri.parse('$_base$_restWatch?user_id=eq.$uid&profile_id=eq.$pid'),
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
      debugPrint(
        '[PT Cloud] push history FAILED: ${res.statusCode} ${res.body} '
        'anonKeyJwt=${isAnonKeyJwtFormat}',
      );
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

    final userId = await _currentUserId();
    if (userId == null) return;
    final pid = await _activeProfileId();
    final res = await http.get(
      Uri.parse(
        '$_base$_restSettings?select=prefs&user_id=eq.$userId&profile_id=eq.$pid',
      ),
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
    final pid = await _activeProfileId();

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
        'profile_id': pid,
        'prefs': map,
      }),
    );
    if (res.statusCode == 401) await signOut();
    if (res.statusCode == 409 || res.statusCode == 400) {
      final patch = await http.patch(
        Uri.parse('$_base$_restSettings?user_id=eq.$uid&profile_id=eq.$pid'),
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
    final pid = await _activeProfileId();

    final secrets = await DebridApi().exportDebridKeysForCloud();
    final res = await http.post(
      Uri.parse('$_base$_restDebrid'),
      headers: {
        ..._headers(token),
        'Prefer': 'return=minimal,resolution=merge-duplicates',
      },
      body: json.encode({
        'user_id': uid,
        'profile_id': pid,
        'secrets': secrets,
      }),
    );
    if (res.statusCode == 401) await signOut();
    if (res.statusCode == 409 || res.statusCode == 400) {
      final patch = await http.patch(
        Uri.parse('$_base$_restDebrid?user_id=eq.$uid&profile_id=eq.$pid'),
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

    final userId = await _currentUserId();
    if (userId == null) return;
    final pid = await _activeProfileId();
    final res = await http.get(
      Uri.parse(
        '$_base$_restDebrid?select=secrets&user_id=eq.$userId&profile_id=eq.$pid',
      ),
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
    if (!isAnonKeyJwtFormat) {
      debugPrint(
        '[PT Cloud] pullOnStartup skipped: set legacy anon JWT for apikey (see isAnonKeyJwtFormat).',
      );
      return;
    }
    try {
      await pullProfileMeta();
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

  /// Display names + avatar (0–7) for the profile picker, synced per account.
  Future<void> pushProfileMetaRow() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await hasStoredSession()) return;
    await _ensureAccess();
    final token = await _accessToken;
    if (token == null) return;
    final userId = await _currentUserId();
    if (userId == null) return;
    final pid = await _activeProfileId();
    final local = await _settings.getLocalProfileDisplayMeta();
    final row = local['$pid'] ?? {};
    final name = row['name'] as String?;
    final avatar = (row['avatar'] is int) ? row['avatar'] as int : 0;
    final body = {
      'user_id': userId,
      'profile_id': pid,
      'name': name,
      'avatar_key': avatar.clamp(0, 7),
    };
    final res = await http.post(
      Uri.parse('$_base$_restProfileMeta'),
      headers: {
        ..._headers(token),
        'Prefer': 'return=minimal,resolution=merge-duplicates',
      },
      body: json.encode(body),
    );
    if (res.statusCode == 401) await signOut();
    if (res.statusCode == 409 || res.statusCode == 400) {
      await http.patch(
        Uri.parse('$_base$_restProfileMeta?user_id=eq.$userId&profile_id=eq.$pid'),
        headers: {..._headers(token), 'Prefer': 'return=minimal'},
        body: json.encode({
          'name': name,
          'avatar_key': avatar.clamp(0, 7),
        }),
      );
    }
  }

  Future<void> pullProfileMeta() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await hasStoredSession()) return;
    await _ensureAccess();
    final token = await _accessToken;
    if (token == null) return;
    final userId = await _currentUserId();
    if (userId == null) return;
    final res = await http.get(
      Uri.parse('$_base$_restProfileMeta?user_id=eq.$userId'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) return;
    final list = json.decode(res.body);
    if (list is! List) return;
    for (final raw in list) {
      if (raw is! Map) continue;
      final p = (raw['profile_id'] is int)
          ? raw['profile_id'] as int
          : int.tryParse('${raw['profile_id']}') ?? 0;
      if (p < 1 || p > 4) continue;
      await _settings.setLocalProfileDisplayMeta(
        p,
        name: raw['name']?.toString(),
        avatarKey: (raw['avatar_key'] is int)
            ? raw['avatar_key'] as int
            : int.tryParse('${raw['avatar_key'] ?? 0}'),
      );
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
