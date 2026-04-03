import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/local_server_service.dart';
import '../platform_flags.dart';

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
      url = 'https://$url'; // default to https
    }
    return url.replaceAll(RegExp(r'/+$'), '');
  }
}

/// Lightweight model for a Jellyfin media item.
class JellyfinItem {
  final String id;
  final String name;
  final String type; // Movie, Series, Season, Episode, ...
  final String? overview;
  final int? productionYear;
  final double? communityRating;
  final String? officialRating;
  final int? runTimeTicks;
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final int? indexNumber;       // episode number or season number
  final int? parentIndexNumber; // season number for episodes
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

  /// Formatted runtime string (e.g. "2h 15m")
  String get runtime {
    if (runTimeTicks == null) return '';
    final minutes = (runTimeTicks! / 600000000).round();
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  /// Percentage of playback completed (0.0 – 1.0)
  double get playbackProgress {
    if (userData == null || runTimeTicks == null || runTimeTicks == 0) return 0;
    final pos = userData!['PlaybackPositionTicks'] as int? ?? 0;
    return (pos / runTimeTicks!).clamp(0.0, 1.0);
  }

  bool get isPlayed => userData?['Played'] == true;
  bool get isFavorite => userData?['IsFavorite'] == true;
  int get unplayedCount => userData?['UnplayedItemCount'] as int? ?? 0;
}

/// Service for communicating with a Jellyfin server.
class JellyfinService {
  static final JellyfinService _instance = JellyfinService._internal();
  factory JellyfinService() => _instance;
  JellyfinService._internal();

  static const String _accountsKey = 'jellyfin_accounts';
  static const String _activeAccountKey = 'jellyfin_active_account';

  /// HTTP client that follows redirects (including 308 on POST).
  late final HttpClient _ioClient = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;

  /// Performs an HTTP request following all redirects (301/302/307/308).
  /// Returns the final response. Works for GET, POST, HEAD, etc.
  Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    var currentUri = uri;
    const maxRedirects = 5;

    for (var i = 0; i <= maxRedirects; i++) {
      final ioReq = await _ioClient.openUrl(method, currentUri).timeout(timeout);
      ioReq.followRedirects = false; // we handle manually

      // Set headers
      headers?.forEach((k, v) => ioReq.headers.set(k, v));

      // Write body for POST/PUT
      if (body != null && (method == 'POST' || method == 'PUT')) {
        ioReq.write(body);
      }

      final ioResp = await ioReq.close().timeout(timeout);
      final statusCode = ioResp.statusCode;

      // Handle redirects
      if (statusCode >= 300 && statusCode < 400) {
        final location = ioResp.headers.value('location');
        if (location == null) break;
        await ioResp.drain<void>();
        currentUri = Uri.parse(location);
        debugPrint('[Jellyfin] Redirect $statusCode → $currentUri');
        continue;
      }

      // Read response body
      final respBody = await ioResp.transform(utf8.decoder).join();
      final respHeaders = <String, String>{};
      ioResp.headers.forEach((name, values) {
        respHeaders[name] = values.join(', ');
      });

      return http.Response(respBody, statusCode, headers: respHeaders);
    }

    throw Exception('Too many redirects');
  }

  /// Shorthand GET.
  Future<http.Response> _get(Uri uri, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 15)}) =>
      _request('GET', uri, headers: headers, timeout: timeout);

  /// Shorthand POST.
  Future<http.Response> _post(Uri uri, {Map<String, String>? headers, String? body, Duration timeout = const Duration(seconds: 15)}) =>
      _request('POST', uri, headers: headers, body: body, timeout: timeout);

  /// Shorthand DELETE.
  Future<http.Response> _delete(Uri uri, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 15)}) =>
      _request('DELETE', uri, headers: headers, timeout: timeout);

  JellyfinAccount? _activeAccount;
  JellyfinAccount? get activeAccount => _activeAccount;
  bool get isLoggedIn => _activeAccount?.accessToken != null;

  final String _deviceId = 'playtorrio_${DateTime.now().millisecondsSinceEpoch}';

  /// Subtitles from the last PlaybackInfo call.
  List<Map<String, dynamic>> _lastSubtitles = [];

  // Stored from the last successful PlaybackInfo call — used in progress reporting
  String _lastPlaySessionId = '';
  String _lastMediaSourceId = '';
  String _lastPlayMethod = 'DirectPlay'; // 'DirectPlay', 'DirectStream', or 'Transcode'
  List<Map<String, dynamic>> get lastSubtitles => _lastSubtitles;

  // ═══════════════════════════════════════════════════════════════════════════
  // Auth Headers
  // ═══════════════════════════════════════════════════════════════════════════

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

  /// Public getter for the auth header value (used by proxy & player headers).
  String get authHeaderValue => _authHeaders['X-Emby-Authorization'] ?? '';

  /// Returns auth headers map suitable for player httpHeaders.
  Map<String, String> get streamHeaders => {
    'X-Emby-Authorization': authHeaderValue,
  };

  String get _base => _activeAccount?.normalizedUrl ?? '';
  String get _userId => _activeAccount?.userId ?? '';

  // ═══════════════════════════════════════════════════════════════════════════
  // Account Persistence
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<JellyfinAccount>> getSavedAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_accountsKey) ?? [];
    return list.map((s) => JellyfinAccount.fromJson(json.decode(s))).toList();
  }

  Future<void> _saveAccounts(List<JellyfinAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _accountsKey,
      accounts.map((a) => json.encode(a.toJson())).toList(),
    );
  }

  Future<void> _setActiveIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeAccountKey, index);
  }

  /// Loads the previously active account (called on app start).
  Future<bool> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await getSavedAccounts();
    final idx = prefs.getInt(_activeAccountKey) ?? -1;
    if (idx >= 0 && idx < accounts.length) {
      _activeAccount = accounts[idx];
      if (_activeAccount!.accessToken != null) {
        // Verify the token is still valid
        try {
          final resp = await _get(
              Uri.parse('$_base/Users/Me'),
              headers: _authHeaders,
              timeout: const Duration(seconds: 5));
          if (resp.statusCode == 200) {
            debugPrint('[Jellyfin] Restored session for ${_activeAccount!.username}');
            return true;
          }
        } catch (_) {}
        // Token invalid — re-login
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

  /// Authenticate and get access token. Throws on failure.
  Future<bool> login(String serverUrl, String username, String password) async {
    _activeAccount = JellyfinAccount(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );

    final resp = await _post(
          Uri.parse('$_base/Users/AuthenticateByName'),
          headers: _authHeaders,
          body: json.encode({'Username': username, 'Pw': password}),
          timeout: const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      _activeAccount = null;
      throw Exception('Login failed (${resp.statusCode}): ${resp.body}');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    _activeAccount!.accessToken = data['AccessToken'] as String;
    _activeAccount!.userId = (data['User'] as Map<String, dynamic>)['Id'] as String;
    _activeAccount!.serverName = data['ServerId'] as String?;

    // Persist
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeAccountKey);
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
    final resp = await _get(
        Uri.parse('$_base/UserViews?userId=$_userId'),
        headers: _authHeaders);
    if (resp.statusCode != 200) throw Exception('Failed to fetch libraries');
    final data = json.decode(resp.body);
    return (data['Items'] as List<dynamic>)
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();
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
    String fields =
        'Overview,Genres,PrimaryImageAspectRatio,MediaStreams,Container',
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

    final uri = Uri.parse('$_base/Items').replace(queryParameters: params);
    final resp = await _get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) throw Exception('Failed to fetch items');
    final data = json.decode(resp.body);
    return (data['Items'] as List<dynamic>)
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Like [getItems] but also returns the server-side [totalCount] so the
  /// caller can implement pagination with prev/next buttons.
  Future<({List<JellyfinItem> items, int totalCount})> getItemsPaged({
    String? parentId,
    String? includeItemTypes,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    int startIndex = 0,
    int limit = 50,
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
      'limit': '$limit',
      'fields': fields,
      'enableImageTypes': 'Primary,Backdrop,Thumb',
      'imageTypeLimit': '1',
      'enableTotalRecordCount': 'true',
    };
    if (parentId != null) params['parentId'] = parentId;
    if (includeItemTypes != null) params['includeItemTypes'] = includeItemTypes;
    if (searchTerm != null && searchTerm.isNotEmpty) params['searchTerm'] = searchTerm;

    final uri = Uri.parse('$_base/Items').replace(queryParameters: params);
    final resp = await _get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) throw Exception('Failed to fetch items: ${resp.statusCode}');
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final items = (data['Items'] as List<dynamic>)
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (data['TotalRecordCount'] as num?)?.toInt() ?? items.length;
    return (items: items, totalCount: total);
  }

  Future<JellyfinItem> getItemDetails(String itemId) async {
    final resp = await _get(
          Uri.parse('$_base/Items/$itemId?userId=$_userId'),
          headers: _authHeaders);
    if (resp.statusCode != 200) throw Exception('Failed to fetch item details');
    return JellyfinItem.fromJson(json.decode(resp.body));
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

    final uri = Uri.parse('$_base/Items/Latest').replace(queryParameters: params);
    final resp = await _get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) throw Exception('Failed to fetch latest items');
    final list = json.decode(resp.body) as List<dynamic>;
    return list.map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>)).toList();
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
    final uri = Uri.parse('$_base/UserItems/Resume').replace(queryParameters: params);
    final resp = await _get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return (data['Items'] as List<dynamic>)
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<JellyfinItem>> getNextUp({int limit = 20}) async {
    final params = <String, String>{
      'userId': _userId,
      'limit': '$limit',
      'fields': 'Overview,Genres,PrimaryImageAspectRatio',
      'enableImages': 'true',
      'enableImageTypes': 'Primary,Backdrop,Thumb',
    };
    final uri = Uri.parse('$_base/Shows/NextUp').replace(queryParameters: params);
    final resp = await _get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return (data['Items'] as List<dynamic>)
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TV Shows — Seasons & Episodes
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<JellyfinItem>> getSeasons(String seriesId) async {
    final resp = await _get(
          Uri.parse('$_base/Shows/$seriesId/Seasons?userId=$_userId'
              '&fields=Overview,PrimaryImageAspectRatio'),
          headers: _authHeaders);
    if (resp.statusCode != 200) throw Exception('Failed to fetch seasons');
    final data = json.decode(resp.body);
    return (data['Items'] as List<dynamic>)
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<JellyfinItem>> getEpisodes(String seriesId, {String? seasonId, int? seasonNumber}) async {
    final params = <String, String>{
      'userId': _userId,
      'fields': 'Overview,PrimaryImageAspectRatio,MediaStreams,Container,ParentIndexNumber,IndexNumber',
    };
    if (seasonId != null) params['seasonId'] = seasonId;
    if (seasonNumber != null) params['season'] = '$seasonNumber';

    final uri = Uri.parse('$_base/Shows/$seriesId/Episodes').replace(queryParameters: params);
    final resp = await _get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) throw Exception('Failed to fetch episodes: ${resp.statusCode}');
    final data = json.decode(resp.body);
    return (data['Items'] as List<dynamic>)
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fallback episode fetch using /Items endpoint with seriesId filter.
  /// Used when /Shows/{id}/Episodes returns empty for plugin-backed shows.
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
    final uri = Uri.parse('$_base/Items').replace(queryParameters: params);
    final resp = await _get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) throw Exception('Failed to fetch episodes via Items: ${resp.statusCode}');
    final data = json.decode(resp.body);
    return (data['Items'] as List<dynamic>)
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Searches tvshows libraries for a Series by name and returns the canonical
  /// item ID — i.e. the one that belongs to a proper TV library with season
  /// metadata. Used as fallback when an item found via global search is a
  /// virtual/plugin copy that lacks season/episode hierarchy.
  Future<String?> findCanonicalSeriesId(String seriesName, {String? excludeId}) async {
    try {
      final libraries = await getLibraries();
      final tvLibs = libraries.where((l) => l.collectionType == 'tvshows').toList();
      for (final lib in tvLibs) {
        final params = <String, String>{
          'userId': _userId,
          'parentId': lib.id,
          'searchTerm': seriesName,
          'includeItemTypes': 'Series',
          'recursive': 'true',
          'limit': '5',
          'fields': 'PrimaryImageAspectRatio',
        };
        final uri = Uri.parse('$_base/Items').replace(queryParameters: params);
        final resp = await _get(uri, headers: _authHeaders);
        if (resp.statusCode != 200) continue;
        final data = json.decode(resp.body);
        final items = (data['Items'] as List<dynamic>)
            .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
            .toList();
        for (final item in items) {
          if (excludeId == null || item.id != excludeId) {
            debugPrint('[Jellyfin] Canonical series found in library "${lib.name}": '
                '${item.name} (${item.id})');
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
    final uri = Uri.parse('$_base/Items').replace(queryParameters: params);
    final resp = await _get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return (data['Items'] as List<dynamic>)
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PlaybackInfo & Streaming URL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calls POST /Items/{id}/PlaybackInfo to register a playback session.
  /// [startTimeTicks] bakes the resume offset into the returned HLS URL.
  /// [forceTranscode] skips direct play/stream entirely — used when the first
  /// attempt returned a direct-play URL that turned out to be inaccessible
  /// (e.g. AIOstreams/debrid sources where the Jellyfin server can't serve
  /// the file statically because it's a remote HTTP URL).
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
          // When forceTranscode=true, tell server to skip direct play entirely.
          // This makes it return only a TranscodingUrl — used for remote HTTP
          // sources (AIOstreams, debrid) where Static=true returns 403.
          'EnableDirectPlay': !forceTranscode,
          'EnableDirectStream': !forceTranscode,
          'EnableTranscoding': true,
          'AllowVideoStreamCopy': true,
          'AllowAudioStreamCopy': true,
        }),
      );

      if (resp.statusCode != 200) {
        debugPrint('[Jellyfin] PlaybackInfo error: ${resp.statusCode} ${resp.body}');
        return null;
      }

      final data = json.decode(resp.body);
      final playSessionId = data['PlaySessionId'] as String? ?? '';
      final sources = data['MediaSources'] as List<dynamic>?;

      // Extract subtitles from MediaStreams
      _lastSubtitles = _extractSubtitles(
        sources?.isNotEmpty == true ? sources![0] as Map<String, dynamic> : null,
        itemId,
      );

      if (sources != null && sources.isNotEmpty) {
        final src = sources[0] as Map<String, dynamic>;
        final supportsDirectPlay = src['SupportsDirectPlay'] == true;
        final supportsDirectStream = src['SupportsDirectStream'] == true;
        final transcodingUrl = src['TranscodingUrl'] as String?;
        final msId = src['Id'] as String? ?? itemId;
        final sourcePath = src['Path'] as String? ?? '';

        debugPrint('[Jellyfin] PlaybackInfo: directPlay=$supportsDirectPlay, '
            'directStream=$supportsDirectStream, '
            'path=${sourcePath.startsWith('http') ? '[remote]' : '[local]'}, '
            'transcodingUrl=${transcodingUrl != null ? "present" : "null"}');

        if (supportsDirectPlay || supportsDirectStream) {
          // If the source file path is a remote HTTP URL (AIOstreams, debrid, etc.)
          // the Jellyfin server cannot serve it with Static=true — it would 403.
          // Retry with direct play disabled to get a working TranscodingUrl instead.
          if (!forceTranscode && sourcePath.startsWith('http')) {
            debugPrint('[Jellyfin] Remote source path detected — retrying with forced transcode');
            return getPlaybackInfo(itemId,
                startTimeTicks: startTimeTicks, forceTranscode: true);
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
        } else if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
          // Server requires transcoding — use the HLS URL it gave us
          final fullUrl = transcodingUrl.startsWith('http')
              ? transcodingUrl
              : '$_base$transcodingUrl';
          _lastPlaySessionId = playSessionId;
          _lastMediaSourceId = msId;
          _lastPlayMethod = 'Transcode';
          debugPrint('[Jellyfin] Using transcoding URL');
          return {
            'mode': 'transcode',
            'url': fullUrl,
            'playSessionId': playSessionId,
          };
        }

        // Fallback to direct attempt
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
      }
      _lastPlaySessionId = playSessionId;
      _lastMediaSourceId = itemId;
      _lastPlayMethod = 'DirectPlay';
      return {'mode': 'direct', 'mediaSourceId': itemId, 'container': 'mp4', 'playSessionId': playSessionId, 'etag': ''};
    } catch (e) {
      debugPrint('[Jellyfin] PlaybackInfo exception: $e');
      _lastSubtitles = [];
      return null;
    }
  }

  /// Extracts subtitle tracks from a MediaSource that can be delivered as
  /// external streams, and returns them in the format used by the player:
  /// [{url, display, language}].
  ///
  /// Includes both text-based subs (SRT/ASS → requested as .srt) and
  /// image-based subs that support external delivery (PGSSUB → .sup,
  /// DVDSUB → .sub), since mpv/media_kit handles all of these natively.
  List<Map<String, dynamic>> _extractSubtitles(
    Map<String, dynamic>? mediaSource,
    String itemId,
  ) {
    if (mediaSource == null) return [];
    final streams = mediaSource['MediaStreams'] as List<dynamic>? ?? [];
    final msId = mediaSource['Id'] as String? ?? itemId;
    final subs = <Map<String, dynamic>>[];

    for (final s in streams) {
      final stream = s as Map<String, dynamic>;
      if (stream['Type'] != 'Subtitle') continue;

      final supportsExternal = stream['SupportsExternalStream'] == true;
      if (!supportsExternal) continue; // Only include deliverable tracks

      final isText = stream['IsTextSubtitleStream'] == true;
      final index = stream['Index'] as int? ?? 0;
      final lang = stream['Language'] as String? ?? '';
      final displayTitle = stream['DisplayTitle'] as String? ?? stream['Title'] as String? ?? 'Track $index';
      final codec = (stream['Codec'] as String? ?? '').toLowerCase();
      final isDefault = stream['IsDefault'] == true;
      final isForced = stream['IsForced'] == true;
      final isExternal = stream['IsExternal'] == true;

      // Determine the best format extension for this subtitle type
      final String format;
      if (isText) {
        format = 'srt'; // Request SRT conversion for all text subs
      } else if (codec == 'pgssub' || codec == 'hdmv_pgs_subtitle') {
        format = 'sup'; // PGS image subtitle (blu-ray)
      } else if (codec == 'dvdsub' || codec == 'dvd_subtitle') {
        format = 'sub'; // DVD image subtitle
      } else {
        format = 'srt'; // Fallback
      }

      // Build display label
      final parts = <String>[displayTitle];
      if (isDefault) parts.add('[Default]');
      if (isForced) parts.add('[Forced]');
      if (isExternal) parts.add('[External]');

      // Build subtitle URL and route through proxy for auth
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

    debugPrint('[Jellyfin] Found ${subs.length} deliverable subtitle tracks');
    return subs;
  }

  /// Returns a subtitle URL for a specific track index and format.
  String getSubtitleUrl(String itemId, String mediaSourceId, int subtitleIndex, {String format = 'srt'}) {
    final directUrl = '$_base/Videos/$itemId/$mediaSourceId/Subtitles/$subtitleIndex/0/Stream.$format';
    return LocalServerService().getJellyfinProxyUrl(directUrl, authHeaderValue);
  }

  /// DeviceProfile matching jellyfin-web capabilities.
  /// Wide DirectPlay support to avoid unnecessary transcoding.
  /// HLS TranscodingProfile uses TS segments (standard) with BreakOnNonKeyFrames
  /// and MinSegments=2 for proper buffering and seeking.
  Map<String, dynamic> _buildDeviceProfile() {
    return {
      'MaxStreamingBitrate': 150000000,
      'MaxStaticBitrate': 150000000,
      'MusicStreamingTranscodingBitrate': 384000,
      'DirectPlayProfiles': [
        // Video — wide codec support to maximise direct play
        {
          'Container': 'mp4,m4v,mkv,mov,avi,ts,m2ts,flv,webm,mpeg,ogv',
          'Type': 'Video',
          'VideoCodec': 'h264,hevc,h265,av1,vp8,vp9,vc1,mpeg2video,mpeg4',
          'AudioCodec': 'aac,mp3,ac3,eac3,dts,truehd,flac,opus,vorbis,pcm_s16le,pcm_s24le'
        },
        // Audio
        {'Container': 'mp3', 'Type': 'Audio'},
        {'Container': 'aac', 'Type': 'Audio'},
        {'Container': 'flac', 'Type': 'Audio'},
        {'Container': 'wav', 'Type': 'Audio'},
        {'Container': 'ogg', 'Type': 'Audio'},
        {'Container': 'opus', 'Type': 'Audio'},
      ],
      'TranscodingProfiles': [
        {
          // TS segments (standard HLS — 'mp4' causes compat issues on many servers)
          'Container': 'ts',
          'Type': 'Video',
          'VideoCodec': 'h264',             // h264 is universally supported for HLS
          'AudioCodec': 'aac,ac3',
          'Context': 'Streaming',
          'Protocol': 'hls',
          'MaxAudioChannels': '6',
          'MinSegments': '2',               // 2+ for proper buffering
          'BreakOnNonKeyFrames': true,       // required for accurate HLS seeking
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

  /// Builds the direct-play/direct-stream URL matching the format used by jellyfin-web:
  ///   /Videos/{id}/stream.{container}?Static=true&mediaSourceId={msId}&deviceId={did}&ApiKey={token}
  ///
  /// Note: Do NOT add startTimeTicks here — it's not valid for Static=true streams.
  /// Seeking is handled natively via HTTP Range requests by the player.
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

    final uri = Uri.parse('$_base/Videos/$itemId/stream.$ext').replace(queryParameters: params);
    return uri.toString();
  }

  /// Returns the stream URL (direct play or transcoded HLS).
  /// Calls PlaybackInfo first; if server requires transcoding, uses the
  /// transcoding URL it provides; otherwise builds a direct-play URL.
  Future<String> getStreamUrl(String itemId) async {
    final info = await getPlaybackInfo(itemId);

    if (info?['mode'] == 'transcode' && info?['url'] != null) {
      final transUrl = info!['url']!;
      debugPrint('[Jellyfin] Stream URL (transcode): $transUrl');
      return LocalServerService().getJellyfinProxyUrl(transUrl, authHeaderValue);
    }

    final directUrl = _buildStreamUrl(
      itemId,
      container: info?['container'],
      mediaSourceId: info?['mediaSourceId'],
      etag: info?['etag'],
    );
    debugPrint('[Jellyfin] Stream URL (direct): $directUrl');
    return LocalServerService().getJellyfinProxyUrl(directUrl, authHeaderValue);
  }

  /// Returns the stream URL with a resume position.
  ///
  /// For HLS transcoded streams, StartTimeTicks must be passed to PlaybackInfo
  /// so the server generates an M3U8 with the offset already baked in.
  /// For direct streams, native HTTP Range seeking handles position automatically.
  Future<String> getStreamUrlWithResume(String itemId, int positionTicks) async {
    // Pass startTimeTicks to PlaybackInfo — the server bakes the offset into
    // the returned HLS URL so segment numbering starts at the right position.
    final info = await getPlaybackInfo(itemId, startTimeTicks: positionTicks);

    if (info?['mode'] == 'transcode' && info?['url'] != null) {
      // The TranscodingUrl already contains StartTimeTicks — use it as-is.
      final transUrl = info!['url']!;
      debugPrint('[Jellyfin] Stream URL (transcode+resume @$positionTicks): $transUrl');
      return LocalServerService().getJellyfinProxyUrl(transUrl, authHeaderValue);
    }

    // Direct stream — Static=true; Range header handles seeking natively.
    // Do NOT pass startTimeTicks here; it's not valid for Static streams.
    final directUrl = _buildStreamUrl(
      itemId,
      container: info?['container'],
      mediaSourceId: info?['mediaSourceId'],
      etag: info?['etag'],
    );
    debugPrint('[Jellyfin] Stream URL (direct+resume): $directUrl');
    return LocalServerService().getJellyfinProxyUrl(directUrl, authHeaderValue);
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
  // Playback Reporting (sync watch state back to Jellyfin)
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
      await _post(
        Uri.parse('$_base/UserPlayedItems/$itemId?userId=$_userId'),
        headers: _authHeaders,
      );
    } catch (e) {
      debugPrint('[Jellyfin] Mark played error: $e');
    }
  }

  Future<void> markUnplayed(String itemId) async {
    try {
      await _delete(
        Uri.parse('$_base/UserPlayedItems/$itemId?userId=$_userId'),
        headers: _authHeaders,
      );
    } catch (e) {
      debugPrint('[Jellyfin] Mark unplayed error: $e');
    }
  }

  Future<void> toggleFavorite(String itemId, bool isFavorite) async {
    try {
      if (isFavorite) {
        await _delete(
          Uri.parse('$_base/UserFavoriteItems/$itemId?userId=$_userId'),
          headers: _authHeaders,
        );
      } else {
        await _post(
          Uri.parse('$_base/UserFavoriteItems/$itemId?userId=$_userId'),
          headers: _authHeaders,
        );
      }
    } catch (e) {
      debugPrint('[Jellyfin] Toggle favorite error: $e');
    }
  }
}
