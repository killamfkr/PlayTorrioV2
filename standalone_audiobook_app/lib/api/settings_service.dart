import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audiobook_prefs_keys.dart';

String _audiobookEntryId(String raw) {
  try {
    final m = json.decode(raw) as Map<String, dynamic>;
    final b = m['book'];
    if (b is Map) return (b['audioBookId'] as String?) ?? '';
  } catch (_) {}
  return '';
}

int _audiobookHistoryTs(String raw) {
  try {
    return (json.decode(raw) as Map)['timestamp'] as int? ?? 0;
  } catch (_) {
    return 0;
  }
}

int _audiobookBookmarkTs(String raw) {
  try {
    final m = json.decode(raw) as Map;
    return (m['savedAt'] as num?)?.toInt() ??
        (m['timestamp'] as num?)?.toInt() ??
        0;
  } catch (_) {
    return 0;
  }
}

List<String> mergeAudiobookHistoryLists(List<String> local, List<String> remote) {
  final map = <String, String>{};
  void ingest(String x) {
    final id = _audiobookEntryId(x);
    if (id.isEmpty) return;
    final prev = map[id];
    if (prev == null || _audiobookHistoryTs(x) >= _audiobookHistoryTs(prev)) {
      map[id] = x;
    }
  }

  for (final x in remote) {
    ingest(x);
  }
  for (final x in local) {
    ingest(x);
  }
  final out = map.values.toList()
    ..sort((a, b) => _audiobookHistoryTs(b).compareTo(_audiobookHistoryTs(a)));
  if (out.length > 10) return out.sublist(0, 10);
  return out;
}

List<String> mergeAudiobookBookmarkLists(List<String> local, List<String> remote) {
  if (remote.isEmpty) return List<String>.from(local);

  final localById = <String, String>{};
  for (final x in local) {
    final id = _audiobookEntryId(x);
    if (id.isNotEmpty) localById[id] = x;
  }

  final out = <String>[];
  for (final x in remote) {
    final id = _audiobookEntryId(x);
    if (id.isEmpty) continue;
    final localRow = localById[id];
    if (localRow != null &&
        _audiobookBookmarkTs(localRow) > _audiobookBookmarkTs(x)) {
      out.add(localRow);
    } else {
      out.add(x);
    }
  }
  out.sort((a, b) => _audiobookBookmarkTs(b).compareTo(_audiobookBookmarkTs(a)));
  return out;
}

List<String> mergeAudiobookLikedLists(List<String> local, List<String> remote) {
  final map = <String, String>{};
  for (final x in remote) {
    final id = _audiobookEntryId(x);
    if (id.isNotEmpty) map[id] = x;
  }
  for (final x in local) {
    final id = _audiobookEntryId(x);
    if (id.isNotEmpty) map[id] = x;
  }
  return map.values.toList();
}

/// Minimal settings for the standalone Stories app.
class SettingsService {
  SettingsService();

  static final ValueNotifier<int> audiobookPrefsChangeNotifier =
      ValueNotifier<int>(0);

  static void notifyAudiobookPrefsChanged() {
    audiobookPrefsChangeNotifier.value++;
  }

  static const _torrentCacheTypeKey = 'torrent_cache_type';
  static const _torrentRamCacheMbKey = 'torrent_ram_cache_mb';
  static const _ptCloudSettingsSyncKey = 'pt_cloud_sync_settings';
  static const _userAvatarKey = 'stories_user_avatar';

  static final ValueNotifier<int> userAvatarChangeNotifier = ValueNotifier<int>(0);

  static void notifyUserAvatarChanged() {
    userAvatarChangeNotifier.value++;
  }

  /// Standalone app uses a single profile row in Supabase.
  Future<int> getPlaytorrioProfileId() async => 1;

  Future<bool> isPlaytorrioCloudSettingsSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ptCloudSettingsSyncKey) ?? true;
  }

  Future<void> setPlaytorrioCloudSettingsSyncEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ptCloudSettingsSyncKey, v);
  }

  Future<String> getTorrentCacheType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_torrentCacheTypeKey) ?? 'ram';
  }

  Future<void> setTorrentCacheType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_torrentCacheTypeKey, type);
  }

  Future<int> getTorrentRamCacheMb() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_torrentRamCacheMbKey) ?? 200;
  }

  Future<void> setTorrentRamCacheMb(int mb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_torrentRamCacheMbKey, mb);
  }

  Future<int> getUserAvatarIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userAvatarKey) ?? 0;
  }

  Future<void> setUserAvatarIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userAvatarKey, index);
    notifyUserAvatarChanged();
  }

  /// Audiobook prefs mirrored to Supabase when signed in.
  Future<Map<String, dynamic>> exportForCloudSync() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      AudiobookPrefsKeys.history:
          prefs.getStringList(AudiobookPrefsKeys.history) ?? [],
      AudiobookPrefsKeys.liked:
          prefs.getStringList(AudiobookPrefsKeys.liked) ?? [],
      AudiobookPrefsKeys.bookmarks:
          prefs.getStringList(AudiobookPrefsKeys.bookmarks) ?? [],
      _torrentCacheTypeKey: await getTorrentCacheType(),
      _torrentRamCacheMbKey: await getTorrentRamCacheMb(),
      _userAvatarKey: await getUserAvatarIndex(),
    };
  }

  Future<void> applyCloudPreferenceMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    for (final e in map.entries) {
      final k = e.key;
      final v = e.value;
      if (k == AudiobookPrefsKeys.history && v is List) {
        final local = prefs.getStringList(AudiobookPrefsKeys.history) ?? [];
        final remote = v.map((x) => x.toString()).toList();
        await prefs.setStringList(
          AudiobookPrefsKeys.history,
          mergeAudiobookHistoryLists(local, remote),
        );
        notifyAudiobookPrefsChanged();
        continue;
      }
      if (k == AudiobookPrefsKeys.liked && v is List) {
        final local = prefs.getStringList(AudiobookPrefsKeys.liked) ?? [];
        final remote = v.map((x) => x.toString()).toList();
        await prefs.setStringList(
          AudiobookPrefsKeys.liked,
          mergeAudiobookLikedLists(local, remote),
        );
        notifyAudiobookPrefsChanged();
        continue;
      }
      if (k == AudiobookPrefsKeys.bookmarks && v is List) {
        final local = prefs.getStringList(AudiobookPrefsKeys.bookmarks) ?? [];
        final remote = v.map((x) => x.toString()).toList();
        await prefs.setStringList(
          AudiobookPrefsKeys.bookmarks,
          mergeAudiobookBookmarkLists(local, remote),
        );
        notifyAudiobookPrefsChanged();
        continue;
      }
      if (k == _torrentCacheTypeKey && v is String) {
        await setTorrentCacheType(v);
        continue;
      }
      if (k == _torrentRamCacheMbKey) {
        final n = v is int ? v : int.tryParse(v.toString());
        if (n != null) await setTorrentRamCacheMb(n);
        continue;
      }
      if (k == _userAvatarKey) {
        final n = v is int ? v : int.tryParse(v.toString());
        if (n != null) await setUserAvatarIndex(n);
      }
    }
  }
}
