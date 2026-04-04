import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'music_storage_service.dart';
import 'trakt_service.dart';

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
  /// When set, Streaming / Details screens pre-select this addon (baseUrl) for streams.
  static const String _defaultStremioAddonBaseUrlKey = 'stremio_default_addon_base_url';

  /// Stored when the user explicitly chooses built-in PlayTorrio over Stremio addons.
  static const String streamSourceForcePlayTorrio = '__pref_playtorrio__';

  /// Built-in player: keep playing when app goes to background (e.g. home gesture).
  static const String _continuePlaybackInBackgroundKey = 'playback_continue_in_background';
  /// Show Picture-in-Picture control in the mobile player (Android).
  static const String _showAndroidPipButtonKey = 'playback_show_android_pip_button';
  /// Android 12+: enter PiP automatically when user leaves the app while playing.
  static const String _autoEnterPipAndroidKey = 'playback_auto_pip_android';
  /// Built-in player: show embedded / external subtitles (Flutter overlay + mpv track).
  static const String _builtinPlayerSubtitlesEnabledKey =
      'playback_builtin_subtitles_enabled';

  /// Android TV: max HLS/DASH variant bitrate (Kbps) for mpv `hls-bitrate`. `0` = no cap (max).
  /// When unset, the player uses a safe default cap on TV only.
  static const String _androidTvMaxStreamBitrateKbpsKey =
      'playback_android_tv_max_stream_bitrate_kbps';

  /// Keeps the built-in player UI in sync when the user toggles subtitles in Settings.
  static final ValueNotifier<bool> builtinPlayerSubtitlesEnabledNotifier =
      ValueNotifier<bool>(true);

  // External player setting
  static const String _externalPlayerKey = 'external_player';

  // Jackett settings
  static const String _jackettBaseUrlKey = 'jackett_base_url';
  static const String _jackettApiKeyKey = 'jackett_api_key';
  
  // Prowlarr settings
  static const String _prowlarrBaseUrlKey = 'prowlarr_base_url';
  static const String _prowlarrApiKeyKey = 'prowlarr_api_key';

  // Light mode (performance)
  static const String _lightModeKey = 'light_mode';

  /// Notifier that fires when light mode changes so all widgets can react.
  static final ValueNotifier<bool> lightModeNotifier = ValueNotifier<bool>(false);

  // Torrent cache settings
  static const String _torrentCacheTypeKey = 'torrent_cache_type';
  static const String _torrentRamCacheMbKey = 'torrent_ram_cache_mb';

  /// Optional XMLTV URL for TV Guide when Stremio addons do not embed schedules.
  static const String _xmltvEpgUrlKey = 'xmltv_epg_url';

  Future<String?> getXmltvEpgUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_xmltvEpgUrlKey);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  Future<void> setXmltvEpgUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await prefs.remove(_xmltvEpgUrlKey);
    } else {
      await prefs.setString(_xmltvEpgUrlKey, url.trim());
    }
  }

  /// XMLTV `<programme channel="...">` id → match a live Stremio channel (same addon baseUrl + meta id).
  static const String _xmltvChannelMapKey = 'xmltv_epg_channel_map_json';

  /// Keys are JSON: `{"b":"<addonBaseUrl>","i":"<stremioChannelId>"}` → EPG channel id string.
  Future<Map<String, String>> getXmltvChannelMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_xmltvChannelMapKey);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  static String xmltvChannelMapKeyFor({required String addonBaseUrl, required String stremioChannelId}) {
    return json.encode({'b': addonBaseUrl, 'i': stremioChannelId});
  }

  Future<void> setXmltvChannelMap(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    if (map.isEmpty) {
      await prefs.remove(_xmltvChannelMapKey);
    } else {
      await prefs.setString(_xmltvChannelMapKey, json.encode(map));
    }
  }

  Future<void> setXmltvChannelMapping({
    required String addonBaseUrl,
    required String stremioChannelId,
    required String epgChannelId,
  }) async {
    final map = await getXmltvChannelMap();
    final k = xmltvChannelMapKeyFor(
      addonBaseUrl: addonBaseUrl,
      stremioChannelId: stremioChannelId,
    );
    if (epgChannelId.trim().isEmpty) {
      map.remove(k);
    } else {
      map[k] = epgChannelId.trim();
    }
    await setXmltvChannelMap(map);
  }

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

  /// Raw preference: `null` = auto (prefer first Stremio addon when installed),
  /// [streamSourceForcePlayTorrio] = always PlayTorrio, else a specific addon baseUrl.
  Future<String?> getDefaultStremioAddonBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_defaultStremioAddonBaseUrlKey);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  /// Resolves which source id to use on streaming UI: `'playtorrio'` or an addon baseUrl.
  /// With no saved preference, prefers the first installed stream addon over built-in scrapers.
  Future<String> resolveDefaultStreamSourceId(
    List<Map<String, dynamic>> streamAddons,
  ) async {
    final raw = await getDefaultStremioAddonBaseUrl();
    if (raw == streamSourceForcePlayTorrio) return 'playtorrio';
    if (raw != null &&
        raw.isNotEmpty &&
        streamAddons.any((a) => a['baseUrl'] == raw)) {
      return raw;
    }
    if (streamAddons.isNotEmpty) {
      return streamAddons.first['baseUrl'] as String;
    }
    return 'playtorrio';
  }

  /// Pass `null` or `'__auto__'` to clear preference (auto: first addon).
  /// Pass `'__playtorrio__'` to force built-in PlayTorrio when addons exist.
  Future<void> setDefaultStremioAddonBaseUrl(String? baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    if (baseUrl == null || baseUrl.isEmpty || baseUrl == '__auto__') {
      await prefs.remove(_defaultStremioAddonBaseUrlKey);
    } else if (baseUrl == '__playtorrio__') {
      await prefs.setString(
        _defaultStremioAddonBaseUrlKey,
        streamSourceForcePlayTorrio,
      );
    } else {
      await prefs.setString(_defaultStremioAddonBaseUrlKey, baseUrl);
    }
  }

  Future<bool> continuePlaybackInBackground() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_continuePlaybackInBackgroundKey) ?? true;
  }

  Future<void> setContinuePlaybackInBackground(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_continuePlaybackInBackgroundKey, value);
  }

  Future<bool> showAndroidPipButton() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showAndroidPipButtonKey) ?? true;
  }

  Future<void> setShowAndroidPipButton(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showAndroidPipButtonKey, value);
  }

  Future<bool> autoEnterPipAndroid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoEnterPipAndroidKey) ?? false;
  }

  Future<void> setAutoEnterPipAndroid(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoEnterPipAndroidKey, value);
  }

  Future<bool> getBuiltinPlayerSubtitlesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_builtinPlayerSubtitlesEnabledKey) ?? true;
    if (builtinPlayerSubtitlesEnabledNotifier.value != v) {
      builtinPlayerSubtitlesEnabledNotifier.value = v;
    }
    return v;
  }

  Future<void> setBuiltinPlayerSubtitlesEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_builtinPlayerSubtitlesEnabledKey, value);
    builtinPlayerSubtitlesEnabledNotifier.value = value;
  }

  /// `null` if the user never changed TV stream cap (player uses built-in default).
  /// `0` means unlimited (mpv `hls-bitrate=max`).
  Future<int?> getAndroidTvMaxStreamBitrateKbps() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_androidTvMaxStreamBitrateKbpsKey)) return null;
    return prefs.getInt(_androidTvMaxStreamBitrateKbpsKey);
  }

  Future<void> setAndroidTvMaxStreamBitrateKbps(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_androidTvMaxStreamBitrateKbpsKey, value);
  }

  Future<void> clearAndroidTvMaxStreamBitrateKbps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_androidTvMaxStreamBitrateKbpsKey);
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
    final v = prefs.getString(_externalPlayerKey) ?? 'Built-in Player';
    // Removed in-app native Exo option — map old installs back to built-in.
    if (v == 'Native ExoPlayer (TV)') {
      await prefs.setString(_externalPlayerKey, 'Built-in Player');
      return 'Built-in Player';
    }
    return v;
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
  // Light Mode (Performance)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> isLightModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_lightModeKey) ?? false;
  }

  Future<void> setLightMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lightModeKey, enabled);
    lightModeNotifier.value = enabled;
  }

  /// Call once at app startup to hydrate the notifier from disk.
  Future<void> initLightMode() async {
    lightModeNotifier.value = await isLightModeEnabled();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Navbar Configuration
  // ═══════════════════════════════════════════════════════════════════════════

  static const String _navbarConfigKey = 'navbar_config';

  /// Notifier that fires when navbar config changes so MainScreen rebuilds.
  static final ValueNotifier<int> navbarChangeNotifier = ValueNotifier<int>(0);

  /// All available nav items in default order. 'settings' is always last and locked.
  /// Search, My List, and Magnet are intentionally last (before Settings in the UI).
  static const List<String> allNavIds = [
    'home', 'discover', 'live_matches',
    'iptv', 'audiobooks', 'books', 'music', 'comics', 'manga',
    'jellyfin', 'anime', 'search', 'mylist', 'magnet',
  ];

  static const List<String> _navTailIds = ['search', 'mylist', 'magnet'];

  /// Returns the ordered list of visible nav item IDs.
  /// Settings is NOT stored — it's always appended by the consumer.
  Future<List<String>> getNavbarConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_navbarConfigKey);
    if (raw == null) return List.from(allNavIds);

    // Drop stale / removed ids; keep user order except tail ids always last.
    final filtered = raw.where((id) => allNavIds.contains(id)).toList();
    final middle = <String>[];
    for (final id in filtered) {
      if (!_navTailIds.contains(id)) middle.add(id);
    }
    final tail = <String>[];
    for (final id in _navTailIds) {
      if (filtered.contains(id)) tail.add(id);
    }
    return [...middle, ...tail];
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
    for (final key in [
      _streamingModeKey,
      _useDebridKey,
      _lightModeKey,
      _continuePlaybackInBackgroundKey,
      _showAndroidPipButtonKey,
      _autoEnterPipAndroidKey,
      _builtinPlayerSubtitlesEnabledKey,
    ]) {
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
      _defaultStremioAddonBaseUrlKey,
      _xmltvEpgUrlKey,
      _xmltvChannelMapKey,
      TraktService.prefsClientIdKey,
      TraktService.prefsClientSecretKey,
    ]) {
      final v = prefs.getString(key);
      if (v != null) prefsMap[key] = v;
    }
    // Int keys
    for (final key in [
      _torrentRamCacheMbKey,
      _androidTvMaxStreamBitrateKbpsKey,
    ]) {
      final v = prefs.getInt(key);
      if (v != null) prefsMap[key] = v;
    }
    // StringList keys
    for (final key in [
      _stremioAddonsKey,
      _navbarConfigKey,
      MusicStorageService.prefsLikedSongsKey,
      MusicStorageService.prefsPlaylistsKey,
    ]) {
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
    for (final key in [
      _streamingModeKey,
      _useDebridKey,
      _lightModeKey,
      _continuePlaybackInBackgroundKey,
      _showAndroidPipButtonKey,
      _autoEnterPipAndroidKey,
      _builtinPlayerSubtitlesEnabledKey,
    ]) {
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
      _defaultStremioAddonBaseUrlKey,
      _xmltvEpgUrlKey,
      _xmltvChannelMapKey,
      TraktService.prefsClientIdKey,
      TraktService.prefsClientSecretKey,
    ]) {
      if (prefsMap.containsKey(key)) {
        await prefs.setString(key, prefsMap[key] as String);
      }
    }
    // Int keys
    for (final key in [
      _torrentRamCacheMbKey,
      _androidTvMaxStreamBitrateKbpsKey,
    ]) {
      if (prefsMap.containsKey(key)) {
        await prefs.setInt(key, (prefsMap[key] as num).toInt());
      }
    }
    // StringList keys
    for (final key in [
      _stremioAddonsKey,
      _navbarConfigKey,
      MusicStorageService.prefsLikedSongsKey,
      MusicStorageService.prefsPlaylistsKey,
    ]) {
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

    final music = MusicStorageService();
    music.likedSongs.value = await music.getLikedSongs();
  }
}
