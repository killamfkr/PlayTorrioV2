import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../api/local_server_service.dart';
import '../platform_flags.dart';
import 'jellyfin_http.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Models
// ═════════════════════════════════════════════════════════════════════════════

/// Represents a single Jellyfin server account.
class JellyfinAccount {
  final String serverUrl;
  final String username;
  final String password;
  String? accessToken;
  String? userId;
  String? serverName;

  JellyfinAccount({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.accessToken,
    this.userId,
    this.serverName,
  });

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'password': password,
    'accessToken': accessToken,
    'userId': userId,
    'serverName': serverName,
  };

  factory JellyfinAccount.fromJson(Map<String, dynamic> json) => JellyfinAccount(
    serverUrl: json['serverUrl'] ?? '',
    username: json['username'] ?? '',
    password: json['password'] ?? '',
    accessToken: json['accessToken'],
    userId: json['userId'],
    serverName: json['serverName'],
  );

  String get normalizedUrl {
    var url = serverUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url.replaceAll(RegExp(r'/+$'), '');
  }
}

/// Lightweight model for a Jellyfin media item.
class JellyfinItem {
  final String id;
  final String name;
  final String type;
  final String? overview;
  final int? productionYear;
  final double? communityRating;
  final String? officialRating;
  final int? runTimeTicks;
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final int? indexNumber;
  final int? parentIndexNumber;
  final List<String> genres;
  final Map<String, String> imageTags;
  final List<String> backdropImageTags;
  final String? collectionType;
  final Map<String, dynamic>? userData;
  final String? status;
  final String? mediaType;
  final List<dynamic>? mediaStreams;
  final String? container;

  JellyfinItem({
    required this.id,
    required this.name,
    required this.type,
    this.overview,
    this.productionYear,
    this.communityRating,
    this.officialRating,
    this.runTimeTicks,
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.indexNumber,
    this.parentIndexNumber,
    this.genres = const [],
    this.imageTags = const {},
    this.backdropImageTags = const [],
    this.collectionType,
    this.userData,
    this.status,
    this.mediaType,
    this.mediaStreams,
    this.container,
  });

  factory JellyfinItem.fromJson(Map<String, dynamic> json) {
    return JellyfinItem(
      id: json['Id'] ?? '',
      name: json['Name'] ?? '',
      type: json['Type'] ?? '',
      overview: json['Overview'],
      productionYear: json['ProductionYear'],
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      officialRating: json['OfficialRating'],
      runTimeTicks: json['RunTimeTicks'],
      seriesId: json['SeriesId'],
      seriesName: json['SeriesName'],
      seasonId: json['SeasonId'],
      indexNumber: json['IndexNumber'],
      parentIndexNumber: json['ParentIndexNumber'],
      genres: (json['Genres'] as List<dynamic>?)?.cast<String>() ?? [],
      imageTags: (json['ImageTags'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          {},
      backdropImageTags:
          (json['BackdropImageTags'] as List<dynamic>?)?.cast<String>() ?? [],
      collectionType: json['CollectionType'],
      userData: json['UserData'] as Map<String, dynamic>?,
      status: json['Status'],
      mediaType: json['MediaType'],
      mediaStreams: json['MediaStreams'] as List<dynamic>?,
      container: json['Container'],
    );
  }

  String get runtime {
    if (runTimeTicks == null) return '';
    final minutes = (runTimeTicks! / 600000000).round();
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  double get playbackProgress {
    if (userData == null || runTimeTicks == null || runTimeTicks == 0) return 0;
    final pos = userData!['PlaybackPositionTicks'] as int? ?? 0;
    return (pos / runTimeTicks!).clamp(0.0, 1.0);
  }

  bool get isPlayed => userData?['Played'] == true;
  bool get isFavorite => userData?['IsFavorite'] == true;
  int get unplayedCount => userData?['UnplayedItemCount'] as int? ?? 0;
}

/// Preloaded home screen data returned by [JellyfinService.loadHomeData].
class HomeData {
  final List<JellyfinItem> libraries;
  final List<JellyfinItem> resumeItems;
  final List<JellyfinItem> nextUpItems;
  final Map<String, List<JellyfinItem>> latestByLibrary;

  const HomeData({
    this.libraries = const [],
    this.resumeItems = const [],
    this.nextUpItems = const [],
    this.latestByLibrary = const {},
  });
}

/// Preloaded series detail data returned by [JellyfinService.loadSeriesData].
class SeriesData {
  final JellyfinItem details;
  final List<JellyfinItem> seasons;
  final List<JellyfinItem> allEpisodes;
  final List<JellyfinItem> similarItems;

  const SeriesData({
    required this.details,
    this.seasons = const [],
    this.allEpisodes = const [],
    this.similarItems = const [],
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// Cache
// ═════════════════════════════════════════════════════════════════════════════

class _CacheEntry<T> {
  final T data;
  final DateTime expires;
  _CacheEntry(this.data, Duration ttl) : expires = DateTime.now().add(ttl);
  bool get isValid => DateTime.now().isBefore(expires);
}

// ═════════════════════════════════════════════════════════════════════════════
// Service
// ═════════════════════════════════════════════════════════════════════════════

class JellyfinService {
  static final JellyfinService _instance = JellyfinService._internal();
  factory JellyfinService() => _instance;
  JellyfinService._internal();

  static const String _accountsKey = 'jellyfin_accounts';
  static const String _activeAccountKey = 'jellyfin_active_account';
  static const _secureStorage = FlutterSecureStorage();

  // In-memory cache — keyed by URL string, values are _CacheEntry<dynamic>.
  final Map<String, _CacheEntry<dynamic>> _cache = {};
  static const _maxCacheEntries = 200;
  static const _shortTtl = Duration(minutes: 2);   // resume, nextUp
  static const _mediumTtl = Duration(minutes: 10);  // items, details
  static const _longTtl = Duration(minutes: 30);    // libraries

  void clearCache() => _cache.clear();

  T? _getFromCache<T>(String key) {
    final entry = _cache[key];
    if (entry != null && entry.isValid) return entry.data as T;
    if (entry != null) _cache.remove(key);
    return null;
  }

  void _putInCache<T>(String key, T data, Duration ttl) {
    // Evict expired entries first, then oldest if still over limit
    if (_cache.length >= _maxCacheEntries) {
      _cache.removeWhere((_, e) => !e.isValid);
    }
    if (_cache.length >= _maxCacheEntries) {
      final oldest = _cache.entries
          .reduce((a, b) => a.value.expires.isBefore(b.value.expires) ? a : b);
      _cache.remove(oldest.key);
    }
    _cache[key] = _CacheEntry<T>(data, ttl);
  }

  // ─── HTTP Client ─────────────────────────────────────────────────────────
  // Uses the shared Jellyfin client (self-signed friendly on IO; std client on web).
  final http.Client _httpClient = createJellyfinHttpClient();

  /// Core HTTP request method.
  /// - Follows redirects (301/302/307/308) manually.
  /// - Retries on transient network errors with exponential backoff.
  Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 30),
    int maxRetries = 2,
  }) async {
    Exception? lastError;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        final delay = Duration(milliseconds: 300 * (1 << (attempt - 1)));
        debugPrint('[Jellyfin] Retry $attempt after ${delay.inMilliseconds}ms');
        await Future.delayed(delay);
      }

      try {
        return await _doRequest(method, uri, headers: headers, body: body, timeout: timeout);
      } on Exception catch (e) {
        lastError = e;
        debugPrint('[Jellyfin] Request error (attempt $attempt): $e');
      }
    }

    throw lastError ?? Exception('Request failed after retries');
  }

  Future<http.Response> _doRequest(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    var currentUri = uri;
    const maxRedirects = 5;

    for (var i = 0; i <= maxRedirects; i++) {
      final req = http.Request(method, currentUri);
      headers?.forEach((k, v) {
        req.headers[k] = v;
      });
      if (body != null && (method == 'POST' || method == 'PUT')) {
        req.body = body;
      }

      final streamed = await _httpClient.send(req).timeout(timeout);
      final statusCode = streamed.statusCode;

      if (statusCode >= 300 && statusCode < 400) {
        final location = streamed.headers['location'];
        if (location == null) break;
        await streamed.stream.drain();
        currentUri = currentUri.resolve(location);
        debugPrint('[Jellyfin] Redirect $statusCode → $currentUri');
        continue;
      }

      final respBody = await streamed.stream.transform(utf8.decoder).join();
      return http.Response(respBody, statusCode, headers: streamed.headers);
    }

    throw Exception('Too many redirects');
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 30)}) =>
      _request('GET', uri, headers: headers, timeout: timeout);

  Future<http.Response> _post(Uri uri, {Map<String, String>? headers, String? body, Duration timeout = const Duration(seconds: 30)}) =>
      _request('POST', uri, headers: headers, body: body, timeout: timeout, maxRetries: 0);

  Future<http.Response> _delete(Uri uri, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 30)}) =>
      _request('DELETE', uri, headers: headers, timeout: timeout, maxRetries: 0);

  /// Cached GET — returns parsed JSON (already decoded) from cache or network.
  Future<dynamic> _cachedGet(String url, {Duration ttl = _mediumTtl}) async {
    final cached = _getFromCache<dynamic>(url);
    if (cached != null) return cached;

    final resp = await _get(Uri.parse(url), headers: _authHeaders);
    if (resp.statusCode != 200) throw Exception('GET $url failed (${resp.statusCode})');

    final data = json.decode(resp.body);
    _putInCache(url, data, ttl);
    return data;
  }

  // ─── Auth / Session State ────────────────────────────────────────────────

  JellyfinAccount? _activeAccount;
  JellyfinAccount? get activeAccount => _activeAccount;
  bool get isLoggedIn => _activeAccount?.accessToken != null;

  static const String _deviceIdKey = 'jellyfin_device_id';
  String _deviceId = '';

  /// Ensures a persistent deviceId exists. Called lazily on first use.
  Future<void> _ensureDeviceId() async {
    if (_deviceId.isNotEmpty) return;
    final stored = await _secureStorage.read(key: _deviceIdKey);
    if (stored != null && stored.isNotEmpty) {
      _deviceId = stored;
    } else {
      _deviceId = 'playtorrio_${DateTime.now().millisecondsSinceEpoch}';
      await _secureStorage.write(key: _deviceIdKey, value: _deviceId);
    }
  }

  List<Map<String, dynamic>> _lastSubtitles = [];
  String _lastPlaySessionId = '';
  String _lastMediaSourceId = '';
  String _lastPlayMethod = 'DirectPlay';
  List<Map<String, dynamic>> get lastSubtitles => _lastSubtitles;

  Map<String, String> get _authHeaders {
    final parts = [
      'MediaBrowser Client="PlayTorrio"',
      'Device="${kIsWeb ? "Web" : (platformIsAndroid ? "Android" : "Windows")}"',
      'DeviceId="$_deviceId"',
      'Version="1.0.0"',
    ];
    if (_activeAccount?.accessToken != null) {
      parts.add('Token="${_activeAccount!.accessToken}"');
    }
    return {
      'X-Emby-Authorization': parts.join(', '),
      'Content-Type': 'application/json',
    };
  }

  String get authHeaderValue => _authHeaders['X-Emby-Authorization'] ?? '';

  Map<String, String> get streamHeaders => {
    'X-Emby-Authorization': authHeaderValue,
  };

  String get _base => _activeAccount?.normalizedUrl ?? '';
  String get _userId => _activeAccount?.userId ?? '';

  // ─── Helpers ─────────────────────────────────────────────────────────────

  List<JellyfinItem> _parseItems(dynamic data) {
    if (data is List) {
      return data.map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    final items = (data as Map<String, dynamic>)['Items'] as List<dynamic>? ?? [];
    return items.map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  String _buildQueryUrl(String path, Map<String, String> params) {
    return Uri.parse('$_base$path').replace(queryParameters: params).toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Account Persistence
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<JellyfinAccount>> getSavedAccounts() async {
    final raw = await _secureStorage.read(key: _accountsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = json.decode(raw) as List<dynamic>;
    return list.map((s) => JellyfinAccount.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<void> _saveAccounts(List<JellyfinAccount> accounts) async {
    await _secureStorage.write(
      key: _accountsKey,
      value: json.encode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> _setActiveIndex(int index) async {
    await _secureStorage.write(key: _activeAccountKey, value: '$index');
  }

  Future<bool> loadSavedSession() async {
    await _ensureDeviceId();
    final accounts = await getSavedAccounts();
    final idxStr = await _secureStorage.read(key: _activeAccountKey);
    final idx = idxStr != null ? int.tryParse(idxStr) ?? -1 : -1;
    if (idx >= 0 && idx < accounts.length) {
      _activeAccount = accounts[idx];
      clearCache();
      if (_activeAccount!.accessToken != null) {
        try {
          final resp = await _get(
              Uri.parse('$_base/Users/Me'),
              headers: _authHeaders);
          if (resp.statusCode == 200) {
            debugPrint('[Jellyfin] Restored session for ${_activeAccount!.username}');
            return true;
          }
        } catch (_) {}
        try {
          return await login(
            _activeAccount!.serverUrl,
            _activeAccount!.username,
            _activeAccount!.password,
          );
        } catch (_) {}
      }
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Authentication
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> login(String serverUrl, String username, String password) async {
    await _ensureDeviceId();
    _activeAccount = JellyfinAccount(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
    clearCache();

    final resp = await _post(
      Uri.parse('$_base/Users/AuthenticateByName'),
      headers: _authHeaders,
      body: json.encode({'Username': username, 'Pw': password}),
    );

    if (resp.statusCode != 200) {
      _activeAccount = null;
      throw Exception('Login failed (${resp.statusCode}): ${resp.body}');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    _activeAccount!.accessToken = data['AccessToken'] as String;
    _activeAccount!.userId = (data['User'] as Map<String, dynamic>)['Id'] as String;
    _activeAccount!.serverName = data['ServerId'] as String?;

    final accounts = await getSavedAccounts();
    final existingIdx = accounts.indexWhere(
      (a) => a.normalizedUrl == _activeAccount!.normalizedUrl && a.username == username,
    );
    if (existingIdx >= 0) {
      accounts[existingIdx] = _activeAccount!;
      await _saveAccounts(accounts);
      await _setActiveIndex(existingIdx);
    } else {
      accounts.add(_activeAccount!);
      await _saveAccounts(accounts);
      await _setActiveIndex(accounts.length - 1);
    }

    debugPrint('[Jellyfin] Logged in as $username on $_base');
    return true;
  }

  Future<void> logout() async {
    _activeAccount = null;
    clearCache();
    await _secureStorage.delete(key: _activeAccountKey);
  }

  Future<void> removeAccount(int index) async {
    final accounts = await getSavedAccounts();
    if (index < 0 || index >= accounts.length) return;
    final removed = accounts.removeAt(index);
    await _saveAccounts(accounts);
    if (_activeAccount?.normalizedUrl == removed.normalizedUrl &&
        _activeAccount?.username == removed.username) {
      await logout();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Libraries / Views
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<JellyfinItem>> getLibraries() async {
    const cacheKey = '__libraries__';
    final cached = _getFromCache<List<JellyfinItem>>(cacheKey);
    if (cached != null) return cached;

    final resp = await _get(Uri.parse('$_base/UserViews?userId=$_userId'), headers: _authHeaders);
    if (resp.statusCode != 200) throw Exception('Failed to fetch libraries');
    final items = _parseItems(json.decode(resp.body));
    _putInCache(cacheKey, items, _longTtl);
    return items;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Items
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<JellyfinItem>> getItems({
    String? parentId,
    String? includeItemTypes,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    int startIndex = 0,
    int limit = 50,
    String? searchTerm,
    String? genres,
    String fields = 'Overview,Genres,PrimaryImageAspectRatio,MediaStreams,Container',
    bool recursive = true,
    String? filters,
  }) async {
    final params = <String, String>{
      'userId': _userId,
      'recursive': '$recursive',
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      'startIndex': '$startIndex',
      'limit': '$limit',
      'fields': fields,
      'enableImageTypes': 'Primary,Backdrop,Thumb',
      'imageTypeLimit': '1',
    };
    if (parentId != null) params['parentId'] = parentId;
    if (includeItemTypes != null) params['includeItemTypes'] = includeItemTypes;
    if (searchTerm != null) params['searchTerm'] = searchTerm;
    if (genres != null) params['genres'] = genres;
    if (filters != null) params['filters'] = filters;

    final url = _buildQueryUrl('/Items', params);
    final data = await _cachedGet(url, ttl: _mediumTtl);
    return _parseItems(data);
  }

  Future<({List<JellyfinItem> items, int totalCount})> getItemsPaged({
    String? parentId,
    String? includeItemTypes,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    int startIndex = 0,
    int? limit,
    String? searchTerm,
    String fields = 'Overview,Genres,PrimaryImageAspectRatio,MediaStreams,Container',
    bool recursive = true,
  }) async {
    final params = <String, String>{
      'userId': _userId,
      'recursive': '$recursive',
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      'startIndex': '$startIndex',
      'fields': fields,
      'enableImageTypes': 'Primary,Backdrop,Thumb',
      'imageTypeLimit': '1',
      'enableTotalRecordCount': 'true',
    };
    if (limit != null) params['limit'] = '$limit';
    if (parentId != null) params['parentId'] = parentId;
    if (includeItemTypes != null) params['includeItemTypes'] = includeItemTypes;
    if (searchTerm != null && searchTerm.isNotEmpty) params['searchTerm'] = searchTerm;

    final url = _buildQueryUrl('/Items', params);
    // Use a longer timeout when fetching all items (no limit) — large
    // libraries can take the server a while to serialize.
    final timeout = limit == null ? const Duration(seconds: 60) : const Duration(seconds: 30);
    final resp = await _get(Uri.parse(url), headers: _authHeaders, timeout: timeout);
    if (resp.statusCode != 200) throw Exception('Failed to fetch items: ${resp.statusCode}');
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final items = _parseItems(data);
    final total = (data['TotalRecordCount'] as num?)?.toInt() ?? items.length;
    return (items: items, totalCount: total);
  }

  Future<JellyfinItem> getItemDetails(String itemId) async {
    final url = '$_base/Items/$itemId?userId=$_userId';
    final data = await _cachedGet(url, ttl: _mediumTtl);
    return JellyfinItem.fromJson(data as Map<String, dynamic>);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Latest / Resume / Next Up
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<JellyfinItem>> getLatestItems({
    String? parentId,
    int limit = 20,
    String? includeItemTypes,
  }) async {
    final params = <String, String>{
      'userId': _userId,
      'limit': '$limit',
      'fields': 'Overview,Genres,PrimaryImageAspectRatio',
      'enableImages': 'true',
      'imageTypeLimit': '1',
      'enableImageTypes': 'Primary,Backdrop,Thumb',
    };
    if (parentId != null) params['parentId'] = parentId;
    if (includeItemTypes != null) params['includeItemTypes'] = includeItemTypes;

    final url = _buildQueryUrl('/Items/Latest', params);
    final data = await _cachedGet(url, ttl: _shortTtl);
    return _parseItems(data);
  }

  Future<List<JellyfinItem>> getResumeItems({int limit = 12}) async {
    final params = <String, String>{
      'userId': _userId,
      'limit': '$limit',
      'mediaTypes': 'Video',
      'fields': 'Overview,Genres,PrimaryImageAspectRatio',
      'enableImages': 'true',
      'imageTypeLimit': '1',
      'enableImageTypes': 'Primary,Backdrop,Thumb',
    };
    final url = _buildQueryUrl('/UserItems/Resume', params);
    try {
      final data = await _cachedGet(url, ttl: _shortTtl);
      return _parseItems(data);
    } catch (_) {
      return [];
    }
  }

  Future<List<JellyfinItem>> getNextUp({int limit = 20}) async {
    final params = <String, String>{
      'userId': _userId,
      'limit': '$limit',
      'fields': 'Overview,Genres,PrimaryImageAspectRatio',
      'enableImages': 'true',
      'enableImageTypes': 'Primary,Backdrop,Thumb',
    };
    final url = _buildQueryUrl('/Shows/NextUp', params);
    try {
      final data = await _cachedGet(url, ttl: _shortTtl);
      return _parseItems(data);
    } catch (_) {
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Parallel Home Data Loading
  // ═══════════════════════════════════════════════════════════════════════════

  /// Loads all home screen data in parallel: libraries, resume, nextUp, and
  /// latest items per video library. Returns a [HomeData] bundle.
  /// This replaces the old sequential pattern where the screen awaited each
  /// call one-by-one.
  Future<HomeData> loadHomeData() async {
    // Phase 1: libraries + resume + nextUp in parallel
    final results = await Future.wait([
      getLibraries(),
      getResumeItems(limit: 12),
      getNextUp(limit: 20),
    ]);

    final libraries = results[0];
    final resumeItems = results[1];
    final nextUpItems = results[2];

    // Phase 2: latest items per video library in parallel
    final videoLibs = libraries.where(
      (l) => l.collectionType == 'movies' || l.collectionType == 'tvshows' || l.collectionType == null,
    ).toList();

    final latestFutures = videoLibs.map(
      (lib) => getLatestItems(parentId: lib.id, limit: 16)
          .then((items) => MapEntry(lib.name, items))
          .catchError((_) => MapEntry(lib.name, <JellyfinItem>[])),
    );
    final latestEntries = await Future.wait(latestFutures);
    final latestByLibrary = Map<String, List<JellyfinItem>>.fromEntries(
      latestEntries.where((e) => e.value.isNotEmpty),
    );

    return HomeData(
      libraries: libraries,
      resumeItems: resumeItems,
      nextUpItems: nextUpItems,
      latestByLibrary: latestByLibrary,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TV Shows — Seasons & Episodes
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<JellyfinItem>> getSeasons(String seriesId) async {
    final url = '$_base/Shows/$seriesId/Seasons?userId=$_userId'
        '&fields=Overview,PrimaryImageAspectRatio';
    final data = await _cachedGet(url, ttl: _mediumTtl);
    return _parseItems(data);
  }

  Future<List<JellyfinItem>> getEpisodes(String seriesId, {String? seasonId, int? seasonNumber}) async {
    final params = <String, String>{
      'userId': _userId,
      'fields': 'Overview,PrimaryImageAspectRatio,MediaStreams,Container,ParentIndexNumber,IndexNumber',
    };
    if (seasonId != null) params['seasonId'] = seasonId;
    if (seasonNumber != null) params['season'] = '$seasonNumber';

    final url = _buildQueryUrl('/Shows/$seriesId/Episodes', params);
    final data = await _cachedGet(url, ttl: _mediumTtl);
    return _parseItems(data);
  }

  Future<List<JellyfinItem>> getEpisodesByItems(String seriesId) async {
    final params = <String, String>{
      'userId': _userId,
      'seriesId': seriesId,
      'includeItemTypes': 'Episode',
      'recursive': 'true',
      'sortBy': 'ParentIndexNumber,IndexNumber,SortName',
      'sortOrder': 'Ascending',
      'fields': 'Overview,PrimaryImageAspectRatio,MediaStreams,Container,ParentIndexNumber,IndexNumber',
    };
    final url = _buildQueryUrl('/Items', params);
    final data = await _cachedGet(url, ttl: _mediumTtl);
    return _parseItems(data);
  }

  /// Parallel series detail loader — fetches details, seasons, episodes, and
  /// similar items concurrently instead of sequentially.
  Future<SeriesData> loadSeriesData(String seriesId, {String? firstGenre}) async {
    // Phase 1: details + seasons in parallel (similar deferred until we have genres)
    final detailsFuture = getItemDetails(seriesId);
    final seasonsFuture = getSeasons(seriesId).catchError((_) => <JellyfinItem>[]);

    final results = await Future.wait([detailsFuture, seasonsFuture]);
    final details = results[0] as JellyfinItem;
    final seasons = results[1] as List<JellyfinItem>;

    // Use detail's genres if caller didn't provide one (stub items from Continue Watching etc.)
    final genre = firstGenre ?? (details.genres.isNotEmpty ? details.genres.first : null);

    // Phase 2: episodes + similar in parallel
    final similarFuture = genre != null
        ? getItems(
            includeItemTypes: 'Series',
            sortBy: 'Random',
            limit: 12,
            genres: genre,
          ).then((items) => items.where((i) => i.id != seriesId).toList())
          .catchError((_) => <JellyfinItem>[])
        : Future.value(<JellyfinItem>[]);

    List<JellyfinItem> allEpisodes = [];
    if (seasons.isNotEmpty) {
      final episodeFutures = seasons.map(
        (s) => getEpisodes(seriesId, seasonId: s.id).catchError((_) => <JellyfinItem>[]),
      );
      final episodeResults = await Future.wait([
        ...episodeFutures,
        similarFuture,
      ]);
      // Last result is similar items, rest are episode lists
      final similarItems = episodeResults.last;
      final episodeLists = episodeResults.sublist(0, episodeResults.length - 1);
      allEpisodes = episodeLists.expand((e) => e).toList();

      // If no episodes found, try fallback methods
      if (allEpisodes.isEmpty) {
        allEpisodes = await getEpisodes(seriesId).catchError((_) => <JellyfinItem>[]);
      }
      if (allEpisodes.isEmpty) {
        allEpisodes = await getEpisodesByItems(seriesId).catchError((_) => <JellyfinItem>[]);
      }

      return SeriesData(
        details: details,
        seasons: seasons,
        allEpisodes: allEpisodes,
        similarItems: similarItems,
      );
    }

    // No seasons — fetch episodes + similar in parallel
    final fallbackResults = await Future.wait([
      getEpisodes(seriesId).catchError((_) => <JellyfinItem>[]),
      similarFuture,
    ]);
    allEpisodes = fallbackResults[0];
    final similarItems = fallbackResults[1];

    if (allEpisodes.isEmpty) {
      allEpisodes = await getEpisodesByItems(seriesId).catchError((_) => <JellyfinItem>[]);
    }

    return SeriesData(
      details: details,
      seasons: seasons,
      allEpisodes: allEpisodes,
      similarItems: similarItems,
    );
  }

  Future<String?> findCanonicalSeriesId(String seriesName, {String? excludeId}) async {
    try {
      final libraries = await getLibraries();
      final tvLibs = libraries.where((l) => l.collectionType == 'tvshows').toList();

      // Search all TV libraries in parallel
      final futures = tvLibs.map((lib) async {
        final params = <String, String>{
          'userId': _userId,
          'parentId': lib.id,
          'searchTerm': seriesName,
          'includeItemTypes': 'Series',
          'recursive': 'true',
          'limit': '5',
          'fields': 'PrimaryImageAspectRatio',
        };
        final url = _buildQueryUrl('/Items', params);
        try {
          final data = await _cachedGet(url, ttl: _mediumTtl);
          return _parseItems(data);
        } catch (_) {
          return <JellyfinItem>[];
        }
      });

      final results = await Future.wait(futures);
      for (final items in results) {
        for (final item in items) {
          if (excludeId == null || item.id != excludeId) {
            debugPrint('[Jellyfin] Canonical series found: ${item.name} (${item.id})');
            return item.id;
          }
        }
      }
    } catch (e) {
      debugPrint('[Jellyfin] findCanonicalSeriesId error: $e');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Search
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<JellyfinItem>> search(String query, {int limit = 30}) async {
    final params = <String, String>{
      'userId': _userId,
      'searchTerm': query,
      'recursive': 'true',
      'includeItemTypes': 'Movie,Series,Episode',
      'limit': '$limit',
      'fields': 'Overview,Genres,PrimaryImageAspectRatio',
      'enableImages': 'true',
      'imageTypeLimit': '1',
      'enableImageTypes': 'Primary,Backdrop,Thumb',
    };
    final url = _buildQueryUrl('/Items', params);
    try {
      final data = await _cachedGet(url, ttl: _shortTtl);
      return _parseItems(data);
    } catch (_) {
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PlaybackInfo & Streaming
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, String>?> getPlaybackInfo(String itemId,
      {int startTimeTicks = 0, bool forceTranscode = false}) async {
    try {
      final resp = await _post(
        Uri.parse('$_base/Items/$itemId/PlaybackInfo?userId=$_userId'
            '&StartTimeTicks=$startTimeTicks&isPlayback=true&autoOpenLiveStream=true'
            '&maxStreamingBitrate=150000000'),
        headers: _authHeaders,
        body: json.encode({
          'DeviceProfile': _buildDeviceProfile(),
          'UserId': _userId,
          'EnableDirectPlay': !forceTranscode,
          'EnableDirectStream': !forceTranscode,
          'EnableTranscoding': true,
          'AllowVideoStreamCopy': true,
          'AllowAudioStreamCopy': true,
        }),
      );

      if (resp.statusCode != 200) {
        debugPrint('[Jellyfin] PlaybackInfo error: ${resp.statusCode}');
        return null;
      }

      final data = json.decode(resp.body);
      final playSessionId = data['PlaySessionId'] as String? ?? '';
      final sources = data['MediaSources'] as List<dynamic>?;

      _lastSubtitles = _extractSubtitles(
        sources?.isNotEmpty == true ? sources![0] as Map<String, dynamic> : null,
        itemId,
      );

      if (sources == null || sources.isEmpty) {
        _lastPlaySessionId = playSessionId;
        _lastMediaSourceId = itemId;
        _lastPlayMethod = 'DirectPlay';
        return {'mode': 'direct', 'mediaSourceId': itemId, 'container': 'mp4', 'playSessionId': playSessionId, 'etag': ''};
      }

      final src = sources[0] as Map<String, dynamic>;
      final supportsDirectPlay = src['SupportsDirectPlay'] == true;
      final supportsDirectStream = src['SupportsDirectStream'] == true;
      final transcodingUrl = src['TranscodingUrl'] as String?;
      final msId = src['Id'] as String? ?? itemId;
      final sourcePath = src['Path'] as String? ?? '';

      debugPrint('[Jellyfin] PlaybackInfo: dp=$supportsDirectPlay ds=$supportsDirectStream '
          'path=${sourcePath.startsWith('http') ? 'remote' : 'local'} '
          'transcode=${transcodingUrl != null}');

      if (supportsDirectPlay || supportsDirectStream) {
        if (!forceTranscode && sourcePath.startsWith('http')) {
          debugPrint('[Jellyfin] Remote source → forced transcode');
          return getPlaybackInfo(itemId, startTimeTicks: startTimeTicks, forceTranscode: true);
        }

        _lastPlaySessionId = playSessionId;
        _lastMediaSourceId = msId;
        _lastPlayMethod = supportsDirectPlay ? 'DirectPlay' : 'DirectStream';
        return {
          'mode': 'direct',
          'mediaSourceId': msId,
          'container': (src['Container'] as String? ?? 'mp4').toLowerCase(),
          'playSessionId': playSessionId,
          'etag': src['ETag'] as String? ?? '',
        };
      }

      if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
        final fullUrl = transcodingUrl.startsWith('http') ? transcodingUrl : '$_base$transcodingUrl';
        _lastPlaySessionId = playSessionId;
        _lastMediaSourceId = msId;
        _lastPlayMethod = 'Transcode';
        return {'mode': 'transcode', 'url': fullUrl, 'playSessionId': playSessionId};
      }

      // Fallback
      _lastPlaySessionId = playSessionId;
      _lastMediaSourceId = msId;
      _lastPlayMethod = 'DirectPlay';
      return {
        'mode': 'direct',
        'mediaSourceId': msId,
        'container': (src['Container'] as String? ?? 'mp4').toLowerCase(),
        'playSessionId': playSessionId,
        'etag': src['ETag'] as String? ?? '',
      };
    } catch (e) {
      debugPrint('[Jellyfin] PlaybackInfo exception: $e');
      _lastSubtitles = [];
      return null;
    }
  }

  List<Map<String, dynamic>> _extractSubtitles(Map<String, dynamic>? mediaSource, String itemId) {
    if (mediaSource == null) return [];
    final streams = mediaSource['MediaStreams'] as List<dynamic>? ?? [];
    final msId = mediaSource['Id'] as String? ?? itemId;
    final subs = <Map<String, dynamic>>[];

    for (final s in streams) {
      final stream = s as Map<String, dynamic>;
      if (stream['Type'] != 'Subtitle') continue;
      if (stream['SupportsExternalStream'] != true) continue;

      final isText = stream['IsTextSubtitleStream'] == true;
      final index = stream['Index'] as int? ?? 0;
      final lang = stream['Language'] as String? ?? '';
      final displayTitle = stream['DisplayTitle'] as String? ?? stream['Title'] as String? ?? 'Track $index';
      final codec = (stream['Codec'] as String? ?? '').toLowerCase();
      final isDefault = stream['IsDefault'] == true;
      final isForced = stream['IsForced'] == true;
      final isExternal = stream['IsExternal'] == true;

      final String format;
      if (isText) {
        format = 'srt';
      } else if (codec == 'pgssub' || codec == 'hdmv_pgs_subtitle') {
        format = 'sup';
      } else if (codec == 'dvdsub' || codec == 'dvd_subtitle') {
        format = 'sub';
      } else {
        format = 'srt';
      }

      final parts = <String>[displayTitle];
      if (isDefault) parts.add('[Default]');
      if (isForced) parts.add('[Forced]');
      if (isExternal) parts.add('[External]');

      final directUrl = '$_base/Videos/$itemId/$msId/Subtitles/$index/0/Stream.$format';
      final proxyUrl = LocalServerService().getJellyfinProxyUrl(directUrl, authHeaderValue);

      subs.add({
        'url': proxyUrl,
        'display': parts.join(' '),
        'language': lang,
        'codec': codec,
        'index': index,
        'isDefault': isDefault,
        'isForced': isForced,
      });
    }

    debugPrint('[Jellyfin] Found ${subs.length} subtitle tracks');
    return subs;
  }

  String getSubtitleUrl(String itemId, String mediaSourceId, int subtitleIndex, {String format = 'srt'}) {
    final directUrl = '$_base/Videos/$itemId/$mediaSourceId/Subtitles/$subtitleIndex/0/Stream.$format';
    return LocalServerService().getJellyfinProxyUrl(directUrl, authHeaderValue);
  }

  Map<String, dynamic> _buildDeviceProfile() {
    return {
      'MaxStreamingBitrate': 150000000,
      'MaxStaticBitrate': 150000000,
      'MusicStreamingTranscodingBitrate': 384000,
      'DirectPlayProfiles': [
        {
          'Container': 'mp4,m4v,mkv,mov,avi,ts,m2ts,flv,webm,mpeg,ogv',
          'Type': 'Video',
          'VideoCodec': 'h264,hevc,h265,av1,vp8,vp9,vc1,mpeg2video,mpeg4',
          'AudioCodec': 'aac,mp3,ac3,eac3,dts,truehd,flac,opus,vorbis,pcm_s16le,pcm_s24le',
        },
        {'Container': 'mp3', 'Type': 'Audio'},
        {'Container': 'aac', 'Type': 'Audio'},
        {'Container': 'flac', 'Type': 'Audio'},
        {'Container': 'wav', 'Type': 'Audio'},
        {'Container': 'ogg', 'Type': 'Audio'},
        {'Container': 'opus', 'Type': 'Audio'},
      ],
      'TranscodingProfiles': [
        {
          'Container': 'ts',
          'Type': 'Video',
          'VideoCodec': 'h264',
          'AudioCodec': 'aac,ac3',
          'Context': 'Streaming',
          'Protocol': 'hls',
          'MaxAudioChannels': '6',
          'MinSegments': '2',
          'BreakOnNonKeyFrames': true,
          'EnableAudioVbrEncoding': true,
        },
      ],
      'CodecProfiles': [],
      'SubtitleProfiles': [
        {'Format': 'srt', 'Method': 'External'},
        {'Format': 'ass', 'Method': 'External'},
        {'Format': 'ssa', 'Method': 'External'},
        {'Format': 'vtt', 'Method': 'External'},
        {'Format': 'sub', 'Method': 'External'},
        {'Format': 'subrip', 'Method': 'External'},
        {'Format': 'sup', 'Method': 'External'},
      ],
    };
  }

  String _buildStreamUrl(String itemId, {String? container, String? mediaSourceId, String? etag}) {
    final ext = container ?? 'mp4';
    final msId = mediaSourceId ?? itemId;
    final token = _activeAccount?.accessToken ?? '';

    final params = <String, String>{
      'Static': 'true',
      'mediaSourceId': msId,
      'deviceId': _deviceId,
      'ApiKey': token,
      'api_key': token,
    };
    if (etag != null && etag.isNotEmpty) params['Tag'] = etag;

    return Uri.parse('$_base/Videos/$itemId/stream.$ext').replace(queryParameters: params).toString();
  }

  /// Resolves a stream URL — handles direct-play validation and transcode fallback.
  /// Returns the URL and whether the stream is transcoded (so callers know
  /// not to pass a seek position — the server already starts at the offset).
  Future<({String url, bool isTranscode})> _resolveStreamUrl(String itemId, {int startTimeTicks = 0}) async {
    final info = await getPlaybackInfo(itemId, startTimeTicks: startTimeTicks);
    final proxy = LocalServerService();

    if (info?['mode'] == 'transcode' && info?['url'] != null) {
      return (url: proxy.getJellyfinProxyUrl(info!['url']!, authHeaderValue), isTranscode: true);
    }

    final directUrl = _buildStreamUrl(
      itemId,
      container: info?['container'],
      mediaSourceId: info?['mediaSourceId'],
      etag: info?['etag'],
    );

    final valid = await _validateStreamUrl(directUrl);
    if (!valid) {
      debugPrint('[Jellyfin] Direct URL invalid → transcode fallback');
      final transInfo = await getPlaybackInfo(itemId,
          startTimeTicks: startTimeTicks, forceTranscode: true);
      if (transInfo?['mode'] == 'transcode' && transInfo?['url'] != null) {
        return (url: proxy.getJellyfinProxyUrl(transInfo!['url']!, authHeaderValue), isTranscode: true);
      }
    }

    return (url: proxy.getJellyfinProxyUrl(directUrl, authHeaderValue), isTranscode: false);
  }

  Future<({String url, bool isTranscode})> getStreamUrl(String itemId) => _resolveStreamUrl(itemId);

  Future<({String url, bool isTranscode})> getStreamUrlWithResume(String itemId, int positionTicks) =>
      _resolveStreamUrl(itemId, startTimeTicks: positionTicks);

  Future<bool> _validateStreamUrl(String url) async {
    try {
      final resp = await _request('HEAD', Uri.parse(url),
          headers: _authHeaders, timeout: const Duration(seconds: 8), maxRetries: 0);
      if (resp.statusCode >= 400) {
        debugPrint('[Jellyfin] Stream validation failed: ${resp.statusCode}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[Jellyfin] Stream validation error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Image URLs
  // ═══════════════════════════════════════════════════════════════════════════

  String getImageUrl(String itemId, {
    String type = 'Primary',
    String? tag,
    int? maxWidth,
    int quality = 90,
    int imageIndex = 0,
  }) {
    final token = _activeAccount?.accessToken ?? '';
    var url = '$_base/Items/$itemId/Images/$type';
    if (type == 'Backdrop') url += '/$imageIndex';
    url += '?quality=$quality&api_key=$token';
    if (tag != null) url += '&tag=$tag';
    if (maxWidth != null) url += '&maxWidth=$maxWidth';
    return url;
  }

  String getPosterUrl(String itemId, {String? tag, int maxWidth = 400}) =>
      getImageUrl(itemId, type: 'Primary', tag: tag, maxWidth: maxWidth);

  String getBackdropUrl(String itemId, {String? tag, int maxWidth = 1920}) =>
      getImageUrl(itemId, type: 'Backdrop', tag: tag, maxWidth: maxWidth);

  // ═══════════════════════════════════════════════════════════════════════════
  // Playback Reporting
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> reportPlaybackStart(String itemId) async {
    try {
      await _post(
        Uri.parse('$_base/Sessions/Playing'),
        headers: _authHeaders,
        body: json.encode({
          'ItemId': itemId,
          'MediaSourceId': _lastMediaSourceId.isNotEmpty ? _lastMediaSourceId : itemId,
          'PlaySessionId': _lastPlaySessionId,
          'PlayMethod': _lastPlayMethod,
          'CanSeek': true,
          'RepeatMode': 'RepeatNone',
        }),
      );
    } catch (e) {
      debugPrint('[Jellyfin] Report start error: $e');
    }
  }

  Future<void> reportPlaybackProgress(String itemId, int positionTicks, {bool isPaused = false}) async {
    try {
      await _post(
        Uri.parse('$_base/Sessions/Playing/Progress'),
        headers: _authHeaders,
        body: json.encode({
          'ItemId': itemId,
          'MediaSourceId': _lastMediaSourceId.isNotEmpty ? _lastMediaSourceId : itemId,
          'PlaySessionId': _lastPlaySessionId,
          'PositionTicks': positionTicks,
          'IsPaused': isPaused,
          'PlayMethod': _lastPlayMethod,
          'RepeatMode': 'RepeatNone',
          'CanSeek': true,
        }),
      );
    } catch (e) {
      debugPrint('[Jellyfin] Report progress error: $e');
    }
  }

  Future<void> reportPlaybackStopped(String itemId, int positionTicks) async {
    try {
      await _post(
        Uri.parse('$_base/Sessions/Playing/Stopped'),
        headers: _authHeaders,
        body: json.encode({
          'ItemId': itemId,
          'MediaSourceId': _lastMediaSourceId.isNotEmpty ? _lastMediaSourceId : itemId,
          'PlaySessionId': _lastPlaySessionId,
          'PositionTicks': positionTicks,
          'PlayMethod': _lastPlayMethod,
        }),
      );
    } catch (e) {
      debugPrint('[Jellyfin] Report stop error: $e');
    }
  }

  Future<void> markPlayed(String itemId) async {
    try {
      await _post(Uri.parse('$_base/UserPlayedItems/$itemId?userId=$_userId'), headers: _authHeaders);
      _invalidateItem(itemId);
    } catch (e) {
      debugPrint('[Jellyfin] Mark played error: $e');
    }
  }

  Future<void> markUnplayed(String itemId) async {
    try {
      await _delete(Uri.parse('$_base/UserPlayedItems/$itemId?userId=$_userId'), headers: _authHeaders);
      _invalidateItem(itemId);
    } catch (e) {
      debugPrint('[Jellyfin] Mark unplayed error: $e');
    }
  }

  Future<void> toggleFavorite(String itemId, bool isFavorite) async {
    try {
      if (isFavorite) {
        await _delete(Uri.parse('$_base/UserFavoriteItems/$itemId?userId=$_userId'), headers: _authHeaders);
      } else {
        await _post(Uri.parse('$_base/UserFavoriteItems/$itemId?userId=$_userId'), headers: _authHeaders);
      }
      _invalidateItem(itemId);
    } catch (e) {
      debugPrint('[Jellyfin] Toggle favorite error: $e');
    }
  }

  /// Removes cached data for a specific item so the next fetch returns fresh state.
  void _invalidateItem(String itemId) {
    _cache.removeWhere((key, _) => key.contains(itemId));
  }

  /// Clears playback-related cache (resume, nextUp) so the home screen
  /// shows fresh data after returning from the player.
  void invalidatePlaybackCache() {
    _cache.removeWhere((key, _) =>
        key.contains('/UserItems/Resume') || key.contains('/Shows/NextUp'));
  }
}
