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

  // Jackett settings
  static const String _jackettBaseUrlKey = 'jackett_base_url';
  static const String _jackettApiKeyKey = 'jackett_api_key';
  
  // Prowlarr settings
  static const String _prowlarrBaseUrlKey = 'prowlarr_base_url';
  static const String _prowlarrApiKeyKey = 'prowlarr_api_key';

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
}
