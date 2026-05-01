import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single JSON-serializable blob for Supabase `user_settings.prefs` — all PT IPTV
/// SharedPreferences keys (`pt_iptv_*`): portals, favorites, scraper hits, alive cache.
abstract final class IptvCloudBundle {
  static const prefsKey = 'iptv_pt_cloud_bundle_v1';

  /// Same keys as [IptvStore] — public for merge logic.
  static const verifiedPortalsPrefsKey = 'pt_iptv_verified_portals';
  static const favoritePortalKeysPrefsKey = 'pt_iptv_favorite_portal_keys';

  /// Bump after cloud merge writes IPTV prefs so open [IptvController] can reload.
  static final ValueNotifier<int> epoch = ValueNotifier(0);

  static void bumpEpoch() => epoch.value++;

  static const Set<String> _stringMergePreferLocalKeys = {
    verifiedPortalsPrefsKey,
  };

  /// Merge local + remote IPTV bundles on **pull** so devices union portals and
  /// starred-portal keys instead of last-write-wins dropping favorites.
  static Map<String, dynamic> mergeForPull(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final keys = {...local.keys, ...remote.keys};
    final out = <String, dynamic>{};
    for (final k in keys) {
      final lw = local[k];
      final rw = remote[k];
      if (lw == null && rw != null) {
        out[k] = rw is Map ? Map<String, dynamic>.from(rw as Map) : rw;
        continue;
      }
      if (rw == null && lw != null) {
        out[k] = lw is Map ? Map<String, dynamic>.from(lw as Map) : lw;
        continue;
      }
      if (lw == null || rw == null) continue;
      if (lw is! Map || rw is! Map) {
        out[k] = lw;
        continue;
      }
      out[k] = _mergeWrappedEntry(k, Map<String, dynamic>.from(lw), Map<String, dynamic>.from(rw));
    }
    return out;
  }

  static Map<String, dynamic> _mergeWrappedEntry(
    String key,
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final lt = local['t']?.toString();
    final rt = remote['t']?.toString();
    if (lt != rt || lt == null) {
      return local;
    }
    switch (lt) {
      case 'l':
        final la = (local['v'] as List?)?.map((x) => x.toString()).toList() ?? [];
        final ra = (remote['v'] as List?)?.map((x) => x.toString()).toList() ?? [];
        return {'t': 'l', 'v': _unionPreserveOrder(la, ra)};
      case 'b':
        final lb = local['v'] == true;
        final rb = remote['v'] == true;
        return {'t': 'b', 'v': lb || rb};
      case 's':
        final ls = local['v']?.toString() ?? '';
        final rs = remote['v']?.toString() ?? '';
        if (key == verifiedPortalsPrefsKey) {
          return {'t': 's', 'v': _mergeVerifiedPortalsJson(ls, rs)};
        }
        if (key.startsWith('pt_iptv_alive_')) {
          return {'t': 's', 'v': _mergeAliveSnapshotJson(ls, rs)};
        }
        if (key.startsWith('pt_iptv_ch_') && !key.startsWith('pt_iptv_chfav_')) {
          return {'t': 's', 'v': _mergeChannelHitsJson(ls, rs)};
        }
        if (ls.isNotEmpty && rs.isNotEmpty) {
          if (_stringMergePreferLocalKeys.contains(key)) return {'t': 's', 'v': ls};
          return {'t': 's', 'v': ls.length >= rs.length ? ls : rs};
        }
        return {'t': 's', 'v': ls.isNotEmpty ? ls : rs};
      default:
        return local;
    }
  }

  static List<String> _unionPreserveOrder(List<String> a, List<String> b) {
    final seen = <String>{};
    final out = <String>[];
    for (final x in [...a, ...b]) {
      if (seen.add(x)) out.add(x);
    }
    return out;
  }

  static String _portalIdentity(Map<String, dynamic> o) {
    final url = (o['url'] ?? '').toString().toLowerCase().trim();
    final u = (o['username'] ?? '').toString().toLowerCase().trim();
    final p = (o['password'] ?? '').toString().toLowerCase().trim();
    return '$url|$u|$p';
  }

  static String _mergeVerifiedPortalsJson(String localRaw, String remoteRaw) {
    List<Map<String, dynamic>> decode(String raw) {
      if (raw.isEmpty) return [];
      try {
        final arr = json.decode(raw) as List;
        final out = <Map<String, dynamic>>[];
        for (final e in arr) {
          if (e is Map) {
            out.add(Map<String, dynamic>.from(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ));
          }
        }
        return out;
      } catch (_) {
        return [];
      }
    }

    final byId = <String, Map<String, dynamic>>{};
    void putAll(List<Map<String, dynamic>> rows) {
      for (final o in rows) {
        final id = _portalIdentity(o);
        if (id.replaceAll('|', '').isEmpty) continue;
        final cur = byId[id];
        if (cur == null) {
          byId[id] = Map<String, dynamic>.from(o);
        } else {
          for (final e in o.entries) {
            final v = e.value;
            if (v == null) continue;
            if (v is String && v.isEmpty) continue;
            cur[e.key] = v;
          }
        }
      }
    }

    putAll(decode(localRaw));
    putAll(decode(remoteRaw));
    return json.encode(byId.values.toList());
  }

  static String _mergeAliveSnapshotJson(String localRaw, String remoteRaw) {
    Map<String, dynamic>? decode(String raw) {
      if (raw.isEmpty) return null;
      try {
        final o = json.decode(raw);
        if (o is Map) {
            return Map<String, dynamic>.from(
              o.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
      } catch (_) {}
      return null;
    }

    final a = decode(localRaw);
    final b = decode(remoteRaw);
    if (a == null && b == null) return '';
    if (a == null) return remoteRaw;
    if (b == null) return localRaw;
    final ids = <String>{};
    for (final src in [a, b]) {
      final list = src['ids'];
      if (list is List) {
        for (final x in list) {
          ids.add(x.toString());
        }
      }
    }
    final atA = (a['at'] as num?)?.toInt() ?? 0;
    final atB = (b['at'] as num?)?.toInt() ?? 0;
    return json.encode({
      'at': atA > atB ? atA : atB,
      'ids': ids.toList(),
    });
  }

  static String _mergeChannelHitsJson(String localRaw, String remoteRaw) {
    List<Map<String, dynamic>> decode(String raw) {
      if (raw.isEmpty) return [];
      try {
        final arr = json.decode(raw) as List;
        final out = <Map<String, dynamic>>[];
        for (final e in arr) {
          if (e is Map) {
            out.add(Map<String, dynamic>.from(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ));
          }
        }
        return out;
      } catch (_) {
        return [];
      }
    }

    final byUrl = <String, Map<String, dynamic>>{};
    void putAll(List<Map<String, dynamic>> rows) {
      for (final o in rows) {
        final url = (o['url'] ?? '').toString();
        if (url.isEmpty) continue;
        final cur = byUrl[url];
        if (cur == null) {
          byUrl[url] = Map<String, dynamic>.from(o);
        } else {
          for (final e in o.entries) {
            final v = e.value;
            if (v == null) continue;
            if (v is String && v.isEmpty) continue;
            cur[e.key] = v;
          }
        }
      }
    }

    putAll(decode(localRaw));
    putAll(decode(remoteRaw));
    return json.encode(byUrl.values.toList());
  }

  /// Collect every `pt_iptv_*` preference (strings, string lists, bools).
  static Future<Map<String, dynamic>> exportAll() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final k in prefs.getKeys()) {
      if (!k.startsWith('pt_iptv')) continue;
      final s = prefs.getString(k);
      if (s != null) {
        out[k] = {'t': 's', 'v': s};
        continue;
      }
      final l = prefs.getStringList(k);
      if (l != null) {
        out[k] = {'t': 'l', 'v': l};
        continue;
      }
      final b = prefs.getBool(k);
      if (b != null) {
        out[k] = {'t': 'b', 'v': b};
      }
    }
    return out;
  }

  static Future<void> applyAll(Map<String, dynamic> bundle) async {
    if (bundle.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final e in bundle.entries) {
      final k = e.key;
      if (!k.startsWith('pt_iptv')) continue;
      final wrapped = e.value;
      if (wrapped is! Map) continue;
      final t = wrapped['t']?.toString();
      final v = wrapped['v'];
      if (t == 's' && v != null) {
        await prefs.setString(k, v.toString());
      } else if (t == 'l' && v is List) {
        await prefs.setStringList(
          k,
          v.map((x) => x.toString()).toList(),
        );
      } else if (t == 'b' && v is bool) {
        await prefs.setBool(k, v);
      }
    }
    bumpEpoch();
  }
}
