import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/my_list_service.dart';
import '../services/watch_history_service.dart';

/// Full Trakt.tv integration — OAuth device-code auth, watchlist sync,
/// scrobble, playback progress, and two-way import/export.
class TraktService {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final TraktService _instance = TraktService._internal();
  factory TraktService() => _instance;
  TraktService._internal();

  // ── Constants ──────────────────────────────────────────────────────────
  static const String _baseUrl = 'https://api.trakt.tv';

  // Register your own app at https://trakt.tv/oauth/applications/new
  // Redirect URI should be "urn:ietf:wg:oauth:2.0:oob" for device flow.
  static const String _clientId =
      '80854d1799a6a7e160a458857982867b119230ff49c502e0241e283897b1c0f6';
  static const String _clientSecret =
      '88597426e493551e2efa4b73aeddb5b2dfc1c58777a3a979124c43d12856db59';

  // ── Secure Storage Keys ────────────────────────────────────────────────
  static const String _keyAccessToken = 'trakt_access_token';
  static const String _keyRefreshToken = 'trakt_refresh_token';
  static const String _keyExpiresAt = 'trakt_expires_at';

  final _storage = const FlutterSecureStorage();

  /// Fires when login state changes so the UI can rebuild.
  static final ValueNotifier<bool> loginNotifier = ValueNotifier<bool>(false);

  // Track whether we've already done an initial sync this session
  bool _initialSyncDone = false;

  // ═══════════════════════════════════════════════════════════════════════
  //  A U T H   —   D E V I C E   C O D E   F L O W
  // ═══════════════════════════════════════════════════════════════════════

  /// Step 1 — request a device code + user_code.
  /// Returns the API response map or null on failure.
  Future<Map<String, dynamic>?> startDeviceAuth() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/oauth/device/code'),
        headers: _publicHeaders,
        body: json.encode({'client_id': _clientId}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      debugPrint('[Trakt] Device code request failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('[Trakt] Device code error: $e');
    }
    return null;
  }

  /// Step 2 — poll for the token after user enters the code.
  /// Returns:
  ///   'success'  — tokens saved, good to go
  ///   'pending'  — user hasn't authorized yet
  ///   'expired'  — code expired
  ///   'denied'   — user denied
  ///   'error'    — unexpected failure
  Future<String> pollForToken(String deviceCode) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/oauth/device/token'),
        headers: _publicHeaders,
        body: json.encode({
          'code': deviceCode,
          'client_id': _clientId,
          'client_secret': _clientSecret,
        }),
      );
      switch (response.statusCode) {
        case 200:
          final data = json.decode(response.body) as Map<String, dynamic>;
          await _saveTokens(data);
          loginNotifier.value = true;
          return 'success';
        case 400:
          return 'pending';
        case 404:
        case 409:
        case 410:
          return 'expired';
        case 418:
          return 'denied';
        case 429:
          return 'pending'; // slow down — caller already uses interval
        default:
          debugPrint('[Trakt] Poll unexpected status: ${response.statusCode}');
          return 'error';
      }
    } catch (e) {
      debugPrint('[Trakt] Poll error: $e');
      return 'error';
    }
  }

  /// Refresh the access token using the saved refresh token.
  Future<bool> refreshToken() async {
    final refreshToken = await _storage.read(key: _keyRefreshToken);
    if (refreshToken == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/oauth/token'),
        headers: _publicHeaders,
        body: json.encode({
          'refresh_token': refreshToken,
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'redirect_uri': 'urn:ietf:wg:oauth:2.0:oob',
          'grant_type': 'refresh_token',
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        await _saveTokens(data);
        debugPrint('[Trakt] Token refreshed successfully');
        return true;
      }
      debugPrint('[Trakt] Token refresh failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('[Trakt] Token refresh error: $e');
    }
    return false;
  }

  /// Revoke the current token and clear storage.
  Future<void> logout() async {
    final token = await _storage.read(key: _keyAccessToken);
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$_baseUrl/oauth/revoke'),
          headers: _publicHeaders,
          body: json.encode({
            'token': token,
            'client_id': _clientId,
            'client_secret': _clientSecret,
          }),
        );
      } catch (_) {} // best-effort
    }
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyExpiresAt);
    _initialSyncDone = false;
    loginNotifier.value = false;
    debugPrint('[Trakt] Logged out');
  }

  /// Whether the user is currently logged in.
  Future<bool> isLoggedIn() async {
    final token = await _getValidToken();
    return token != null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  W A T C H L I S T   ↔   M Y   L I S T
  // ═══════════════════════════════════════════════════════════════════════

  /// Pull the user's Trakt watchlist and merge into local My List.
  Future<int> importWatchlistToMyList() async {
    final token = await _getValidToken();
    if (token == null) return 0;

    int imported = 0;

    try {
      // Fetch movies watchlist
      final moviesResp = await http.get(
        Uri.parse('$_baseUrl/sync/watchlist/movies?extended=full'),
        headers: _authHeaders(token),
      );
      if (moviesResp.statusCode == 200) {
        final List movies = json.decode(moviesResp.body);
        for (final entry in movies) {
          final movie = entry['movie'] as Map<String, dynamic>?;
          if (movie == null) continue;
          final ids = movie['ids'] as Map<String, dynamic>? ?? {};
          final tmdbId = ids['tmdb'] as int?;
          if (tmdbId == null) continue;

          final uid = MyListService.movieId(tmdbId, 'movie');
          if (!MyListService().contains(uid)) {
            final poster = await _fetchTmdbPoster(tmdbId, 'movie');
            await MyListService().addMovie(
              tmdbId: tmdbId,
              imdbId: ids['imdb']?.toString(),
              title: movie['title']?.toString() ?? 'Unknown',
              posterPath: poster,
              mediaType: 'movie',
              voteAverage: (movie['rating'] as num?)?.toDouble() ?? 0,
              releaseDate: movie['released']?.toString() ?? '',
            );
            imported++;
          }
        }
      }

      // Fetch shows watchlist
      final showsResp = await http.get(
        Uri.parse('$_baseUrl/sync/watchlist/shows?extended=full'),
        headers: _authHeaders(token),
      );
      if (showsResp.statusCode == 200) {
        final List shows = json.decode(showsResp.body);
        for (final entry in shows) {
          final show = entry['show'] as Map<String, dynamic>?;
          if (show == null) continue;
          final ids = show['ids'] as Map<String, dynamic>? ?? {};
          final tmdbId = ids['tmdb'] as int?;
          if (tmdbId == null) continue;

          final uid = MyListService.movieId(tmdbId, 'tv');
          if (!MyListService().contains(uid)) {
            final poster = await _fetchTmdbPoster(tmdbId, 'tv');
            await MyListService().addMovie(
              tmdbId: tmdbId,
              imdbId: ids['imdb']?.toString(),
              title: show['title']?.toString() ?? 'Unknown',
              posterPath: poster,
              mediaType: 'tv',
              voteAverage: (show['rating'] as num?)?.toDouble() ?? 0,
              releaseDate: show['first_aired']?.toString().split('T').first ?? '',
            );
            imported++;
          }
        }
      }

      debugPrint('[Trakt] Imported $imported items from watchlist');
    } catch (e) {
      debugPrint('[Trakt] Watchlist import error: $e');
    }
    return imported;
  }

  /// Push a local My List item to the Trakt watchlist.
  Future<bool> addToWatchlist({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
  }) async {
    if (tmdbId == null && imdbId == null) return false;
    final token = await _getValidToken();
    if (token == null) return false;

    final type = mediaType == 'tv' || mediaType == 'series' ? 'shows' : 'movies';
    final ids = <String, dynamic>{};
    if (tmdbId != null) ids['tmdb'] = tmdbId;
    if (imdbId != null) ids['imdb'] = imdbId;
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/sync/watchlist'),
        headers: _authHeaders(token),
        body: json.encode({
          type: [
            {'ids': ids}
          ]
        }),
      );
      debugPrint('[Trakt] Add to watchlist ($type ids:$ids): ${resp.statusCode}');
      return resp.statusCode == 201 || resp.statusCode == 200;
    } catch (e) {
      debugPrint('[Trakt] Add to watchlist error: $e');
      return false;
    }
  }

  /// Remove an item from the Trakt watchlist.
  Future<bool> removeFromWatchlist({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
  }) async {
    if (tmdbId == null && imdbId == null) return false;
    final token = await _getValidToken();
    if (token == null) return false;

    final type = mediaType == 'tv' || mediaType == 'series' ? 'shows' : 'movies';
    final ids = <String, dynamic>{};
    if (tmdbId != null) ids['tmdb'] = tmdbId;
    if (imdbId != null) ids['imdb'] = imdbId;
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/sync/watchlist/remove'),
        headers: _authHeaders(token),
        body: json.encode({
          type: [
            {'ids': ids}
          ]
        }),
      );
      debugPrint('[Trakt] Remove from watchlist ($type ids:$ids): ${resp.statusCode}');
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('[Trakt] Remove from watchlist error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  S C R O B B L E   —   R E A L - T I M E   T R A C K I N G
  // ═══════════════════════════════════════════════════════════════════════

  /// POST /scrobble/start — call when playback begins.
  Future<bool> scrobbleStart({
    required int tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    required double progressPercent,
  }) async {
    return _scrobble('start',
        tmdbId: tmdbId, mediaType: mediaType,
        season: season, episode: episode,
        progressPercent: progressPercent);
  }

  /// POST /scrobble/pause — call when playback pauses.
  Future<bool> scrobblePause({
    required int tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    required double progressPercent,
  }) async {
    return _scrobble('pause',
        tmdbId: tmdbId, mediaType: mediaType,
        season: season, episode: episode,
        progressPercent: progressPercent);
  }

  /// POST /scrobble/stop — call when playback stops.
  /// If progress >= 80 %, Trakt marks it as watched automatically.
  Future<bool> scrobbleStop({
    required int tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    required double progressPercent,
  }) async {
    return _scrobble('stop',
        tmdbId: tmdbId, mediaType: mediaType,
        season: season, episode: episode,
        progressPercent: progressPercent);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  H I S T O R Y   —   M A R K   A S   W A T C H E D
  // ═══════════════════════════════════════════════════════════════════════

  /// Explicitly add an item to history (watched).
  Future<bool> addToHistory({
    required int tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    DateTime? watchedAt,
  }) async {
    final token = await _getValidToken();
    if (token == null) return false;

    final body = <String, dynamic>{};
    final at = (watchedAt ?? DateTime.now()).toUtc().toIso8601String();

    if (mediaType == 'tv' && season != null && episode != null) {
      body['episodes'] = [
        {
          'watched_at': at,
          'ids': {'tmdb': tmdbId},
          // Trakt can find the episode from show tmdbId + S/E numbers
        }
      ];
      // Alternative: send show + seasons array for absolute correctness
      body['shows'] = [
        {
          'ids': {'tmdb': tmdbId},
          'seasons': [
            {
              'number': season,
              'episodes': [
                {'number': episode, 'watched_at': at}
              ]
            }
          ]
        }
      ];
      // Remove the flat episodes since we're using the nested shows format
      body.remove('episodes');
    } else {
      body['movies'] = [
        {
          'watched_at': at,
          'ids': {'tmdb': tmdbId},
        }
      ];
    }

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/sync/history'),
        headers: _authHeaders(token),
        body: json.encode(body),
      );
      debugPrint('[Trakt] Add to history: ${resp.statusCode}');
      return resp.statusCode == 201 || resp.statusCode == 200;
    } catch (e) {
      debugPrint('[Trakt] Add to history error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  P L A Y B A C K   P R O G R E S S   ( R E S U M E )
  // ═══════════════════════════════════════════════════════════════════════

  /// GET /sync/playback — items the user is still in the middle of.
  /// Returns raw Trakt response list.
  Future<List<Map<String, dynamic>>> getPlaybackProgress() async {
    final token = await _getValidToken();
    if (token == null) return [];

    final results = <Map<String, dynamic>>[];

    try {
      // Movies in progress
      final moviesResp = await http.get(
        Uri.parse('$_baseUrl/sync/playback/movies'),
        headers: _authHeaders(token),
      );
      if (moviesResp.statusCode == 200) {
        final List items = json.decode(moviesResp.body);
        for (final item in items) {
          results.add(Map<String, dynamic>.from(item as Map));
        }
      }

      // Episodes in progress
      final episodesResp = await http.get(
        Uri.parse('$_baseUrl/sync/playback/episodes'),
        headers: _authHeaders(token),
      );
      if (episodesResp.statusCode == 200) {
        final List items = json.decode(episodesResp.body);
        for (final item in items) {
          results.add(Map<String, dynamic>.from(item as Map));
        }
      }

      debugPrint('[Trakt] Got ${results.length} playback progress items');
    } catch (e) {
      debugPrint('[Trakt] Get playback error: $e');
    }
    return results;
  }

  /// Import Trakt playback progress → local Continue Watching.
  /// Only imports items not already in local history.
  Future<int> importPlaybackToWatchHistory() async {
    final traktItems = await getPlaybackProgress();
    if (traktItems.isEmpty) return 0;

    int imported = 0;

    for (final item in traktItems) {
      try {
        final progress = (item['progress'] as num?)?.toDouble() ?? 0;
        final type = item['type']?.toString(); // 'movie' or 'episode'

        int? tmdbId;
        String? imdbId;
        String title = 'Unknown';
        String posterPath = '';
        String mediaType = 'movie';
        int? season;
        int? episode;
        String? episodeTitle;

        if (type == 'movie') {
          final movie = item['movie'] as Map<String, dynamic>? ?? {};
          final ids = movie['ids'] as Map<String, dynamic>? ?? {};
          tmdbId = ids['tmdb'] as int?;
          imdbId = ids['imdb']?.toString();
          title = movie['title']?.toString() ?? 'Unknown';
          mediaType = 'movie';
        } else if (type == 'episode') {
          final ep = item['episode'] as Map<String, dynamic>? ?? {};
          final show = item['show'] as Map<String, dynamic>? ?? {};
          final showIds = show['ids'] as Map<String, dynamic>? ?? {};
          tmdbId = showIds['tmdb'] as int?;
          imdbId = showIds['imdb']?.toString();
          title = show['title']?.toString() ?? 'Unknown';
          season = ep['season'] as int?;
          episode = ep['number'] as int?;
          episodeTitle = ep['title']?.toString();
          mediaType = 'tv';
        }

        if (tmdbId == null) continue;

        // Fetch poster from TMDB
        posterPath = await _fetchTmdbPoster(tmdbId, mediaType);

        // Check if already in local history
        final existing = await WatchHistoryService().getProgress(
          tmdbId,
          season: season,
          episode: episode,
        );
        if (existing != null) continue;

        // Estimate position/duration from progress percentage.
        // We don't have real duration from Trakt playback, use 100min default.
        // The actual position matters less — what matters is having the entry.
        const estimatedDurationMs = 6000000; // 100 minutes
        final estimatedPositionMs = (progress / 100 * estimatedDurationMs).round();

        await WatchHistoryService().saveProgress(
          tmdbId: tmdbId,
          imdbId: imdbId,
          title: title,
          posterPath: posterPath,
          method: 'trakt_import',
          sourceId: 'trakt',
          position: estimatedPositionMs,
          duration: estimatedDurationMs,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
          mediaType: mediaType,
        );
        imported++;
      } catch (e) {
        debugPrint('[Trakt] Import playback item error: $e');
      }
    }

    debugPrint('[Trakt] Imported $imported playback items to watch history');
    return imported;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  F U L L   S Y N C   ( called after login / app start )
  // ═══════════════════════════════════════════════════════════════════════

  /// Run a full import from Trakt to local data.
  /// Safe to call multiple times — only runs once per session unless forced.
  Future<void> fullSync({bool force = false}) async {
    if (!force && _initialSyncDone) return;
    final loggedIn = await isLoggedIn();
    if (!loggedIn) return;

    debugPrint('[Trakt] Starting full sync...');
    final watchlistCount = await importWatchlistToMyList();
    final playbackCount = await importPlaybackToWatchHistory();
    _initialSyncDone = true;
    debugPrint('[Trakt] Full sync done — watchlist: $watchlistCount, playback: $playbackCount');
  }

  /// Push the entire local My List to Trakt watchlist (bulk export).
  Future<int> exportMyListToWatchlist() async {
    final token = await _getValidToken();
    if (token == null) return 0;

    final items = MyListService().items;
    final movies = <Map<String, dynamic>>[];
    final shows = <Map<String, dynamic>>[];

    for (final item in items) {
      final tmdbId = item['tmdbId'] as int?;
      final imdbId = item['imdbId']?.toString();
      if (tmdbId == null && imdbId == null) continue;
      final mediaType = item['mediaType']?.toString() ?? 'movie';
      final ids = <String, dynamic>{};
      if (tmdbId != null) ids['tmdb'] = tmdbId;
      if (imdbId != null) ids['imdb'] = imdbId;
      final entry = {'ids': ids};
      if (mediaType == 'tv' || mediaType == 'series') {
        shows.add(entry);
      } else {
        movies.add(entry);
      }
    }

    if (movies.isEmpty && shows.isEmpty) return 0;

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/sync/watchlist'),
        headers: _authHeaders(token),
        body: json.encode({
          if (movies.isNotEmpty) 'movies': movies,
          if (shows.isNotEmpty) 'shows': shows,
        }),
      );
      final total = movies.length + shows.length;
      debugPrint('[Trakt] Exported $total items to watchlist: ${resp.statusCode}');
      return resp.statusCode == 201 || resp.statusCode == 200 ? total : 0;
    } catch (e) {
      debugPrint('[Trakt] Export watchlist error: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  U S E R   P R O F I L E
  // ═══════════════════════════════════════════════════════════════════════

  /// Get the logged-in user's profile (username, vip status, etc.)
  Future<Map<String, dynamic>?> getUserProfile() async {
    final token = await _getValidToken();
    if (token == null) return null;

    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/users/me'),
        headers: _authHeaders(token),
      );
      if (resp.statusCode == 200) {
        return json.decode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[Trakt] Get profile error: $e');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  I N T E R N A L   H E L P E R S
  // ═══════════════════════════════════════════════════════════════════════

  Map<String, String> get _publicHeaders => {
        'Content-Type': 'application/json',
        'trakt-api-version': '2',
        'trakt-api-key': _clientId,
      };

  Map<String, String> _authHeaders(String token) => {
        'Content-Type': 'application/json',
        'trakt-api-version': '2',
        'trakt-api-key': _clientId,
        'Authorization': 'Bearer $token',
      };

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await _storage.write(key: _keyAccessToken, value: data['access_token']);
    await _storage.write(key: _keyRefreshToken, value: data['refresh_token']);
    final expiresIn = data['expires_in'] as int? ?? 7776000; // ~90 days
    final expiresAt = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .toIso8601String();
    await _storage.write(key: _keyExpiresAt, value: expiresAt);
    debugPrint('[Trakt] Tokens saved, expires in ${expiresIn ~/ 86400} days');
  }

  /// Get a valid access token, refreshing if near expiry.
  Future<String?> _getValidToken() async {
    final token = await _storage.read(key: _keyAccessToken);
    if (token == null) return null;

    final expiresAtStr = await _storage.read(key: _keyExpiresAt);
    if (expiresAtStr != null) {
      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt != null &&
          DateTime.now().isAfter(expiresAt.subtract(const Duration(days: 7)))) {
        // Token expires within 7 days — refresh it
        debugPrint('[Trakt] Token nearing expiry, refreshing...');
        final refreshed = await refreshToken();
        if (refreshed) {
          return await _storage.read(key: _keyAccessToken);
        }
        // If refresh failed but token isn't actually expired yet, use it
        if (DateTime.now().isBefore(expiresAt)) return token;
        return null;
      }
    }
    return token;
  }

  Future<bool> _scrobble(
    String action, {
    required int tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    required double progressPercent,
  }) async {
    final token = await _getValidToken();
    if (token == null) return false;

    final body = <String, dynamic>{
      'progress': progressPercent.clamp(0, 100),
    };

    if (mediaType == 'tv' && season != null && episode != null) {
      body['show'] = {
        'ids': {'tmdb': tmdbId}
      };
      body['episode'] = {
        'season': season,
        'number': episode,
      };
    } else {
      body['movie'] = {
        'ids': {'tmdb': tmdbId}
      };
    }

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/scrobble/$action'),
        headers: _authHeaders(token),
        body: json.encode(body),
      );
      debugPrint('[Trakt] Scrobble $action (tmdb:$tmdbId S:$season E:$episode ${progressPercent.toStringAsFixed(1)}%): ${resp.statusCode}');
      // 200 = success, 409 = already scrobbled (OK), 422 = progress too low
      return resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 409;
    } catch (e) {
      debugPrint('[Trakt] Scrobble error: $e');
      return false;
    }
  }

  // ── TMDB poster resolution ─────────────────────────────────────────────
  static const String _tmdbApiKey = 'c3515fdc674ea2bd7b514f4bc3616a4a';
  static const String _tmdbBase = 'https://api.themoviedb.org/3';

  /// Fetch the TMDB poster_path for a given TMDB ID.
  /// Returns the relative path (e.g. "/abc123.jpg") or empty string.
  Future<String> _fetchTmdbPoster(int tmdbId, String mediaType) async {
    try {
      final type = (mediaType == 'tv' || mediaType == 'series') ? 'tv' : 'movie';
      final resp = await http.get(
        Uri.parse('$_tmdbBase/$type/$tmdbId?api_key=$_tmdbApiKey'),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        return data['poster_path']?.toString() ?? '';
      }
    } catch (e) {
      debugPrint('[Trakt] TMDB poster fetch failed for $tmdbId: $e');
    }
    return '';
  }
}
