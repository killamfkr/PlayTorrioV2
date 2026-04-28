import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single JSON-serializable blob for Supabase `user_settings.prefs` — all PT IPTV
/// SharedPreferences keys (`pt_iptv_*`): portals, favorites, scraper hits, alive cache.
abstract final class IptvCloudBundle {
  static const prefsKey = 'iptv_pt_cloud_bundle_v1';

  /// Bump after cloud merge writes IPTV prefs so open [IptvController] can reload.
  static final ValueNotifier<int> epoch = ValueNotifier(0);

  static void bumpEpoch() => epoch.value++;

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
