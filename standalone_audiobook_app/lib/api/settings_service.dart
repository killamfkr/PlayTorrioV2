import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Minimal settings for the standalone audiobook app.
class SettingsService {
  SettingsService();

  static final ValueNotifier<int> audiobookPrefsChangeNotifier =
      ValueNotifier<int>(0);

  static void notifyAudiobookPrefsChanged() {
    audiobookPrefsChangeNotifier.value++;
  }

  static const _torrentCacheTypeKey = 'torrent_cache_type';
  static const _torrentRamCacheMbKey = 'torrent_ram_cache_mb';

  Future<String> getTorrentCacheType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_torrentCacheTypeKey) ?? 'ram';
  }

  Future<int> getTorrentRamCacheMb() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_torrentRamCacheMbKey) ?? 200;
  }
}
