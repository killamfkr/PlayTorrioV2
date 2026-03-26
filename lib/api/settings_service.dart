import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  /// Fires whenever Stremio addons are added or removed.
  /// Listeners can compare the value to detect changes.
  static final ValueNotifier<int> addonChangeNotifier = ValueNotifier<int>(0);

  static const String _streamingModeKey = 'streaming_mode';
  static const String _sortPreferenceKey = 'sort_preference';
  static const String _useDebridKey = 'use_debrid_for_streams';
  static const String _debridServiceKey = 'debrid_service';
  static const String _stremioAddonsKey = 'stremio_addons';
  
  // External player setting
  static const String _externalPlayerKey = 'external_player';

  // Jackett settings
  static const String _jackettBaseUrlKey = 'jackett_base_url';
  static const String _jackettApiKeyKey = 'jackett_api_key';
  
  // Prowlarr settings
  static const String _prowlarrBaseUrlKey = 'prowlarr_base_url';
  static const String _prowlarrApiKeyKey = 'prowlarr_api_key';

  // Torrent cache settings
  static const String _torrentCacheTypeKey = 'torrent_cache_type';
  static const String _torrentRamCacheMbKey = 'torrent_ram_cache_mb';

  Future<List<Map<String, dynamic>>> getStremioAddons() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList(_stremioAddonsKey) ?? [];
    return list.map((s) => json.decode(s) as Map<String, dynamic>).toList();
  }

  Future<void> saveStremioAddon(Map<String, dynamic> addon) async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> current = await getStremioAddons();
    // Prevent duplicates by manifest URL
    current.removeWhere((a) => a['baseUrl'] == addon['baseUrl']);
    current.add(addon);
    await prefs.setStringList(_stremioAddonsKey, current.map((e) => json.encode(e)).toList().cast<String>());
    addonChangeNotifier.value++;
  }

  Future<void> removeStremioAddon(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> current = await getStremioAddons();
    current.removeWhere((a) => a['baseUrl'] == baseUrl);
    await prefs.setStringList(_stremioAddonsKey, current.map((e) => json.encode(e)).toList().cast<String>());
    addonChangeNotifier.value++;
  }

  Future<bool> isStreamingModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_streamingModeKey) ?? false;
  }

  Future<void> setStreamingMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_streamingModeKey, enabled);
  }

  Future<String> getSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sortPreferenceKey) ?? 'Seeders (High to Low)';
  }

  Future<void> setSortPreference(String preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPreferenceKey, preference);
  }

  Future<bool> useDebridForStreams() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useDebridKey) ?? false;
  }

  Future<void> setUseDebridForStreams(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useDebridKey, enabled);
  }

  Future<String> getDebridService() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_debridServiceKey) ?? 'None';
  }

  Future<void> setDebridService(String service) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_debridServiceKey, service);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // External Player
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> getExternalPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_externalPlayerKey) ?? 'Built-in Player';
  }

  Future<void> setExternalPlayer(String player) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_externalPlayerKey, player);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Jackett Settings
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> getJackettBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_jackettBaseUrlKey);
  }

  Future<void> setJackettBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = url.trimRight().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_jackettBaseUrlKey, normalized);
  }

  Future<String?> getJackettApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_jackettApiKeyKey);
  }

  Future<void> setJackettApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_jackettApiKeyKey, apiKey);
  }

  Future<bool> isJackettConfigured() async {
    final baseUrl = await getJackettBaseUrl();
    final apiKey = await getJackettApiKey();
    return baseUrl != null && baseUrl.isNotEmpty && 
           apiKey != null && apiKey.isNotEmpty;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Prowlarr Settings
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> getProwlarrBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prowlarrBaseUrlKey);
  }

  Future<void> setProwlarrBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = url.trimRight().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_prowlarrBaseUrlKey, normalized);
  }

  Future<String?> getProwlarrApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prowlarrApiKeyKey);
  }

  Future<void> setProwlarrApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prowlarrApiKeyKey, apiKey);
  }

  Future<bool> isProwlarrConfigured() async {
    final baseUrl = await getProwlarrBaseUrl();
    final apiKey = await getProwlarrApiKey();
    return baseUrl != null && baseUrl.isNotEmpty && 
           apiKey != null && apiKey.isNotEmpty;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Torrent Cache Settings
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns 'ram' or 'disk'. Defaults to 'ram'.
  Future<String> getTorrentCacheType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_torrentCacheTypeKey) ?? 'ram';
  }

  Future<void> setTorrentCacheType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_torrentCacheTypeKey, type);
  }

  /// RAM cache size in MB. Defaults to 200.
  Future<int> getTorrentRamCacheMb() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_torrentRamCacheMbKey) ?? 200;
  }

  Future<void> setTorrentRamCacheMb(int mb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_torrentRamCacheMbKey, mb);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Navbar Configuration
  // ═══════════════════════════════════════════════════════════════════════════

  static const String _navbarConfigKey = 'navbar_config';

  /// Notifier that fires when navbar config changes so MainScreen rebuilds.
  static final ValueNotifier<int> navbarChangeNotifier = ValueNotifier<int>(0);

  /// All available nav items in default order. 'settings' is always last and locked.
  static const List<String> allNavIds = [
    'home', 'discover', 'search', 'mylist', 'magnet', 'live_matches',
    'iptv', 'audiobooks', 'books', 'music', 'comics', 'manga',
    'jellyfin', 'anime', 'arabic',
  ];

  /// Returns the ordered list of visible nav item IDs.
  /// Settings is NOT stored — it's always appended by the consumer.
  Future<List<String>> getNavbarConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_navbarConfigKey);
    if (raw == null) return List.from(allNavIds); // default: all visible
    // Filter out any stale IDs that no longer exist
    return raw.where((id) => allNavIds.contains(id)).toList();
  }

  /// Save the ordered list of visible nav item IDs (excluding 'settings').
  Future<void> setNavbarConfig(List<String> visibleIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_navbarConfigKey, visibleIds);
    navbarChangeNotifier.value++;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Export / Import All Settings
  // ═══════════════════════════════════════════════════════════════════════════

  static const List<String> _secureKeys = [
    'rd_access_token',
    'rd_refresh_token',
    'rd_token_expiry',
    'rd_client_id',
    'rd_client_secret',
    'torbox_api_key',
    'trakt_access_token',
    'trakt_refresh_token',
    'trakt_expires_at',
  ];

  /// Collects every setting (SharedPreferences + FlutterSecureStorage) into a
  /// single JSON-encodable map.
  Future<Map<String, dynamic>> exportAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final secure = const FlutterSecureStorage();

    final Map<String, dynamic> data = {};

    // --- SharedPreferences ---
    final prefsMap = <String, dynamic>{};
    // Bool keys
    for (final key in [_streamingModeKey, _useDebridKey]) {
      final v = prefs.getBool(key);
      if (v != null) prefsMap[key] = v;
    }
    // String keys
    for (final key in [
      _sortPreferenceKey,
      _debridServiceKey,
      _externalPlayerKey,
      _jackettBaseUrlKey,
      _jackettApiKeyKey,
      _prowlarrBaseUrlKey,
      _prowlarrApiKeyKey,
      _torrentCacheTypeKey,
    ]) {
      final v = prefs.getString(key);
      if (v != null) prefsMap[key] = v;
    }
    // Int keys
    for (final key in [_torrentRamCacheMbKey]) {
      final v = prefs.getInt(key);
      if (v != null) prefsMap[key] = v;
    }
    // StringList keys
    for (final key in [_stremioAddonsKey, _navbarConfigKey]) {
      final v = prefs.getStringList(key);
      if (v != null) prefsMap[key] = v;
    }
    data['shared_preferences'] = prefsMap;

    // --- FlutterSecureStorage ---
    final secureMap = <String, String>{};
    for (final key in _secureKeys) {
      final v = await secure.read(key: key);
      if (v != null) secureMap[key] = v;
    }
    data['secure_storage'] = secureMap;

    data['export_version'] = 1;
    data['exported_at'] = DateTime.now().toIso8601String();

    return data;
  }

  /// Restores every setting from a previously-exported JSON map.
  Future<void> importAllSettings(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final secure = const FlutterSecureStorage();

    // --- SharedPreferences ---
    final prefsMap = data['shared_preferences'] as Map<String, dynamic>? ?? {};

    // Bool keys
    for (final key in [_streamingModeKey, _useDebridKey]) {
      if (prefsMap.containsKey(key)) {
        await prefs.setBool(key, prefsMap[key] as bool);
      }
    }
    // String keys
    for (final key in [
      _sortPreferenceKey,
      _debridServiceKey,
      _externalPlayerKey,
      _jackettBaseUrlKey,
      _jackettApiKeyKey,
      _prowlarrBaseUrlKey,
      _prowlarrApiKeyKey,
      _torrentCacheTypeKey,
    ]) {
      if (prefsMap.containsKey(key)) {
        await prefs.setString(key, prefsMap[key] as String);
      }
    }
    // Int keys
    for (final key in [_torrentRamCacheMbKey]) {
      if (prefsMap.containsKey(key)) {
        await prefs.setInt(key, prefsMap[key] as int);
      }
    }
    // StringList keys
    for (final key in [_stremioAddonsKey, _navbarConfigKey]) {
      if (prefsMap.containsKey(key)) {
        await prefs.setStringList(
            key, (prefsMap[key] as List).cast<String>());
      }
    }

    // --- FlutterSecureStorage ---
    final secureMap = data['secure_storage'] as Map<String, dynamic>? ?? {};
    for (final key in _secureKeys) {
      if (secureMap.containsKey(key)) {
        await secure.write(key: key, value: secureMap[key] as String);
      }
    }

    // Notify listeners so UI refreshes
    addonChangeNotifier.value++;
    navbarChangeNotifier.value++;
  }
}
