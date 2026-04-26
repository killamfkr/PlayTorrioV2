import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../api/settings_service.dart';
import 'watch_history_service.dart';

/// Syncs “Continue watching” with the same Nuvio account as [nuvioapp.space]
/// (Supabase: `dpyhjjcoabcglfmgecug`, public anon key as on the website).
class NuvioSyncService {
  NuvioSyncService._();
  static final NuvioSyncService instance = NuvioSyncService._();

  static const String kSupabaseUrl = 'https://dpyhjjcoabcglfmgecug.supabase.co';
  // Public anon JWT from the Nuvio web bundle (same as their browser client).
  static const String kAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRweWhqamNvYWJjZ2xmbWdlY3VnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3ODYyNDcsImV4cCI6MjA4NjM2MjI0N30.U-3QSNDdpsnvRk_7ZL419AFTOtggHJJcmkodxeXjbkg';

  static const _accessKey = 'nuvio_access_token';
  static const _refreshKey = 'nuvio_refresh_token';
  final _secure = const FlutterSecureStorage();
  final _settings = SettingsService();
  String? _access;
  String? _refresh;

  Future<String?> get _cachedAccess async {
    if (_access != null && _access!.isNotEmpty) return _access;
    _access = await _secure.read(key: _accessKey);
    return _access;
  }

  Future<String?> get _cachedRefresh async {
    if (_refresh != null && _refresh!.isNotEmpty) return _refresh;
    _refresh = await _secure.read(key: _refreshKey);
    return _refresh;
  }

  Future<void> _persistSession(String access, String? refresh) async {
    _access = access;
    await _secure.write(key: _accessKey, value: access);
    if (refresh != null && refresh.isNotEmpty) {
      _refresh = refresh;
      await _secure.write(key: _refreshKey, value: refresh);
    }
  }

  Future<void> signOut() async {
    final token = await _cachedAccess;
    if (token != null && token.isNotEmpty) {
      try {
        unawaited(http.post(
          Uri.parse('$kSupabaseUrl/auth/v1/logout'),
          headers: {
            'apikey': kAnonKey,
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

  Future<bool> hasStoredSession() async {
    return (await _cachedAccess)?.isNotEmpty == true ||
        (await _cachedRefresh)?.isNotEmpty == true;
  }

  Future<void> signInWithPassword(
      {required String email, required String password}) async {
    final res = await http.post(
      Uri.parse(
          '$kSupabaseUrl/auth/v1/token?grant_type=password'),
      headers: {
        'apikey': kAnonKey,
        'Content-Type': 'application/json',
      },
      body: json.encode({'email': email.trim(), 'password': password}),
    );
    if (res.statusCode != 200) {
      var msg = res.body;
      try {
        final m = json.decode(res.body) as Map<String, dynamic>?;
        msg = m?['error_description']?.toString() ??
            m?['msg']?.toString() ??
            res.body;
      } catch (_) {}
      throw NuvioAuthException(msg);
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    await _persistSession(
        data['access_token'] as String, data['refresh_token'] as String?);
  }

  Future<void> _ensureAccess() async {
    if ((await _cachedAccess)?.isNotEmpty == true) return;
    final rt = await _cachedRefresh;
    if (rt == null || rt.isEmpty) {
      throw const NuvioAuthException('Not signed in to Nuvio');
    }
    final res = await http.post(
      Uri.parse(
          '$kSupabaseUrl/auth/v1/token?grant_type=refresh_token'),
      headers: {
        'apikey': kAnonKey,
        'Content-Type': 'application/json',
      },
      body: json.encode({'refresh_token': rt}),
    );
    if (res.statusCode != 200) {
      await signOut();
      throw const NuvioAuthException('Session expired. Sign in again.');
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    await _persistSession(
        data['access_token'] as String, data['refresh_token'] as String?);
  }

  Future<int> getProfileId() => _settings.getNuvioProfileId();
  Future<void> setProfileId(int id) => _settings.setNuvioProfileId(id);
  Future<bool> isSyncEnabled() => _settings.isNuvioSyncEnabled();
  Future<void> setSyncEnabled(bool v) => _settings.setNuvioSyncEnabled(v);

  static String progressKeyFor({
    required int tmdbId,
    int? season,
    int? episode,
  }) {
    if (season != null && episode != null) {
      return 'pt_${tmdbId}_s${season}e$episode';
    }
    return 'pt_$tmdbId';
  }

  static String contentIdFor({
    required int tmdbId,
    int? season,
    int? episode,
  }) {
    if (season != null && episode != null) {
      return 'tmdb:$tmdbId:$season:$episode';
    }
    return 'tmdb:$tmdbId';
  }

  static String? _typeFromEntry(Map<String, dynamic> e) {
    final m = (e['mediaType'] ?? e['stremioType'])?.toString().toLowerCase();
    if (m == 'movie') return 'movie';
    if (m == 'tv' || m == 'series') return 'series';
    if (e['season'] != null && e['episode'] != null) return 'series';
    return 'movie';
  }

  static Map<String, dynamic> nuvioRowFromLocalEntry(Map<String, dynamic> e) {
    final tmdb = e['tmdbId'] is int
        ? e['tmdbId'] as int
        : int.tryParse('${e['tmdbId']}') ?? 0;
    if (tmdb <= 0) {
      throw ArgumentError('tmdbId required for Nuvio');
    }
    final season = e['season'] as int?;
    final episode = e['episode'] as int?;
    final pos = e['position'] is int
        ? e['position'] as int
        : int.tryParse('${e['position'] ?? 0}') ?? 0;
    final dur = e['duration'] is int
        ? e['duration'] as int
        : int.tryParse('${e['duration'] ?? 0}') ?? 0;
    final type = _typeFromEntry(e) ?? 'movie';
    return {
      'progress_key': progressKeyFor(
        tmdbId: tmdb,
        season: season,
        episode: episode,
      ),
      'content_id': contentIdFor(
        tmdbId: tmdb,
        season: season,
        episode: episode,
      ),
      'content_type': type,
      if (season != null) 'season': season,
      if (episode != null) 'episode': episode,
      'position': pos.toString(),
      'duration': dur.toString(),
    };
  }

  /// Merges remote Nuvio rows into local “Continue watching” (TMDB rows only).
  Future<void> pullAndMerge() async {
    if (!await isSyncEnabled()) return;
    if (!await hasStoredSession()) return;
    final profile = await getProfileId();
    await _ensureAccess();
    final token = await _cachedAccess;
    if (token == null) return;

    final res = await http.post(
      Uri.parse('$kSupabaseUrl/rest/v1/rpc/sync_pull_watch_progress'),
      headers: {
        'apikey': kAnonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'p_profile_id': profile}),
    );
    if (res.statusCode == 401) {
      await signOut();
      return;
    }
    if (res.statusCode != 200) {
      debugPrint('[NuvioSync] pull failed: ${res.statusCode} ${res.body}');
      return;
    }
    final decoded = json.decode(res.body);
    if (decoded is! List) return;

    final wh = WatchHistoryService();
    final local = await wh.getHistory();
    final byUnique = {for (final m in local) m['uniqueId'] as String: m};

    for (final raw in decoded) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)));
      final parsed = _fromNuvioRow(m);
      if (parsed == null) continue;
      final uid = parsed['uniqueId'] as String;
      final existing = byUnique[uid];
      final newPos = parsed['position'] as int;
      if (existing != null) {
        final oldPos = existing['position'] is int
            ? existing['position'] as int
            : (existing['position'] as num?)?.toInt() ?? 0;
        if (newPos <= oldPos) continue;
      }
      byUnique[uid] = {
        'uniqueId': uid,
        'tmdbId': parsed['tmdbId'],
        'imdbId': existing?['imdbId'] ?? parsed['imdbId'],
        'title': existing?['title'] ?? 'TMDB ${parsed['tmdbId']}',
        'posterPath': existing?['posterPath'] ?? '',
        'method': existing?['method'] ?? 'nuvio_sync',
        'sourceId': existing?['sourceId'] ?? 'nuvio',
        'position': newPos,
        'duration': parsed['duration'] as int,
        'season': parsed['season'],
        'episode': parsed['episode'],
        'episodeTitle': existing?['episodeTitle'],
        'magnetLink': existing?['magnetLink'],
        'fileIndex': existing?['fileIndex'],
        'streamUrl': existing?['streamUrl'],
        'stremioId': existing?['stremioId'],
        'stremioAddonBaseUrl': existing?['stremioAddonBaseUrl'],
        'stremioType': existing?['stremioType'],
        'mediaType': parsed['mediaType'],
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
    }

    var merged = byUnique.values.toList();
    merged.sort(
      (a, b) => (b['updatedAt'] as int? ?? 0)
          .compareTo(a['updatedAt'] as int? ?? 0),
    );
    if (merged.length > 50) merged = merged.sublist(0, 50);
    await wh.replaceAll(merged);
  }

  static Map<String, dynamic>? _fromNuvioRow(Map<String, dynamic> m) {
    int? tmdb;
    int? s;
    int? ep;
    final cid = m['content_id']?.toString() ?? '';
    if (cid.startsWith('tmdb:')) {
      final parts = cid.split(':');
      if (parts.length >= 2) tmdb = int.tryParse(parts[1]);
      if (parts.length >= 4) {
        s = int.tryParse(parts[2]);
        ep = int.tryParse(parts[3]);
      }
    }
    if (tmdb == null || tmdb <= 0) return null;
    final pos = int.tryParse('${m['position'] ?? 0}') ?? 0;
    final dur = int.tryParse('${m['duration'] ?? 0}') ?? 0;
    final type = m['content_type']?.toString() ?? 'movie';
    String unique;
    if (s != null && ep != null) {
      unique = '${tmdb}_S${s}_E$ep';
    } else {
      unique = '$tmdb';
    }
    return {
      'uniqueId': unique,
      'tmdbId': tmdb,
      'position': pos,
      'duration': dur,
      'season': s,
      'episode': ep,
      'mediaType': type == 'series' || type == 'tv' ? 'tv' : 'movie',
      'imdbId': null,
    };
  }

  /// Push a single local entry; mirrors Nuvio web: pull list → merge one row → push.
  Future<void> pushEntryFromLocalMap(Map<String, dynamic> e) async {
    if (!await isSyncEnabled()) return;
    if (!await hasStoredSession()) return;
    if (e['tmdbId'] == null) return;
    final profile = await getProfileId();
    late final Map<String, dynamic> row;
    try {
      row = nuvioRowFromLocalEntry(e);
    } catch (_) {
      return;
    }

    await _ensureAccess();
    final token = await _cachedAccess;
    if (token == null) return;

    final pull = await http.post(
      Uri.parse('$kSupabaseUrl/rest/v1/rpc/sync_pull_watch_progress'),
      headers: {
        'apikey': kAnonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'p_profile_id': profile}),
    );
    if (pull.statusCode == 401) {
      await signOut();
      return;
    }
    if (pull.statusCode != 200) {
      debugPrint('[NuvioSync] push: pull failed ${pull.body}');
      return;
    }
    var list = <dynamic>[];
    final pj = json.decode(pull.body);
    if (pj is List) list = pj;

    var idx = list.indexWhere(
      (h) => h is Map && '${h['progress_key']}' == row['progress_key'],
    );
    if (idx >= 0) {
      final old = Map<String, dynamic>.from(
        (list[idx] as Map).map((k, v) => MapEntry(k.toString(), v)));
      list = List<dynamic>.from(list);
      list[idx] = {...old, ...row};
    } else {
      list = [...list, row];
    }

    final push = await http.post(
      Uri.parse('$kSupabaseUrl/rest/v1/rpc/sync_push_watch_progress'),
      headers: {
        'apikey': kAnonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'p_profile_id': profile,
        'p_entries': list,
      }),
    );
    if (push.statusCode < 200 || push.statusCode >= 300) {
      debugPrint('[NuvioSync] push failed: ${push.statusCode} ${push.body}');
    }
  }

  void schedulePush(Map<String, dynamic> entry) {
    if (kIsWeb) return;
    unawaited(() async {
      try {
        await pushEntryFromLocalMap(entry);
      } catch (e, st) {
        debugPrint('[NuvioSync] push failed: $e $st');
      }
    }());
  }

  Future<void> pullOnStartup() async {
    if (kIsWeb) return;
    if (!await isSyncEnabled()) return;
    if (!await hasStoredSession()) return;
    try {
      await pullAndMerge();
    } catch (e) {
      debugPrint('[NuvioSync] startup pull: $e');
    }
  }
}

class NuvioAuthException implements Exception {
  const NuvioAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
