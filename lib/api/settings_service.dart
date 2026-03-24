import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  /// Built-in (media_kit) player: keep playing when app is in background.
  static const String _builtinPlayerBackgroundPlayKey =
      'builtin_player_background_play';

  /// Built-in player: show Picture-in-Picture control (Android).
  static const String _builtinPlayerPictureInPictureKey =
      'builtin_player_picture_in_picture';

  static const String _stremioPreferredStreamAddonKey =
      'stremio_preferred_stream_addon_base_url';

  static const String _stremioAutoPickFirstStreamKey =
      'stremio_auto_pick_first_stream';

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

  /// When true, the integrated player does not auto-pause on background.
  Future<bool> getBuiltinPlayerBackgroundPlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_builtinPlayerBackgroundPlayKey) ?? false;
  }

  Future<void> setBuiltinPlayerBackgroundPlay(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_builtinPlayerBackgroundPlayKey, enabled);
  }

  /// When true, the mobile player shows PiP (Android). iOS/desktop ignore.
  Future<bool> getBuiltinPlayerPictureInPicture() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_builtinPlayerPictureInPictureKey) ?? false;
  }

  Future<void> setBuiltinPlayerPictureInPicture(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_builtinPlayerPictureInPictureKey, enabled);
  }

  /// Empty string = no preference (keep arrival order from addons).
  Future<String> getStremioPreferredStreamAddonBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_stremioPreferredStreamAddonKey) ?? '';
  }

  Future<void> setStremioPreferredStreamAddonBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stremioPreferredStreamAddonKey, baseUrl.trim());
  }

  Future<bool> getStremioAutoPickFirstStream() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_stremioAutoPickFirstStreamKey) ?? false;
  }

  Future<void> setStremioAutoPickFirstStream(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_stremioAutoPickFirstStreamKey, enabled);
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
}
