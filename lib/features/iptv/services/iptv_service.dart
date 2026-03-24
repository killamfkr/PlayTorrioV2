import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/iptv_credential.dart';
import '../models/iptv_user_info.dart';
import '../models/iptv_category.dart';
import '../models/iptv_channel.dart';
import '../models/iptv_movie.dart';
import '../models/iptv_series.dart';
import 'xtream_api_service.dart';
import 'm3u_parser_service.dart';
import '../models/iptv_epg_listing.dart';

/// Unified IPTV service that wraps both Xtream and M3U modes.
/// Singleton with session state. Supports multiple saved playlists.
class IptvService {
  static final IptvService _instance = IptvService._internal();
  factory IptvService() => _instance;
  IptvService._internal();

  static const String _credentialKey = 'iptv_credential';
  static const String _allCredentialsKey = 'iptv_all_credentials';
  static const String _activeCredentialIdKey = 'iptv_active_credential_id';

  IptvCredential? _credential;
  IptvUserInfo? _userInfo;
  XtreamApiService? _xtreamApi;

  // All saved playlists
  List<IptvCredential> _savedCredentials = [];

  // M3U cached data
  List<IptvChannel>? _m3uChannels;
  List<IptvCategory>? _m3uCategories;

  // Cache
  final Map<String, List<IptvChannel>> _liveStreamCache = {};
  final Map<String, List<IptvMovie>> _vodStreamCache = {};
  final Map<String, List<IptvSeries>> _seriesCache = {};
  List<IptvCategory>? _liveCategoriesCache;
  List<IptvCategory>? _vodCategoriesCache;
  List<IptvCategory>? _seriesCategoriesCache;
  DateTime? _cacheTimestamp;

  // Notifier for login state changes
  static final ValueNotifier<bool> loginStateNotifier = ValueNotifier<bool>(false);

  IptvCredential? get credential => _credential;
  IptvUserInfo? get userInfo => _userInfo;
  bool get isLoggedIn => _credential != null;
  bool get isXtream => _credential?.type == IptvLoginType.xtream;
  List<IptvCredential> get savedCredentials => List.unmodifiable(_savedCredentials);

  // ─── Persistence ────────────────────────────────────────────
  Future<void> loadSavedCredential() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load all saved credentials
      final allJson = prefs.getString(_allCredentialsKey);
      if (allJson != null) {
        final list = jsonDecode(allJson) as List;
        _savedCredentials = list.map((j) => IptvCredential.fromJson(j)).toList();
      }

      // Load active credential by ID
      final activeId = prefs.getString(_activeCredentialIdKey);
      if (activeId != null && _savedCredentials.isNotEmpty) {
        final active = _savedCredentials.where((c) => c.id == activeId).firstOrNull;
        if (active != null) {
          _credential = active;
          _initApiForCredential(active);
          loginStateNotifier.value = true;
          return;
        }
      }

      // Fallback: load legacy single credential
      final json = prefs.getString(_credentialKey);
      if (json != null) {
        final cred = IptvCredential.fromJson(jsonDecode(json));
        _credential = cred;
        _initApiForCredential(cred);
        // Migrate legacy credential to new list
        if (!_savedCredentials.any((c) => c.id == cred.id)) {
          _savedCredentials.add(cred);
          await _saveAllCredentials();
          await prefs.setString(_activeCredentialIdKey, cred.id);
        }
        loginStateNotifier.value = true;
      }
    } catch (e) {
      debugPrint('Failed to load IPTV credentials: $e');
    }
  }

  void _initApiForCredential(IptvCredential cred) {
    if (cred.type == IptvLoginType.xtream) {
      _xtreamApi = XtreamApiService(
        serverUrl: cred.serverUrl!,
        username: cred.username!,
        password: cred.password!,
      );
    }
  }

  Future<void> _saveAllCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _savedCredentials.map((c) => c.toJson()).toList();
    await prefs.setString(_allCredentialsKey, jsonEncode(list));
  }

  Future<void> _setActiveCredentialId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeCredentialIdKey, id);
    // Also keep legacy key in sync for backward compat
    final cred = _savedCredentials.where((c) => c.id == id).firstOrNull;
    if (cred != null) {
      await prefs.setString(_credentialKey, jsonEncode(cred.toJson()));
    }
  }

  // ─── Login ──────────────────────────────────────────────────
  Future<IptvUserInfo> loginXtream(String serverUrl, String username, String password, {String? name}) async {
    final api = XtreamApiService(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
    final userInfo = await api.authenticate();
    if (!userInfo.auth) {
      api.dispose();
      throw Exception('Invalid credentials');
    }

    _xtreamApi?.dispose();
    _xtreamApi = api;
    final cred = IptvCredential.xtream(server: serverUrl, user: username, pass: password, name: name);
    _credential = cred;
    _userInfo = userInfo;
    _clearCache();

    // Add to saved list (replace if same server+user combo exists)
    _savedCredentials.removeWhere((c) =>
        c.type == IptvLoginType.xtream && c.serverUrl == serverUrl && c.username == username);
    _savedCredentials.add(cred);
    await _saveAllCredentials();
    await _setActiveCredentialId(cred.id);
    loginStateNotifier.value = true;
    return userInfo;
  }

  Future<void> loginM3u(String url, {String? name}) async {
    final parser = M3uParserService();
    final result = await parser.parseFromUrl(url);
    _m3uChannels = result.channels;
    _m3uCategories = result.categories;
    final cred = IptvCredential.m3u(url: url, name: name);
    _credential = cred;
    _userInfo = null;
    _xtreamApi?.dispose();
    _xtreamApi = null;
    _clearCache();

    // Add to saved list (replace if same URL exists)
    _savedCredentials.removeWhere((c) => c.type == IptvLoginType.m3u && c.m3uUrl == url);
    _savedCredentials.add(cred);
    await _saveAllCredentials();
    await _setActiveCredentialId(cred.id);
    loginStateNotifier.value = true;
  }

  /// Switch to a previously saved playlist
  Future<void> switchToCredential(IptvCredential cred) async {
    _xtreamApi?.dispose();
    _xtreamApi = null;
    _m3uChannels = null;
    _m3uCategories = null;
    _clearCache();

    _credential = cred;
    if (cred.type == IptvLoginType.xtream) {
      _xtreamApi = XtreamApiService(
        serverUrl: cred.serverUrl!,
        username: cred.username!,
        password: cred.password!,
      );
      try {
        _userInfo = await _xtreamApi!.authenticate();
      } catch (_) {
        _userInfo = null;
      }
    } else {
      _userInfo = null;
      final parser = M3uParserService();
      final result = await parser.parseFromUrl(cred.m3uUrl!);
      _m3uChannels = result.channels;
      _m3uCategories = result.categories;
    }

    await _setActiveCredentialId(cred.id);
    loginStateNotifier.value = true;
  }

  /// Remove a saved playlist
  Future<void> removeCredential(String id) async {
    _savedCredentials.removeWhere((c) => c.id == id);
    await _saveAllCredentials();
    // If removing the active one, logout
    if (_credential?.id == id) {
      await logout();
    }
  }

  Future<void> logout() async {
    _xtreamApi?.dispose();
    _xtreamApi = null;
    _credential = null;
    _userInfo = null;
    _m3uChannels = null;
    _m3uCategories = null;
    _clearCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_credentialKey);
    await prefs.remove(_activeCredentialIdKey);
    loginStateNotifier.value = false;
  }

  void _clearCache() {
    _liveStreamCache.clear();
    _vodStreamCache.clear();
    _seriesCache.clear();
    _liveCategoriesCache = null;
    _vodCategoriesCache = null;
    _seriesCategoriesCache = null;
    _cacheTimestamp = null;
  }

  bool get _isCacheExpired {
    if (_cacheTimestamp == null) return true;
    return DateTime.now().difference(_cacheTimestamp!).inMinutes > 30;
  }

  // ─── Refresh user info ─────────────────────────────────────
  Future<void> refreshUserInfo() async {
    if (!isXtream || _xtreamApi == null) return;
    try {
      _userInfo = await _xtreamApi!.authenticate();
    } catch (_) {}
  }

  // ─── Live TV ────────────────────────────────────────────────
  Future<List<IptvCategory>> getLiveCategories() async {
    if (_credential?.type == IptvLoginType.m3u) {
      return _m3uCategories ?? [];
    }
    if (_liveCategoriesCache != null && !_isCacheExpired) return _liveCategoriesCache!;
    _liveCategoriesCache = await _xtreamApi!.getLiveCategories();
    _cacheTimestamp = DateTime.now();
    return _liveCategoriesCache!;
  }

  Future<List<IptvChannel>> getLiveStreams({String? categoryId}) async {
    if (_credential?.type == IptvLoginType.m3u) {
      final all = _m3uChannels ?? [];
      if (categoryId == null) return all;
      return all.where((c) => c.categoryId == categoryId || c.categoryName == categoryId).toList();
    }
    final key = categoryId ?? '_all';
    if (_liveStreamCache.containsKey(key) && !_isCacheExpired) {
      return _liveStreamCache[key]!;
    }
    final streams = await _xtreamApi!.getLiveStreams(categoryId: categoryId);
    _liveStreamCache[key] = streams;
    _cacheTimestamp = DateTime.now();
    return streams;
  }

  String getLiveStreamUrl(IptvChannel channel) {
    if (channel.streamUrl != null) return channel.streamUrl!;
    return _xtreamApi!.getLiveStreamUrl(channel.streamId);
  }

  // ─── VOD (Movies) ──────────────────────────────────────────
  Future<List<IptvCategory>> getVodCategories() async {
    if (_credential?.type == IptvLoginType.m3u) return [];
    if (_vodCategoriesCache != null && !_isCacheExpired) return _vodCategoriesCache!;
    _vodCategoriesCache = await _xtreamApi!.getVodCategories();
    _cacheTimestamp = DateTime.now();
    return _vodCategoriesCache!;
  }

  Future<List<IptvMovie>> getVodStreams({String? categoryId}) async {
    if (_credential?.type == IptvLoginType.m3u) return [];
    final key = categoryId ?? '_all';
    if (_vodStreamCache.containsKey(key) && !_isCacheExpired) {
      return _vodStreamCache[key]!;
    }
    final streams = await _xtreamApi!.getVodStreams(categoryId: categoryId);
    _vodStreamCache[key] = streams;
    _cacheTimestamp = DateTime.now();
    return streams;
  }

  Future<VodInfo> getVodInfo(int vodId) async {
    return _xtreamApi!.getVodInfo(vodId);
  }

  String getMovieUrl(int streamId, String containerExtension) {
    return _xtreamApi!.getMovieUrl(streamId, containerExtension);
  }

  // ─── Series ─────────────────────────────────────────────────
  Future<List<IptvCategory>> getSeriesCategories() async {
    if (_credential?.type == IptvLoginType.m3u) return [];
    if (_seriesCategoriesCache != null && !_isCacheExpired) return _seriesCategoriesCache!;
    _seriesCategoriesCache = await _xtreamApi!.getSeriesCategories();
    _cacheTimestamp = DateTime.now();
    return _seriesCategoriesCache!;
  }

  Future<List<IptvSeries>> getSeries({String? categoryId}) async {
    if (_credential?.type == IptvLoginType.m3u) return [];
    final key = categoryId ?? '_all';
    if (_seriesCache.containsKey(key) && !_isCacheExpired) {
      return _seriesCache[key]!;
    }
    final series = await _xtreamApi!.getSeries(categoryId: categoryId);
    _seriesCache[key] = series;
    _cacheTimestamp = DateTime.now();
    return series;
  }

  Future<SeriesInfo> getSeriesInfo(int seriesId) async {
    return _xtreamApi!.getSeriesInfo(seriesId);
  }

  String getEpisodeUrl(int episodeId, String containerExtension) {
    return _xtreamApi!.getEpisodeUrl(episodeId, containerExtension);
  }

  /// Xtream short EPG only; empty for M3U playlists.
  Future<List<IptvEpgListing>> getShortEpgListings(IptvChannel channel, {int limit = 12}) async {
    if (!isXtream || _xtreamApi == null) return [];
    if (channel.streamId <= 0) return [];
    return _xtreamApi!.getShortEpgListings(channel.streamId, limit: limit);
  }
}
